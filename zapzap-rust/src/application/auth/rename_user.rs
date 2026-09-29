//! A player changes their username, under sign-up's rules (`validate_username`). The name
//! lives only in `users`: games, history and statistics join on the user id, so past games
//! show the new name. The JWT carries the name, so the answer is a new token.

use std::sync::Arc;

use super::register_user::{is_reserved_username, validate_username};
use crate::domain::entities::User;
use crate::domain::repositories::UserRepository;
use crate::infrastructure::auth::JwtService;

/// The renamed user and a token carrying the new name
pub struct RenameUserOutput {
    pub user: User,
    pub token: String,
}

/// Rename own account use case
pub struct RenameUser {
    user_repo: Arc<dyn UserRepository>,
    jwt_service: Arc<JwtService>,
}

impl RenameUser {
    pub fn new(user_repo: Arc<dyn UserRepository>, jwt_service: Arc<JwtService>) -> Self {
        Self {
            user_repo,
            jwt_service,
        }
    }

    /// Renames `user_id` to `username`; its own current name is accepted and changes nothing.
    /// The new token expires at `exp` (Unix seconds), the one of the token it replaces: a
    /// rename never extends a session.
    pub async fn execute(
        &self,
        user_id: &str,
        username: &str,
        exp: usize,
    ) -> Result<RenameUserOutput, RenameError> {
        validate_username(username).map_err(RenameError::Validation)?;
        let username = username.trim();
        let mut user = self
            .user_repo
            .find_by_id(user_id)
            .await?
            .ok_or(RenameError::NotFound)?;

        // A reserved name is refused unless it is this account's own, whatever its case (the
        // default admin keeps "admin")
        if is_reserved_username(username)
            && username.trim().to_lowercase() != user.username.trim().to_lowercase()
        {
            return Err(RenameError::Reserved);
        }

        if user.username != username {
            // Unique whatever the case, unless the only match is this account's own name
            // (bob -> Bob); older case-duplicates stay, they are not checked again
            let own_case_change = user.username.to_lowercase() == username.to_lowercase();
            if !own_case_change && self.user_repo.exists_by_username_ci(username).await? {
                return Err(RenameError::UsernameExists);
            }
            // A name taken between the check and the write fails on the UNIQUE constraint
            match self.user_repo.update_username(user_id, username).await {
                Ok(true) => {}
                Ok(false) => return Err(RenameError::NotFound),
                Err(e) if e.is_unique_violation() => return Err(RenameError::UsernameExists),
                Err(e) => return Err(e.into()),
            }
            tracing::info!(
                "User {} renamed: {} -> {}",
                user.id,
                user.username,
                username
            );
            user.username = username.to_string();
        }

        let token = self
            .jwt_service
            .sign_until(&user.id, &user.username, user.is_admin, exp)
            .map_err(|e| RenameError::Internal(e.to_string()))?;
        Ok(RenameUserOutput { user, token })
    }
}

/// Rename error types
#[derive(Debug, thiserror::Error)]
pub enum RenameError {
    #[error("{0}")]
    Validation(String),
    #[error("Username already exists")]
    UsernameExists,
    #[error("Username is reserved")]
    Reserved,
    #[error("User not found")]
    NotFound,
    #[error("Internal error: {0}")]
    Internal(String),
    #[error("Repository error: {0}")]
    Repository(#[from] crate::domain::repositories::RepositoryError),
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::infrastructure::database::repositories::racing_user_repo::RacingUserRepo;
    use std::sync::atomic::Ordering;

    #[tokio::test]
    async fn a_name_taken_after_the_check_is_refused_by_the_database() {
        let repo = Arc::new(RacingUserRepo::new().await);
        for (id, name) in [("u1", "alice"), ("u2", "bob")] {
            repo.save(&User::new_human(id.into(), name.into(), "hash".into()))
                .await
                .unwrap();
        }
        let use_case = RenameUser::new(repo.clone(), Arc::new(JwtService::new("secret".into())));

        // The lookup misses "bob", as if he had signed up just after it
        repo.stale_username_checks.store(1, Ordering::SeqCst);
        let err = use_case.execute("u1", "bob", 0).await.err().unwrap();
        assert!(matches!(err, RenameError::UsernameExists), "{err}");
        assert_eq!(
            repo.find_by_id("u1").await.unwrap().unwrap().username,
            "alice"
        );
    }
}
