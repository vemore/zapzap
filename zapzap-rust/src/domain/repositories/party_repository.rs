use async_trait::async_trait;

use crate::domain::entities::{Party, PartyPlayer, PartyStatus, Round, User};
use crate::domain::repositories::RepositoryError;
use crate::domain::services::GameResults;
use crate::domain::value_objects::GameState;

/// Party with player count (optimized for listing)
#[derive(Debug, Clone)]
pub struct PartyWithPlayerCount {
    pub party: Party,
    pub player_count: usize,
    pub player_user_ids: Vec<String>,
}

/// Party repository trait
#[async_trait]
pub trait PartyRepository: Send + Sync {
    // ========== Party operations ==========

    /// Find party by ID
    async fn find_by_id(&self, id: &str) -> Result<Option<Party>, RepositoryError>;

    /// Find party by invite code
    async fn find_by_invite_code(&self, code: &str) -> Result<Option<Party>, RepositoryError>;

    /// Find public parties with pagination
    async fn find_public_parties(
        &self,
        status: Option<PartyStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Party>, RepositoryError>;

    /// Find public parties with player counts (optimized - single query)
    async fn find_public_parties_with_counts(
        &self,
        status: Option<PartyStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<PartyWithPlayerCount>, RepositoryError>;

    /// Find parties by owner
    async fn find_by_owner(
        &self,
        owner_id: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Party>, RepositoryError>;

    /// Find all parties (admin)
    async fn find_all_parties(
        &self,
        status: Option<PartyStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Party>, RepositoryError>;

    /// Save party (create or update)
    async fn save(&self, party: &Party) -> Result<(), RepositoryError>;

    /// Delete party
    async fn delete(&self, id: &str) -> Result<(), RepositoryError>;

    /// Update party status
    async fn update_status(&self, id: &str, status: PartyStatus) -> Result<(), RepositoryError>;

    // ========== Party player operations ==========

    /// Get party players
    async fn get_party_players(&self, party_id: &str) -> Result<Vec<PartyPlayer>, RepositoryError>;

    /// Add player to party; `AlreadyExists` when the user already has a seat in it
    async fn add_party_player(
        &self,
        party_id: &str,
        user_id: &str,
        player_index: u8,
    ) -> Result<(), RepositoryError>;

    /// Move a player to another (free) seat
    async fn set_player_index(
        &self,
        party_id: &str,
        user_id: &str,
        player_index: u8,
    ) -> Result<(), RepositoryError>;

    /// Remove player from party
    async fn remove_party_player(
        &self,
        party_id: &str,
        user_id: &str,
    ) -> Result<(), RepositoryError>;

    /// Check if user is in party
    async fn is_player_in_party(
        &self,
        party_id: &str,
        user_id: &str,
    ) -> Result<bool, RepositoryError>;

    /// Get player index in party
    async fn get_player_index(
        &self,
        party_id: &str,
        user_id: &str,
    ) -> Result<Option<u8>, RepositoryError>;

    /// The seats of the party's human players, in seat order
    async fn human_seats(&self, party_id: &str) -> Result<Vec<u8>, RepositoryError>;

    /// Give a late human's seat to a bot (GAME_RULES.md "Turn Time Limit"), in one
    /// transaction: the game state read at `expected_version` is written as the next
    /// version by the compare-and-swap of `update_game_state`; the seat changes hands; the
    /// party's ownership passes on when the human owned it; and the human's result, a
    /// loss ranked after every seat by `rank_ejected`, is written (the players ejected
    /// before move down one). `Conflict`, with nothing written, when
    /// another write of the game state (a move) came in since the read, or the seat is no
    /// longer the human's.
    async fn replace_player(
        &self,
        replacement: &SeatReplacement<'_>,
    ) -> Result<(), RepositoryError>;

    // ========== Round operations ==========

    /// Get round by ID
    async fn get_round_by_id(&self, id: &str) -> Result<Option<Round>, RepositoryError>;

    /// Save round (create or update)
    async fn save_round(&self, round: &Round) -> Result<(), RepositoryError>;

    /// Get current round for party
    async fn get_current_round(&self, party_id: &str) -> Result<Option<Round>, RepositoryError>;

    // ========== Game state operations ==========

    /// Get game state for party, to read it
    async fn get_game_state(&self, party_id: &str) -> Result<Option<GameState>, RepositoryError> {
        Ok(self
            .get_versioned_game_state(party_id)
            .await?
            .map(|read| read.state))
    }

    /// Get game state for party with its version, to change it through
    /// `update_game_state`
    async fn get_versioned_game_state(
        &self,
        party_id: &str,
    ) -> Result<Option<VersionedGameState>, RepositoryError>;

    /// Write a game state whatever is stored (a game's first state), as a new version.
    /// A move goes through `update_game_state`.
    async fn save_game_state(
        &self,
        party_id: &str,
        state: &GameState,
    ) -> Result<(), RepositoryError>;

    /// Write a game state read at `expected_version` (compare-and-swap), as the next
    /// version, and nothing else: a write of the state alone (a bot's turn handed on, a
    /// deadline extended). `RepositoryError::Conflict`, with nothing written, when another
    /// write (a move, a bot move, a forfeit, an ejection, an admin stop) came in since the
    /// read, or the party is no longer playing; `NotFound` when the state is gone (the
    /// party deleted).
    ///
    /// Every game-state write stamps the turn's deadline (`GameState::stamp_turn_deadline`)
    /// with the repository's clock, so every turn that begins gets its deadline as it is
    /// stored.
    async fn update_game_state(
        &self,
        party_id: &str,
        state: &GameState,
        expected_version: i64,
    ) -> Result<(), RepositoryError>;

    /// Write what a game use case changed, all of it or nothing, in one transaction that
    /// begins with the compare-and-swap of `update_game_state` (same `Conflict` and
    /// `NotFound`): the game state, the round rows (`RoundWrite`), and at the game's end
    /// the party finished and the game's results, built from the seats, the recorded
    /// eliminations and the players the turn timer ejected as the transaction reads them
    /// (`build_game_results`). Party fields are written one by one, never the whole row,
    /// so no write of the party read before the state is undone. Returns those results
    /// when `write.winner` ended the game.
    async fn write_game(
        &self,
        write: &GameWrite<'_>,
    ) -> Result<Option<GameResults>, RepositoryError>;

    /// The playing parties whose seat on turn went past its turn deadline at `now` (Unix
    /// milliseconds)
    async fn parties_past_turn_deadline(&self, now: u64) -> Result<Vec<String>, RepositoryError>;

    // ========== Game action logging ==========

    /// Save game action
    async fn save_game_action(&self, action: &GameAction) -> Result<(), RepositoryError>;

    /// Get game actions for round
    async fn get_game_actions(
        &self,
        party_id: &str,
        round_number: u32,
    ) -> Result<Vec<GameAction>, RepositoryError>;
}

/// A game state and the version it was read at: the token `update_game_state` compares,
/// so that a write based on a stale read is refused instead of undoing the one before it
#[derive(Debug, Clone)]
pub struct VersionedGameState {
    pub state: GameState,
    pub version: i64,
}

/// What a game use case writes: `PartyRepository::write_game`
#[derive(Debug, Clone)]
pub struct GameWrite<'a> {
    pub party_id: &'a str,
    /// The game state to write
    pub state: &'a GameState,
    /// The version `state` was read at
    pub expected_version: i64,
    /// A player's move: `(seat, user)`, written only while that user still holds that
    /// seat, checked in the same statement as the version (the turn timer may have given
    /// it to a bot since the move checked it)
    pub seat_holder: Option<(u8, &'a str)>,
    /// What becomes of the round rows
    pub round: RoundWrite<'a>,
    /// The seat that won the game `state` ends: the party is finished and the game's
    /// results written
    pub winner: Option<u8>,
}

/// The round rows a game use case writes: the round a row stands for is the state's
/// `round_number`, whatever `parties.current_round_id` said when the use case read it
#[derive(Debug, Clone)]
pub enum RoundWrite<'a> {
    /// No round row changes
    Unchanged,
    /// The round under way takes the state's turn and action (a move)
    Progress,
    /// The round under way is over: finished, with each seat's score (a ZapZap)
    Finish(&'a [RoundScoreEntry]),
    /// A round begins: its row is inserted and becomes the party's current round
    Start(&'a Round),
}

/// A late human's seat given to a bot: what `PartyRepository::replace_player` writes
#[derive(Debug, Clone)]
pub struct SeatReplacement<'a> {
    pub party_id: &'a str,
    pub player_index: u8,
    /// The human who held the seat
    pub human_id: &'a str,
    /// The bot who takes it, with its hand and score
    pub bot_id: &'a str,
    /// The bot to create first, in the same transaction, when no existing bot was free
    /// (`bot_id` is its id): an ejection that loses its race creates no bot
    pub new_bot: Option<&'a User>,
    /// The party's new owner, when the human owned it
    pub new_owner_id: Option<&'a str>,
    /// The game state to write: the seat no longer timed
    pub state: &'a GameState,
    /// The version `state` was read at
    pub expected_version: i64,
    /// The seats of the game: the human ranks after all of them
    pub seat_count: u8,
}

/// Round score entry for saving
#[derive(Debug, Clone)]
pub struct RoundScoreEntry {
    pub user_id: String,
    pub player_index: u8,
    pub score_this_round: u16,
    pub total_score_after: u16,
    pub hand_points: u16,
    pub is_zapzap_caller: bool,
    pub zapzap_success: bool,
    pub was_counteracted: bool,
    pub hand_cards: Vec<u8>,
    pub is_lowest_hand: bool,
    pub is_eliminated: bool,
}

/// Player game result for saving
#[derive(Debug, Clone)]
pub struct PlayerGameResult {
    pub user_id: String,
    pub final_score: u16,
    pub finish_position: u8,
    pub rounds_played: u32,
    pub is_winner: bool,
}

/// A player the turn timer ejected, as their result was written at the ejection: the score
/// and the round they left with (GAME_RULES.md "Final Ranking" item 5)
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EjectedPlayer {
    pub user_id: String,
    pub final_score: u16,
    pub rounds_played: u32,
}

/// Game action log entry
#[derive(Debug, Clone)]
pub struct GameAction {
    pub party_id: String,
    pub round_number: u32,
    pub turn_number: u32,
    pub player_index: u8,
    pub user_id: String,
    pub is_human: bool,
    pub action_type: String,
    pub action_data: String,
    pub hand_before: String,
    pub hand_value_before: u16,
    pub scores_before: String,
    pub opponent_hand_sizes: String,
    pub deck_size: u32,
    pub last_cards_played: String,
    pub hand_after: String,
    pub hand_value_after: Option<u16>,
    pub created_at: i64,
}
