use async_trait::async_trait;
use sqlx::SqlitePool;

use crate::domain::entities::{BotDifficulty, User, UserType, DELETED_USER_ID_PREFIX};
use crate::domain::repositories::{AccountDeletion, RepositoryError, UserRepository};

/// The columns that name a user in a game, each handed to the anonymous user when an
/// account is deleted (`delete_account`)
const USER_REFERENCES: [(&str, &str); 6] = [
    ("parties", "owner_id"),
    ("party_players", "user_id"),
    ("round_scores", "user_id"),
    ("game_results", "winner_user_id"),
    ("player_game_results", "user_id"),
    ("game_actions", "user_id"),
];

fn db_err(e: sqlx::Error) -> RepositoryError {
    RepositoryError::Database(e.to_string())
}

/// SQLite implementation of UserRepository
pub struct SqliteUserRepository {
    pool: SqlitePool,
}

impl SqliteUserRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    fn row_to_user(row: &sqlx::sqlite::SqliteRow) -> User {
        use sqlx::Row;

        let user_type_str: String = row.get("user_type");
        let bot_difficulty_str: Option<String> = row.get("bot_difficulty");

        User {
            id: row.get("id"),
            username: row.get("username"),
            password_hash: row.get("password_hash"),
            user_type: UserType::from_str(&user_type_str).unwrap_or(UserType::Human),
            bot_difficulty: bot_difficulty_str
                .as_deref()
                .and_then(BotDifficulty::from_str),
            is_admin: row.get::<i32, _>("is_admin") != 0,
            google_id: row.get("google_id"),
            email: row.get("email"),
            last_login_at: row.get("last_login_at"),
            total_play_time_seconds: row.get::<i64, _>("total_play_time_seconds"),
            created_at: row.get("created_at"),
            updated_at: row.get("updated_at"),
        }
    }
}

#[async_trait]
impl UserRepository for SqliteUserRepository {
    async fn find_by_id(&self, id: &str) -> Result<Option<User>, RepositoryError> {
        let row = sqlx::query("SELECT * FROM users WHERE id = ?")
            .bind(id)
            .fetch_optional(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(row.as_ref().map(Self::row_to_user))
    }

    async fn find_by_ids(&self, ids: &[String]) -> Result<Vec<User>, RepositoryError> {
        if ids.is_empty() {
            return Ok(Vec::new());
        }

        // Build placeholders for IN clause
        let placeholders: Vec<&str> = ids.iter().map(|_| "?").collect();
        let query = format!(
            "SELECT * FROM users WHERE id IN ({})",
            placeholders.join(", ")
        );

        let mut query_builder = sqlx::query(&query);
        for id in ids {
            query_builder = query_builder.bind(id);
        }

        let rows = query_builder
            .fetch_all(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(rows.iter().map(Self::row_to_user).collect())
    }

    async fn find_by_username(&self, username: &str) -> Result<Option<User>, RepositoryError> {
        let row = sqlx::query("SELECT * FROM users WHERE username = ?")
            .bind(username)
            .fetch_optional(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(row.as_ref().map(Self::row_to_user))
    }

    async fn find_by_google_id(&self, google_id: &str) -> Result<Option<User>, RepositoryError> {
        let row = sqlx::query("SELECT * FROM users WHERE google_id = ?")
            .bind(google_id)
            .fetch_optional(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(row.as_ref().map(Self::row_to_user))
    }

    async fn exists_by_username(&self, username: &str) -> Result<bool, RepositoryError> {
        let count: i32 = sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE username = ?")
            .bind(username)
            .fetch_one(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(count > 0)
    }

    async fn find_all_bots(
        &self,
        difficulty: Option<BotDifficulty>,
    ) -> Result<Vec<User>, RepositoryError> {
        let rows = match difficulty {
            Some(diff) => {
                sqlx::query("SELECT * FROM users WHERE user_type = 'bot' AND bot_difficulty = ?")
                    .bind(diff.as_str())
                    .fetch_all(&self.pool)
                    .await
            }
            None => {
                sqlx::query("SELECT * FROM users WHERE user_type = 'bot'")
                    .fetch_all(&self.pool)
                    .await
            }
        }
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(rows.iter().map(Self::row_to_user).collect())
    }

    async fn save(&self, user: &User) -> Result<(), RepositoryError> {
        let now = chrono::Utc::now().timestamp();

        sqlx::query(
            r#"
            INSERT INTO users (id, username, password_hash, user_type, bot_difficulty, is_admin, google_id, email, last_login_at, total_play_time_seconds, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                username = excluded.username,
                password_hash = excluded.password_hash,
                user_type = excluded.user_type,
                bot_difficulty = excluded.bot_difficulty,
                is_admin = excluded.is_admin,
                google_id = excluded.google_id,
                email = excluded.email,
                last_login_at = excluded.last_login_at,
                total_play_time_seconds = excluded.total_play_time_seconds,
                updated_at = ?
            "#,
        )
        .bind(&user.id)
        .bind(&user.username)
        .bind(&user.password_hash)
        .bind(user.user_type.as_str())
        .bind(user.bot_difficulty.map(|d| d.as_str()))
        .bind(user.is_admin as i32)
        .bind(&user.google_id)
        .bind(&user.email)
        .bind(user.last_login_at)
        .bind(user.total_play_time_seconds)
        .bind(user.created_at)
        .bind(user.updated_at)
        .bind(now)
        .execute(&self.pool)
        .await
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(())
    }

    async fn delete(&self, id: &str) -> Result<bool, RepositoryError> {
        let result = sqlx::query("DELETE FROM users WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(result.rows_affected() > 0)
    }

    async fn delete_account(&self, id: &str) -> Result<AccountDeletion, RepositoryError> {
        // One transaction: the checks and the writes see the same database, and a write
        // that lost a race with another one fails instead of leaving a half-done deletion.
        // IMMEDIATE takes the write lock up front: a deferred transaction that reads first
        // and upgrades later fails at once with "database is locked" when a game or bot
        // write holds the lock, where BEGIN IMMEDIATE waits out the busy timeout
        let mut tx = self
            .pool
            .begin_with("BEGIN IMMEDIATE")
            .await
            .map_err(db_err)?;

        let is_admin: Option<i64> = sqlx::query_scalar("SELECT is_admin FROM users WHERE id = ?")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(db_err)?;
        let Some(is_admin) = is_admin else {
            return Ok(AccountDeletion::NotFound);
        };
        if is_admin != 0 {
            let admins: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE is_admin = 1")
                .fetch_one(&mut *tx)
                .await
                .map_err(db_err)?;
            if admins <= 1 {
                return Ok(AccountDeletion::LastAdmin);
            }
        }

        // The foreign keys cascade: deleting the user outright would take their seat out
        // of a game in progress, and every party they own with it
        let active: Option<i64> = sqlx::query_scalar(
            "SELECT 1 FROM parties p WHERE p.status IN ('waiting', 'playing') \
             AND (p.owner_id = ? OR EXISTS (SELECT 1 FROM party_players pp \
                  WHERE pp.party_id = p.id AND pp.user_id = ?)) LIMIT 1",
        )
        .bind(id)
        .bind(id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(db_err)?;
        if active.is_some() {
            return Ok(AccountDeletion::ActiveParty);
        }

        let mut referenced = false;
        for (table, column) in USER_REFERENCES {
            let found: Option<i64> =
                sqlx::query_scalar(&format!("SELECT 1 FROM {table} WHERE {column} = ? LIMIT 1"))
                    .bind(id)
                    .fetch_optional(&mut *tx)
                    .await
                    .map_err(db_err)?;
            if found.is_some() {
                referenced = true;
                break;
            }
        }

        let anonymised_as = if referenced {
            // A new anonymous user per deleted account: the UNIQUE(party_id, user_id)
            // indexes refuse two players of one game under a single id
            let anon_id = format!("{DELETED_USER_ID_PREFIX}{}", uuid::Uuid::new_v4());
            let now = chrono::Utc::now().timestamp();
            sqlx::query(
                "INSERT INTO users (id, username, password_hash, user_type, is_admin, created_at, updated_at) \
                 VALUES (?, ?, NULL, 'human', 0, ?, ?)",
            )
            .bind(&anon_id)
            .bind(&anon_id)
            .bind(now)
            .bind(now)
            .execute(&mut *tx)
            .await
            .map_err(db_err)?;
            for (table, column) in USER_REFERENCES {
                sqlx::query(&format!(
                    "UPDATE {table} SET {column} = ? WHERE {column} = ?"
                ))
                .bind(&anon_id)
                .bind(id)
                .execute(&mut *tx)
                .await
                .map_err(db_err)?;
            }
            Some(anon_id)
        } else {
            None
        };

        sqlx::query("DELETE FROM users WHERE id = ?")
            .bind(id)
            .execute(&mut *tx)
            .await
            .map_err(db_err)?;
        tx.commit().await.map_err(db_err)?;
        Ok(AccountDeletion::Deleted { anonymised_as })
    }

    async fn is_in_active_party(&self, id: &str) -> Result<bool, RepositoryError> {
        let row = sqlx::query(
            "SELECT 1 FROM party_players pp JOIN parties p ON p.id = pp.party_id \
             WHERE pp.user_id = ? AND p.status IN ('waiting', 'playing') LIMIT 1",
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(row.is_some())
    }

    async fn update_last_login(&self, id: &str) -> Result<(), RepositoryError> {
        let now = chrono::Utc::now().timestamp();

        sqlx::query("UPDATE users SET last_login_at = ?, updated_at = ? WHERE id = ?")
            .bind(now)
            .bind(now)
            .bind(id)
            .execute(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(())
    }

    async fn find_all_humans(&self, limit: u32, offset: u32) -> Result<Vec<User>, RepositoryError> {
        let rows = sqlx::query(
            "SELECT * FROM users WHERE user_type = 'human' AND id NOT LIKE 'deleted-%' ORDER BY created_at DESC LIMIT ? OFFSET ?",
        )
        .bind(limit as i32)
        .bind(offset as i32)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(rows.iter().map(Self::row_to_user).collect())
    }

    async fn set_admin(&self, id: &str, is_admin: bool) -> Result<(), RepositoryError> {
        let now = chrono::Utc::now().timestamp();

        sqlx::query("UPDATE users SET is_admin = ?, updated_at = ? WHERE id = ?")
            .bind(is_admin as i32)
            .bind(now)
            .bind(id)
            .execute(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(())
    }
}
