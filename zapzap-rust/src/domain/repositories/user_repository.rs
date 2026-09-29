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
    /// The row changed since it was read: a compare-and-swap write lost a race, and
    /// wrote nothing (`PartyRepository::update_game_state`)
    #[error("Conflict: {0}")]
    Conflict(String),
}

impl RepositoryError {
    /// Another write came in between the read and this write, which wrote nothing
    pub fn is_conflict(&self) -> bool {
        matches!(self, RepositoryError::Conflict(_))
    }

    /// The row to write is gone (a game state whose party was deleted)
    pub fn is_not_found(&self) -> bool {
        matches!(self, RepositoryError::NotFound(_))
    }

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
    /// `forfeits` are the seats the user held in games in progress, given up
    Deleted {
        anonymised_as: Option<String>,
        forfeits: Vec<SeatForfeit>,
    },
    NotFound,
    /// Seated in, or owner of, a waiting party: nothing was changed (they can leave it)
    ActiveParty,
    /// The only admin: nothing was changed
    LastAdmin,
}

/// A seat in a game in progress that an account deletion gave up: the seat is
/// eliminated (`forfeit_seat`), under the anonymous user from then on
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SeatForfeit {
    pub party_id: String,
    pub player_index: u8,
    pub outcome: ForfeitOutcome,
}

/// What became of the game a seat was forfeited in
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ForfeitOutcome {
    /// The other seats play on
    Continues,
    /// Fewer than two seats were left in the game: it is over, won by that seat
    Finished {
        winner_user_id: String,
        winner_index: u8,
    },
    /// No other human sat at the table: the party was deleted, as when the last human
    /// leaves a waiting party; `name` and `visibility` are the ones it had
    Deleted { name: String, visibility: String },
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

    /// Check if username exists, whatever the case (`LOWER(username) = LOWER(?)`)
    async fn exists_by_username_ci(&self, username: &str) -> Result<bool, RepositoryError>;

    /// Find all bots, optionally filtered by difficulty
    async fn find_all_bots(
        &self,
        difficulty: Option<BotDifficulty>,
    ) -> Result<Vec<User>, RepositoryError>;

    /// Save user (create or update)
    async fn save(&self, user: &User) -> Result<(), RepositoryError>;

    /// Delete user; `false` when no row was deleted
    async fn delete(&self, id: &str) -> Result<bool, RepositoryError>;

    /// Delete an account, in one transaction: its seats in games in progress are
    /// forfeited (`SeatForfeit`), its games are handed to a new anonymous user
    /// (`DELETED_USER_ID_PREFIX`), so they stay in the other players' history, then the
    /// user row goes (and with it the Google id and email)
    async fn delete_account(&self, id: &str) -> Result<AccountDeletion, RepositoryError>;

    /// Whether the user holds a seat in a waiting or playing party
    async fn is_in_active_party(&self, id: &str) -> Result<bool, RepositoryError>;

    /// Update last login timestamp
    async fn update_last_login(&self, id: &str) -> Result<(), RepositoryError>;

    /// Find all human users with pagination
    async fn find_all_humans(&self, limit: u32, offset: u32) -> Result<Vec<User>, RepositoryError>;

    /// Set user admin status
    async fn set_admin(&self, id: &str, is_admin: bool) -> Result<(), RepositoryError>;

    /// Rename a user, that column only. A name another user holds fails on the UNIQUE
    /// constraint (`RepositoryError::is_unique_violation`); `false` when no row matched
    async fn update_username(&self, id: &str, username: &str) -> Result<bool, RepositoryError>;

    /// Replace a user's password hash, that column only; `false` when no row matched
    async fn update_password_hash(
        &self,
        id: &str,
        password_hash: &str,
    ) -> Result<bool, RepositoryError>;
}
