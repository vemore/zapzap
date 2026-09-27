//! Resetting a user's password: `zapzap-backend reset-password <username>` (`main.rs`), the
//! new password read from stdin so it never appears in argv or a shell history / process
//! list, and hashed through [`PasswordService::hash`] as registration hashes.
//!
//! Replaces the only reset tool the Node backend had, `scripts/reset-password.js`, which
//! hard-coded a single username/password pair and was removed with it.

use sqlx::SqlitePool;

use crate::domain::repositories::UserRepository;
use crate::infrastructure::auth::PasswordService;
use crate::infrastructure::database::repositories::SqliteUserRepository;

/// What [`reset_password`] did.
#[derive(Debug, PartialEq, Eq)]
pub enum ResetOutcome {
    /// The user's stored hash was replaced.
    Reset,
    /// No such username: the database was not touched.
    NotFound,
}

/// Hash `new_password` (bcrypt, [`PasswordService::hash`]) and store it as `username`'s
/// password, replacing whatever hash — or `None`, for a bot — was there. `NotFound` when no
/// user has that username; the database is then a no-op.
pub async fn reset_password(
    db: &SqlitePool,
    username: &str,
    new_password: &str,
) -> anyhow::Result<ResetOutcome> {
    let repo = SqliteUserRepository::new(db.clone());
    let Some(mut user) = repo.find_by_username(username).await? else {
        return Ok(ResetOutcome::NotFound);
    };
    user.password_hash = Some(PasswordService::hash(new_password)?);
    repo.save(&user).await?;
    Ok(ResetOutcome::Reset)
}
