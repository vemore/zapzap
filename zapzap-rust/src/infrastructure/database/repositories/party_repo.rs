use std::sync::Arc;

use async_trait::async_trait;
use sqlx::{SqliteConnection, SqlitePool};

use crate::domain::entities::{
    Party, PartyPlayer, PartyStatus, PartyVisibility, Round, RoundStatus,
};
use crate::domain::repositories::{
    GameAction, PartyRepository, PlayerGameResult, RepositoryError, SeatReplacement,
    VersionedGameState,
};
use crate::domain::value_objects::{GameState, PartySettings};
use crate::infrastructure::services::{Clock, SystemClock};

/// SQLite implementation of PartyRepository
pub struct SqlitePartyRepository {
    pool: SqlitePool,
    /// The time a game-state write stamps the turn deadline with
    clock: Arc<dyn Clock>,
}

impl SqlitePartyRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self::with_clock(pool, Arc::new(SystemClock))
    }

    /// A repository whose game-state writes read `clock` (a test's `ManualClock`)
    pub fn with_clock(pool: SqlitePool, clock: Arc<dyn Clock>) -> Self {
        Self { pool, clock }
    }

    /// Get a reference to the database pool for direct queries
    pub fn get_db(&self) -> &SqlitePool {
        &self.pool
    }

    fn row_to_party(row: &sqlx::sqlite::SqliteRow) -> Party {
        use sqlx::Row;

        let visibility_str: String = row.get("visibility");
        let status_str: String = row.get("status");
        let settings_json: String = row.get("settings_json");

        Party {
            id: row.get("id"),
            name: row.get("name"),
            owner_id: row.get("owner_id"),
            invite_code: row.get("invite_code"),
            visibility: PartyVisibility::from_str(&visibility_str)
                .unwrap_or(PartyVisibility::Public),
            status: PartyStatus::from_str(&status_str).unwrap_or(PartyStatus::Waiting),
            settings: PartySettings::from_stored_json(&settings_json),
            current_round_id: row.get("current_round_id"),
            created_at: row.get("created_at"),
            updated_at: row.get("updated_at"),
        }
    }

    fn row_to_round(row: &sqlx::sqlite::SqliteRow) -> Round {
        use sqlx::Row;

        let status_str: String = row.get("status");

        Round {
            id: row.get("id"),
            party_id: row.get("party_id"),
            round_number: row.get::<i32, _>("round_number") as u32,
            status: RoundStatus::from_str(&status_str).unwrap_or(RoundStatus::Active),
            current_turn: row.get::<i32, _>("current_turn") as u8,
            current_action: row.get("current_action"),
            created_at: row.get("created_at"),
            finished_at: row.get("finished_at"),
        }
    }

    fn row_to_player(row: &sqlx::sqlite::SqliteRow) -> PartyPlayer {
        use sqlx::Row;

        PartyPlayer {
            id: row.get("id"),
            party_id: row.get("party_id"),
            user_id: row.get("user_id"),
            player_index: row.get::<i32, _>("player_index") as u8,
            joined_at: row.get("joined_at"),
        }
    }
}

#[async_trait]
impl PartyRepository for SqlitePartyRepository {
    async fn find_by_id(&self, id: &str) -> Result<Option<Party>, RepositoryError> {
        let row = sqlx::query("SELECT * FROM parties WHERE id = ?")
            .bind(id)
            .fetch_optional(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(row.as_ref().map(Self::row_to_party))
    }

    async fn find_by_invite_code(&self, code: &str) -> Result<Option<Party>, RepositoryError> {
        let row = sqlx::query("SELECT * FROM parties WHERE invite_code = ?")
            .bind(code)
            .fetch_optional(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(row.as_ref().map(Self::row_to_party))
    }

    async fn find_public_parties(
        &self,
        status: Option<PartyStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Party>, RepositoryError> {
        let rows = match status {
            Some(s) => {
                sqlx::query(
                    "SELECT * FROM parties WHERE visibility = 'public' AND status = ? ORDER BY created_at DESC LIMIT ? OFFSET ?",
                )
                .bind(s.as_str())
                .bind(limit as i32)
                .bind(offset as i32)
                .fetch_all(&self.pool)
                .await
            }
            None => {
                // By default, exclude finished parties from the list
                sqlx::query(
                    "SELECT * FROM parties WHERE visibility = 'public' AND status != 'finished' ORDER BY created_at DESC LIMIT ? OFFSET ?",
                )
                .bind(limit as i32)
                .bind(offset as i32)
                .fetch_all(&self.pool)
                .await
            }
        }
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(rows.iter().map(Self::row_to_party).collect())
    }

    async fn find_public_parties_with_counts(
        &self,
        status: Option<PartyStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<crate::domain::repositories::PartyWithPlayerCount>, RepositoryError> {
        use sqlx::Row;

        // Query parties with player counts in one go
        let query = match status {
            Some(s) => sqlx::query(
                r#"
                    SELECT p.*,
                           COUNT(pp.id) as player_count,
                           GROUP_CONCAT(pp.user_id) as player_ids
                    FROM parties p
                    LEFT JOIN party_players pp ON p.id = pp.party_id
                    WHERE p.visibility = 'public' AND p.status = ?
                    GROUP BY p.id
                    ORDER BY p.created_at DESC
                    LIMIT ? OFFSET ?
                    "#,
            )
            .bind(s.as_str())
            .bind(limit as i32)
            .bind(offset as i32),
            None => sqlx::query(
                r#"
                    SELECT p.*,
                           COUNT(pp.id) as player_count,
                           GROUP_CONCAT(pp.user_id) as player_ids
                    FROM parties p
                    LEFT JOIN party_players pp ON p.id = pp.party_id
                    WHERE p.visibility = 'public' AND p.status != 'finished'
                    GROUP BY p.id
                    ORDER BY p.created_at DESC
                    LIMIT ? OFFSET ?
                    "#,
            )
            .bind(limit as i32)
            .bind(offset as i32),
        };

        let rows = query
            .fetch_all(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        let mut result = Vec::with_capacity(rows.len());
        for row in &rows {
            let party = Self::row_to_party(row);
            let player_count: i32 = row.get("player_count");
            let player_ids_str: Option<String> = row.get("player_ids");
            let player_user_ids: Vec<String> = player_ids_str
                .map(|s| s.split(',').map(String::from).collect())
                .unwrap_or_default();

            result.push(crate::domain::repositories::PartyWithPlayerCount {
                party,
                player_count: player_count as usize,
                player_user_ids,
            });
        }

        Ok(result)
    }

    async fn find_by_owner(
        &self,
        owner_id: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Party>, RepositoryError> {
        let rows = sqlx::query(
            "SELECT * FROM parties WHERE owner_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?",
        )
        .bind(owner_id)
        .bind(limit as i32)
        .bind(offset as i32)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(rows.iter().map(Self::row_to_party).collect())
    }

    async fn find_all_parties(
        &self,
        status: Option<PartyStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Party>, RepositoryError> {
        let rows = match status {
            Some(s) => sqlx::query(
                "SELECT * FROM parties WHERE status = ? ORDER BY created_at DESC LIMIT ? OFFSET ?",
            )
            .bind(s.as_str())
            .bind(limit as i32)
            .bind(offset as i32)
            .fetch_all(&self.pool)
            .await,
            None => {
                sqlx::query("SELECT * FROM parties ORDER BY created_at DESC LIMIT ? OFFSET ?")
                    .bind(limit as i32)
                    .bind(offset as i32)
                    .fetch_all(&self.pool)
                    .await
            }
        }
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(rows.iter().map(Self::row_to_party).collect())
    }

    async fn save(&self, party: &Party) -> Result<(), RepositoryError> {
        let settings_json = serde_json::to_string(&party.settings)
            .map_err(|e| RepositoryError::Database(e.to_string()))?;
        let now = chrono::Utc::now().timestamp();

        sqlx::query(
            r#"
            INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json, current_round_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                owner_id = excluded.owner_id,
                invite_code = excluded.invite_code,
                visibility = excluded.visibility,
                status = excluded.status,
                settings_json = excluded.settings_json,
                current_round_id = excluded.current_round_id,
                updated_at = ?
            "#,
        )
        .bind(&party.id)
        .bind(&party.name)
        .bind(&party.owner_id)
        .bind(&party.invite_code)
        .bind(party.visibility.as_str())
        .bind(party.status.as_str())
        .bind(&settings_json)
        .bind(&party.current_round_id)
        .bind(party.created_at)
        .bind(party.updated_at)
        .bind(now)
        .execute(&self.pool)
        .await
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(())
    }

    async fn delete(&self, id: &str) -> Result<(), RepositoryError> {
        // Delete related data first
        sqlx::query("DELETE FROM party_players WHERE party_id = ?")
            .bind(id)
            .execute(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        sqlx::query("DELETE FROM game_state WHERE party_id = ?")
            .bind(id)
            .execute(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        sqlx::query("DELETE FROM rounds WHERE party_id = ?")
            .bind(id)
            .execute(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        sqlx::query("DELETE FROM parties WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(())
    }

    async fn update_status(&self, id: &str, status: PartyStatus) -> Result<(), RepositoryError> {
        let now = chrono::Utc::now().timestamp();

        sqlx::query("UPDATE parties SET status = ?, updated_at = ? WHERE id = ?")
            .bind(status.as_str())
            .bind(now)
            .bind(id)
            .execute(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(())
    }

    async fn get_party_players(&self, party_id: &str) -> Result<Vec<PartyPlayer>, RepositoryError> {
        let rows =
            sqlx::query("SELECT * FROM party_players WHERE party_id = ? ORDER BY player_index ASC")
                .bind(party_id)
                .fetch_all(&self.pool)
                .await
                .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(rows.iter().map(Self::row_to_player).collect())
    }

    async fn add_party_player(
        &self,
        party_id: &str,
        user_id: &str,
        player_index: u8,
    ) -> Result<(), RepositoryError> {
        let now = chrono::Utc::now().timestamp();

        sqlx::query(
            "INSERT INTO party_players (party_id, user_id, player_index, joined_at) VALUES (?, ?, ?, ?)",
        )
        .bind(party_id)
        .bind(user_id)
        .bind(player_index as i32)
        .bind(now)
        .execute(&self.pool)
        .await
        .map_err(|e| {
            let seat_taken_by_user = e.as_database_error().is_some_and(|d| {
                d.is_unique_violation() && d.message().contains("party_players.user_id")
            });
            if seat_taken_by_user {
                RepositoryError::AlreadyExists(format!("{user_id} in party {party_id}"))
            } else {
                RepositoryError::Database(e.to_string())
            }
        })?;

        Ok(())
    }

    async fn set_player_index(
        &self,
        party_id: &str,
        user_id: &str,
        player_index: u8,
    ) -> Result<(), RepositoryError> {
        sqlx::query("UPDATE party_players SET player_index = ? WHERE party_id = ? AND user_id = ?")
            .bind(player_index as i32)
            .bind(party_id)
            .bind(user_id)
            .execute(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(())
    }

    async fn remove_party_player(
        &self,
        party_id: &str,
        user_id: &str,
    ) -> Result<(), RepositoryError> {
        sqlx::query("DELETE FROM party_players WHERE party_id = ? AND user_id = ?")
            .bind(party_id)
            .bind(user_id)
            .execute(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(())
    }

    async fn is_player_in_party(
        &self,
        party_id: &str,
        user_id: &str,
    ) -> Result<bool, RepositoryError> {
        let count: i32 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM party_players WHERE party_id = ? AND user_id = ?",
        )
        .bind(party_id)
        .bind(user_id)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(count > 0)
    }

    async fn get_player_index(
        &self,
        party_id: &str,
        user_id: &str,
    ) -> Result<Option<u8>, RepositoryError> {
        let result: Option<i32> = sqlx::query_scalar(
            "SELECT player_index FROM party_players WHERE party_id = ? AND user_id = ?",
        )
        .bind(party_id)
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(result.map(|i| i as u8))
    }

    async fn human_seats(&self, party_id: &str) -> Result<Vec<u8>, RepositoryError> {
        let seats: Vec<i64> = sqlx::query_scalar(
            "SELECT pp.player_index FROM party_players pp JOIN users u ON u.id = pp.user_id \
             WHERE pp.party_id = ? AND u.user_type = 'human' ORDER BY pp.player_index",
        )
        .bind(party_id)
        .fetch_all(&self.pool)
        .await
        .map_err(db_err)?;
        Ok(seats.into_iter().map(|seat| seat as u8).collect())
    }

    async fn replace_player(
        &self,
        replacement: &SeatReplacement<'_>,
    ) -> Result<(), RepositoryError> {
        let now = chrono::Utc::now().timestamp();
        let party_id = replacement.party_id;
        // The write lock up front, as `delete_account` takes it: a concurrent write waits
        // out the busy timeout rather than failing on a read-to-write upgrade
        let mut tx = self
            .pool
            .begin_with("BEGIN IMMEDIATE")
            .await
            .map_err(db_err)?;

        // The compare-and-swap every move goes through: a move that came first wins, and
        // the transaction rolls back when it returns
        write_game_state_if_unchanged(
            &mut tx,
            party_id,
            replacement.state,
            replacement.expected_version,
            self.clock.now_millis(),
            None,
        )
        .await?;

        // A stand-in created for this seat exists only if the ejection happens
        if let Some(bot) = replacement.new_bot {
            sqlx::query(
                "INSERT INTO users (id, username, user_type, bot_difficulty, created_at, \
                 updated_at) VALUES (?, ?, 'bot', ?, ?, ?)",
            )
            .bind(&bot.id)
            .bind(&bot.username)
            .bind(bot.bot_difficulty.map(|d| d.as_str()))
            .bind(bot.created_at)
            .bind(bot.updated_at)
            .execute(&mut *tx)
            .await
            .map_err(db_err)?;
        }

        let moved = sqlx::query(
            "UPDATE party_players SET user_id = ? \
             WHERE party_id = ? AND player_index = ? AND user_id = ?",
        )
        .bind(replacement.bot_id)
        .bind(party_id)
        .bind(replacement.player_index as i32)
        .bind(replacement.human_id)
        .execute(&mut *tx)
        .await
        .map_err(db_err)?;
        if moved.rows_affected() == 0 {
            return Err(RepositoryError::Conflict(format!(
                "seat {} of party {party_id} is no longer {}'s",
                replacement.player_index, replacement.human_id
            )));
        }

        if let Some(owner) = replacement.new_owner_id {
            sqlx::query(
                "UPDATE parties SET owner_id = ?, updated_at = ? WHERE id = ? AND owner_id = ?",
            )
            .bind(owner)
            .bind(now)
            .bind(party_id)
            .bind(replacement.human_id)
            .execute(&mut *tx)
            .await
            .map_err(db_err)?;
        }

        // The human's game is a loss, whatever the bot does with the seat. The seats take
        // positions 1..=seat_count when the game ends; the players ejected before rank
        // after every seat, the latest ejected first, so the earlier ones move down one.
        let seat_count = i32::from(replacement.seat_count);
        sqlx::query(
            "UPDATE player_game_results SET finish_position = finish_position + 1 \
             WHERE party_id = ? AND finish_position > ?",
        )
        .bind(party_id)
        .bind(seat_count)
        .execute(&mut *tx)
        .await
        .map_err(db_err)?;
        let state = replacement.state;
        sqlx::query(
            "INSERT INTO player_game_results \
             (party_id, user_id, final_score, finish_position, rounds_played, is_winner, created_at) \
             VALUES (?, ?, ?, ?, ?, 0, ?) \
             ON CONFLICT(party_id, user_id) DO UPDATE SET \
                final_score = excluded.final_score, \
                finish_position = excluded.finish_position, \
                rounds_played = excluded.rounds_played, \
                is_winner = 0",
        )
        .bind(party_id)
        .bind(replacement.human_id)
        .bind(i32::from(state.get_score(replacement.player_index)))
        .bind(seat_count + 1)
        .bind(i32::from(state.round_number))
        .bind(now)
        .execute(&mut *tx)
        .await
        .map_err(db_err)?;

        tx.commit().await.map_err(db_err)
    }

    async fn get_round_by_id(&self, id: &str) -> Result<Option<Round>, RepositoryError> {
        let row = sqlx::query("SELECT * FROM rounds WHERE id = ?")
            .bind(id)
            .fetch_optional(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(row.as_ref().map(Self::row_to_round))
    }

    async fn save_round(&self, round: &Round) -> Result<(), RepositoryError> {
        sqlx::query(
            r#"
            INSERT INTO rounds (id, party_id, round_number, status, current_turn, current_action, created_at, finished_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                status = excluded.status,
                current_turn = excluded.current_turn,
                current_action = excluded.current_action,
                finished_at = excluded.finished_at
            "#,
        )
        .bind(&round.id)
        .bind(&round.party_id)
        .bind(round.round_number as i32)
        .bind(round.status.as_str())
        .bind(round.current_turn as i32)
        .bind(&round.current_action)
        .bind(round.created_at)
        .bind(round.finished_at)
        .execute(&self.pool)
        .await
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(())
    }

    async fn get_current_round(&self, party_id: &str) -> Result<Option<Round>, RepositoryError> {
        // First try to get the round by party's current_round_id
        let row = sqlx::query(
            "SELECT r.* FROM rounds r
             JOIN parties p ON r.id = p.current_round_id
             WHERE p.id = ?",
        )
        .bind(party_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        if row.is_some() {
            return Ok(row.as_ref().map(Self::row_to_round));
        }

        // Fallback: get the latest round for the party
        let row = sqlx::query(
            "SELECT * FROM rounds WHERE party_id = ? ORDER BY round_number DESC LIMIT 1",
        )
        .bind(party_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(row.as_ref().map(Self::row_to_round))
    }

    async fn get_versioned_game_state(
        &self,
        party_id: &str,
    ) -> Result<Option<VersionedGameState>, RepositoryError> {
        let row: Option<(String, i64)> =
            sqlx::query_as("SELECT state_json, version FROM game_state WHERE party_id = ?")
                .bind(party_id)
                .fetch_optional(&self.pool)
                .await
                .map_err(|e| RepositoryError::Database(e.to_string()))?;

        match row {
            Some((json, version)) => {
                // Parse the JSON into GameState
                match GameState::from_json(&json) {
                    Ok(state) => Ok(Some(VersionedGameState { state, version })),
                    Err(e) => {
                        tracing::error!("Failed to parse game state JSON: {}", e);
                        Err(RepositoryError::Database(format!(
                            "Invalid game state JSON: {}",
                            e
                        )))
                    }
                }
            }
            None => Ok(None),
        }
    }

    async fn save_game_state(
        &self,
        party_id: &str,
        state: &GameState,
    ) -> Result<(), RepositoryError> {
        let now = chrono::Utc::now().timestamp();

        // Serialize GameState to JSON, the deadline of the turn under way stamped
        let mut state = state.clone();
        state.stamp_turn_deadline(self.clock.now_millis());
        let state_json = state.to_json();

        // A new version even when it replaces a state: a write based on the old one is
        // refused by `update_game_state`
        sqlx::query(
            r#"
            INSERT INTO game_state (party_id, state_json, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(party_id) DO UPDATE SET
                state_json = excluded.state_json,
                updated_at = excluded.updated_at,
                version = game_state.version + 1
            "#,
        )
        .bind(party_id)
        .bind(state_json)
        .bind(now)
        .execute(&self.pool)
        .await
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(())
    }

    async fn update_game_state(
        &self,
        party_id: &str,
        state: &GameState,
        expected_version: i64,
    ) -> Result<(), RepositoryError> {
        let mut conn = self.pool.acquire().await.map_err(db_err)?;
        write_game_state_if_unchanged(
            &mut conn,
            party_id,
            state,
            expected_version,
            self.clock.now_millis(),
            None,
        )
        .await
    }

    async fn update_game_state_for_player(
        &self,
        party_id: &str,
        state: &GameState,
        expected_version: i64,
        player_index: u8,
        user_id: &str,
    ) -> Result<(), RepositoryError> {
        let mut conn = self.pool.acquire().await.map_err(db_err)?;
        write_game_state_if_unchanged(
            &mut conn,
            party_id,
            state,
            expected_version,
            self.clock.now_millis(),
            Some((player_index, user_id)),
        )
        .await
    }

    async fn parties_past_turn_deadline(&self, now: u64) -> Result<Vec<String>, RepositoryError> {
        // `turnDeadline` is null unless a timed seat is on turn (`stamp_turn_deadline`)
        sqlx::query_scalar(
            "SELECT g.party_id FROM game_state g JOIN parties p ON p.id = g.party_id \
             WHERE p.status = 'playing' AND json_extract(g.state_json, '$.turnDeadline') <= ?",
        )
        .bind(i64::try_from(now).unwrap_or(i64::MAX))
        .fetch_all(&self.pool)
        .await
        .map_err(db_err)
    }

    async fn save_game_action(&self, action: &GameAction) -> Result<(), RepositoryError> {
        sqlx::query(
            r#"
            INSERT INTO game_actions (
                party_id, round_number, turn_number, player_index, user_id, is_human,
                action_type, action_data, hand_before, hand_value_before, scores_before,
                opponent_hand_sizes, deck_size, last_cards_played, hand_after, hand_value_after, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            "#,
        )
        .bind(&action.party_id)
        .bind(action.round_number as i32)
        .bind(action.turn_number as i32)
        .bind(action.player_index as i32)
        .bind(&action.user_id)
        .bind(action.is_human as i32)
        .bind(&action.action_type)
        .bind(&action.action_data)
        .bind(&action.hand_before)
        .bind(action.hand_value_before as i32)
        .bind(&action.scores_before)
        .bind(&action.opponent_hand_sizes)
        .bind(action.deck_size as i32)
        .bind(&action.last_cards_played)
        .bind(&action.hand_after)
        .bind(action.hand_value_after.map(|v| v as i32))
        .bind(action.created_at)
        .execute(&self.pool)
        .await
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(())
    }

    async fn get_game_actions(
        &self,
        party_id: &str,
        round_number: u32,
    ) -> Result<Vec<GameAction>, RepositoryError> {
        let rows = sqlx::query(
            "SELECT * FROM game_actions WHERE party_id = ? AND round_number = ? ORDER BY turn_number ASC",
        )
        .bind(party_id)
        .bind(round_number as i32)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        let actions = rows
            .into_iter()
            .map(|row| {
                use sqlx::Row;
                GameAction {
                    party_id: row.get("party_id"),
                    round_number: row.get::<i32, _>("round_number") as u32,
                    turn_number: row.get::<i32, _>("turn_number") as u32,
                    player_index: row.get::<i32, _>("player_index") as u8,
                    user_id: row.get("user_id"),
                    is_human: row.get::<i32, _>("is_human") != 0,
                    action_type: row.get("action_type"),
                    action_data: row.get("action_data"),
                    hand_before: row.get("hand_before"),
                    hand_value_before: row.get::<i32, _>("hand_value_before") as u16,
                    scores_before: row.get("scores_before"),
                    opponent_hand_sizes: row.get("opponent_hand_sizes"),
                    deck_size: row.get::<i32, _>("deck_size") as u32,
                    last_cards_played: row.get("last_cards_played"),
                    hand_after: row.get("hand_after"),
                    hand_value_after: row
                        .get::<Option<i32>, _>("hand_value_after")
                        .map(|v| v as u16),
                    created_at: row.get("created_at"),
                }
            })
            .collect();

        Ok(actions)
    }

    async fn save_round_scores(
        &self,
        party_id: &str,
        round_number: u32,
        scores: Vec<crate::domain::repositories::RoundScoreEntry>,
    ) -> Result<(), RepositoryError> {
        let now = chrono::Utc::now().timestamp();

        for score in scores {
            let hand_cards_json = serde_json::to_string(&score.hand_cards).unwrap_or_default();

            sqlx::query(
                r#"
                INSERT INTO round_scores (
                    party_id, round_number, user_id, player_index,
                    score_this_round, total_score_after, hand_points,
                    is_zapzap_caller, zapzap_success, was_counteracted,
                    hand_cards, is_lowest_hand, is_eliminated, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(party_id, round_number, user_id) DO UPDATE SET
                    score_this_round = excluded.score_this_round,
                    total_score_after = excluded.total_score_after,
                    hand_points = excluded.hand_points,
                    is_zapzap_caller = excluded.is_zapzap_caller,
                    zapzap_success = excluded.zapzap_success,
                    was_counteracted = excluded.was_counteracted,
                    hand_cards = excluded.hand_cards,
                    is_lowest_hand = excluded.is_lowest_hand,
                    is_eliminated = excluded.is_eliminated
                "#,
            )
            .bind(party_id)
            .bind(round_number as i32)
            .bind(&score.user_id)
            .bind(score.player_index as i32)
            .bind(score.score_this_round as i32)
            .bind(score.total_score_after as i32)
            .bind(score.hand_points as i32)
            .bind(if score.is_zapzap_caller { 1 } else { 0 })
            .bind(if score.zapzap_success { 1 } else { 0 })
            .bind(if score.was_counteracted { 1 } else { 0 })
            .bind(&hand_cards_json)
            .bind(if score.is_lowest_hand { 1 } else { 0 })
            .bind(if score.is_eliminated { 1 } else { 0 })
            .bind(now)
            .execute(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;
        }

        Ok(())
    }

    async fn get_elimination_order(
        &self,
        party_id: &str,
    ) -> Result<Vec<(String, Option<u32>)>, RepositoryError> {
        let mut conn = self.pool.acquire().await.map_err(db_err)?;
        elimination_order(&mut conn, party_id).await
    }

    async fn save_game_results(
        &self,
        party_id: &str,
        winner_user_id: &str,
        winner_score: u16,
        total_rounds: u32,
        was_golden_score: bool,
        player_results: Vec<PlayerGameResult>,
    ) -> Result<(), RepositoryError> {
        let mut conn = self.pool.acquire().await.map_err(db_err)?;
        write_game_results(
            &mut conn,
            party_id,
            winner_user_id,
            winner_score,
            total_rounds,
            was_golden_score,
            player_results,
        )
        .await
    }
}

fn db_err(e: sqlx::Error) -> RepositoryError {
    RepositoryError::Database(e.to_string())
}

/// Write a game state read at `expected_version`, as the next version, the deadline of the
/// turn under way stamped at `now_ms`: the compare-and-swap of every move
/// (`update_game_state`, `update_game_state_for_player`) and of an ejection
/// (`replace_player`). With `seat_holder` `(seat, user)`, only while that user still holds
/// that seat (a player's move). One statement, so SQLite checks the version and the seat
/// and writes atomically; `Conflict`, with nothing written, when the version moved on, the
/// state is gone or the seat changed hands.
async fn write_game_state_if_unchanged(
    conn: &mut SqliteConnection,
    party_id: &str,
    state: &GameState,
    expected_version: i64,
    now_ms: u64,
    seat_holder: Option<(u8, &str)>,
) -> Result<(), RepositoryError> {
    let mut state = state.clone();
    state.stamp_turn_deadline(now_ms);
    let written = sqlx::query(
        "UPDATE game_state SET state_json = ?1, updated_at = ?2, version = version + 1 \
         WHERE party_id = ?3 AND version = ?4 AND (?5 IS NULL OR EXISTS ( \
             SELECT 1 FROM party_players \
             WHERE party_id = ?3 AND player_index = ?5 AND user_id = ?6))",
    )
    .bind(state.to_json())
    .bind(chrono::Utc::now().timestamp())
    .bind(party_id)
    .bind(expected_version)
    .bind(seat_holder.map(|(seat, _)| i32::from(seat)))
    .bind(seat_holder.map(|(_, user)| user))
    .execute(&mut *conn)
    .await
    .map_err(db_err)?;

    if written.rows_affected() == 0 {
        return Err(RepositoryError::Conflict(match seat_holder {
            Some((seat, user)) => format!(
                "game state of party {party_id} changed since version {expected_version}, \
                 or seat {seat} is no longer {user}'s"
            ),
            None => {
                format!("game state of party {party_id} changed since version {expected_version}")
            }
        }));
    }
    Ok(())
}

/// Each player of the party with the first round they were eliminated in, by seat: the
/// `MIN(round_number)` of their `round_scores` rows marked `is_eliminated`, `None` if none.
/// On a connection, so that a transaction can read it (`delete_account`).
pub(crate) async fn elimination_order(
    conn: &mut SqliteConnection,
    party_id: &str,
) -> Result<Vec<(String, Option<u32>)>, RepositoryError> {
    let rows = sqlx::query_as::<_, (String, Option<i32>)>(
        r#"
        SELECT
            pp.user_id,
            (SELECT MIN(rs.round_number)
             FROM round_scores rs
             WHERE rs.party_id = pp.party_id
             AND rs.user_id = pp.user_id
             AND rs.is_eliminated = 1) as elimination_round
        FROM party_players pp
        WHERE pp.party_id = ?
        ORDER BY pp.player_index ASC
        "#,
    )
    .bind(party_id)
    .fetch_all(&mut *conn)
    .await
    .map_err(db_err)?;

    Ok(rows
        .into_iter()
        .map(|(user_id, round)| (user_id, round.map(|r| r as u32)))
        .collect())
}

/// Write a finished game's results (`game_results`, `player_game_results`), upserted on
/// the party. On a connection, so that a transaction can write them (`delete_account`).
pub(crate) async fn write_game_results(
    conn: &mut SqliteConnection,
    party_id: &str,
    winner_user_id: &str,
    winner_score: u16,
    total_rounds: u32,
    was_golden_score: bool,
    player_results: Vec<PlayerGameResult>,
) -> Result<(), RepositoryError> {
    let now = chrono::Utc::now().timestamp();

    sqlx::query(
        "INSERT INTO game_results (party_id, winner_user_id, winner_final_score, total_rounds, was_golden_score, player_count, finished_at, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(party_id) DO UPDATE SET
            winner_user_id = excluded.winner_user_id,
            winner_final_score = excluded.winner_final_score,
            total_rounds = excluded.total_rounds,
            was_golden_score = excluded.was_golden_score,
            finished_at = excluded.finished_at",
    )
    .bind(party_id)
    .bind(winner_user_id)
    .bind(winner_score as i32)
    .bind(total_rounds as i32)
    .bind(if was_golden_score { 1 } else { 0 })
    .bind(player_results.len() as i32)
    .bind(now)
    .bind(now)
    .execute(&mut *conn)
    .await
    .map_err(db_err)?;

    for result in player_results {
        sqlx::query(
            "INSERT INTO player_game_results (party_id, user_id, final_score, finish_position, rounds_played, is_winner, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(party_id, user_id) DO UPDATE SET
                final_score = excluded.final_score,
                finish_position = excluded.finish_position,
                rounds_played = excluded.rounds_played,
                is_winner = excluded.is_winner",
        )
        .bind(party_id)
        .bind(&result.user_id)
        .bind(result.final_score as i32)
        .bind(result.finish_position as i32)
        .bind(result.rounds_played as i32)
        .bind(if result.is_winner { 1 } else { 0 })
        .bind(now)
        .execute(&mut *conn)
        .await
        .map_err(db_err)?;
    }

    Ok(())
}
