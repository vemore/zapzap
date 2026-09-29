//! A player changes their password, confirmed as a deletion is (`confirm_identity`): by the
//! current password, or for an account created with Google by a fresh Google ID token of
//! that account — which sets its first password. The new one follows sign-up's rules
//! (`validate_password`). Tokens already issued stay valid: the JWT does not carry the
//! password.

use std::sync::Arc;

use super::confirm_identity::{confirm_identity, ConfirmError};
use super::register_user::validate_password;
use crate::domain::repositories::UserRepository;
use crate::infrastructure::auth::PasswordService;
use crate::infrastructure::services::GoogleOAuthService;

/// The new password and what confirms the change
pub struct ChangePasswordInput {
    pub current_password: Option<String>,
    /// A Google ID token, for an account without a password
    pub credential: Option<String>,
    pub new_password: String,
}

/// Change own password use case
pub struct ChangePassword {
    user_repo: Arc<dyn UserRepository>,
    google: Option<Arc<GoogleOAuthService>>,
}

impl ChangePassword {
    /// `google` is `None` when `GOOGLE_OAUTH_CLIENT_ID` is not configured
    pub fn new(
        user_repo: Arc<dyn UserRepository>,
        google: Option<Arc<GoogleOAuthService>>,
    ) -> Self {
        Self { user_repo, google }
    }

    /// Replaces the password of `user_id`
    pub async fn execute(
        &self,
        user_id: &str,
        input: ChangePasswordInput,
    ) -> Result<(), ChangePasswordError> {
        validate_password(&input.new_password).map_err(ChangePasswordError::Validation)?;
        let user = self
            .user_repo
            .find_by_id(user_id)
            .await?
            .ok_or(ChangePasswordError::NotFound)?;
        confirm_identity(
            &user,
            input.current_password.as_deref(),
            input.credential.as_deref(),
            self.google.as_deref(),
        )
        .await?;

        let hash = PasswordService::hash(&input.new_password)
            .map_err(|e| ChangePasswordError::Internal(e.to_string()))?;
        if !self.user_repo.update_password_hash(user_id, &hash).await? {
            return Err(ChangePasswordError::NotFound);
        }
        tracing::info!(
            "Password {} for {} ({})",
            if user.password_hash.is_some() {
                "changed"
            } else {
                "set"
            },
            user.username,
            user.id
        );
        Ok(())
    }
}

/// Change password error types
#[derive(Debug, thiserror::Error)]
pub enum ChangePasswordError {
    #[error("{0}")]
    Validation(String),
    #[error("User not found")]
    NotFound,
    #[error(transparent)]
    Confirmation(#[from] ConfirmError),
    #[error("Internal error: {0}")]
    Internal(String),
    #[error("Repository error: {0}")]
    Repository(#[from] crate::domain::repositories::RepositoryError),
}
