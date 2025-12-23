use async_trait::async_trait;

use crate::domain::entities::{BotDifficulty, User};

/// Error type for repository operations
#[derive(Debug, thiserror::Error)]
pub enum RepositoryError {
    #[error("Not found: {0}")]
    NotFound(String),
    #[error("Already exists: {0}")]
    AlreadyExists(String),
    #[error("Database error: {0}")]
    Database(String),
}

/// User repository trait
#[async_trait]
pub trait UserRepository: Send + Sync {
    /// Find user by ID
    async fn find_by_id(&self, id: &str) -> Result<Option<User>, RepositoryError>;

    /// Find multiple users by IDs (batch query - avoids N+1)
    async fn find_by_ids(&self, ids: &[String]) -> Result<Vec<User>, RepositoryError>;

    /// Find user by username
    async fn find_by_username(&self, username: &str) -> Result<Option<User>, RepositoryError>;

    /// Find user by Google ID
    async fn find_by_google_id(&self, google_id: &str) -> Result<Option<User>, RepositoryError>;

    /// Check if username exists
    async fn exists_by_username(&self, username: &str) -> Result<bool, RepositoryError>;

    /// Find all bots, optionally filtered by difficulty
    async fn find_all_bots(
        &self,
        difficulty: Option<BotDifficulty>,
    ) -> Result<Vec<User>, RepositoryError>;

    /// Save user (create or update)
    async fn save(&self, user: &User) -> Result<(), RepositoryError>;

    /// Delete user
    async fn delete(&self, id: &str) -> Result<(), RepositoryError>;

    /// Update last login timestamp
    async fn update_last_login(&self, id: &str) -> Result<(), RepositoryError>;

    /// Find all human users with pagination
    async fn find_all_humans(
        &self,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<User>, RepositoryError>;

    /// Set user admin status
    async fn set_admin(&self, id: &str, is_admin: bool) -> Result<(), RepositoryError>;
}
