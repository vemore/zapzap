//! A player changes their username, under sign-up's rules (`validate_username`). The name
//! lives only in `users`: games, history and statistics join on the user id, so past games
//! show the new name. The JWT carries the name, so the answer is a new token.

use std::sync::Arc;

use super::register_user::validate_username;
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

    /// Renames `user_id` to `username`; its own current name is accepted and changes nothing
    pub async fn execute(
        &self,
        user_id: &str,
        username: &str,
    ) -> Result<RenameUserOutput, RenameError> {
        validate_username(username).map_err(RenameError::Validation)?;
        let mut user = self
            .user_repo
            .find_by_id(user_id)
            .await?
            .ok_or(RenameError::NotFound)?;

        if user.username != username {
            if self.user_repo.exists_by_username(username).await? {
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
            .sign(&user.id, &user.username, user.is_admin)
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
        let err = use_case.execute("u1", "bob").await.err().unwrap();
        assert!(matches!(err, RenameError::UsernameExists), "{err}");
        assert_eq!(
            repo.find_by_id("u1").await.unwrap().unwrap().username,
            "alice"
        );
    }
}
