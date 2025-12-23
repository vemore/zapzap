use async_trait::async_trait;
use sqlx::SqlitePool;

use crate::domain::entities::{BotDifficulty, User, UserType};
use crate::domain::repositories::{RepositoryError, UserRepository};

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
        let count: i32 =
            sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE username = ?")
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

    async fn delete(&self, id: &str) -> Result<(), RepositoryError> {
        sqlx::query("DELETE FROM users WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await
            .map_err(|e| RepositoryError::Database(e.to_string()))?;

        Ok(())
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

    async fn find_all_humans(
        &self,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<User>, RepositoryError> {
        let rows = sqlx::query(
            "SELECT * FROM users WHERE user_type = 'human' ORDER BY created_at DESC LIMIT ? OFFSET ?",
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
