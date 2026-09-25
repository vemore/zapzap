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

impl RepositoryError {
    /// A UNIQUE constraint refused the write (SQLite's message)
    pub fn is_unique_violation(&self) -> bool {
        matches!(self, RepositoryError::Database(m) if m.contains("UNIQUE constraint failed"))
    }

    /// UNIQUE(party_id, player_index) refused the write: another player took the seat
    pub fn is_seat_conflict(&self) -> bool {
        self.is_unique_violation()
            && matches!(self, RepositoryError::Database(m) if m.contains(".player_index"))
    }
}

/// Outcome of `UserRepository::delete_account`
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AccountDeletion {
    /// The user is gone; `anonymised_as` names the anonymous user their finished games
    /// now belong to, `None` when they had played none
    Deleted {
        anonymised_as: Option<String>,
    },
    NotFound,
    /// Seated in, or owner of, a waiting or playing party: nothing was changed
    ActiveParty,
    /// The only admin: nothing was changed
    LastAdmin,
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

    /// Delete user; `false` when no row was deleted
    async fn delete(&self, id: &str) -> Result<bool, RepositoryError>;

    /// Delete an account, in one transaction: its finished games are handed to a new
    /// anonymous user (`DELETED_USER_ID_PREFIX`), so they stay in the other players'
    /// history, then the user row goes (and with it the Google id and email)
    async fn delete_account(&self, id: &str) -> Result<AccountDeletion, RepositoryError>;

    /// Whether the user holds a seat in a waiting or playing party
    async fn is_in_active_party(&self, id: &str) -> Result<bool, RepositoryError>;

    /// Update last login timestamp
    async fn update_last_login(&self, id: &str) -> Result<(), RepositoryError>;

    /// Find all human users with pagination
    async fn find_all_humans(&self, limit: u32, offset: u32) -> Result<Vec<User>, RepositoryError>;

    /// Set user admin status
    async fn set_admin(&self, id: &str, is_admin: bool) -> Result<(), RepositoryError>;
}
