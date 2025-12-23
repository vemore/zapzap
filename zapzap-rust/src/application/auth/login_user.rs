use std::sync::Arc;

use crate::domain::entities::User;
use crate::domain::repositories::UserRepository;
use crate::infrastructure::auth::{JwtService, PasswordService};

/// Login user input
pub struct LoginUserInput {
    pub username: String,
    pub password: String,
}

/// Login user output
pub struct LoginUserOutput {
    pub user: User,
    pub token: String,
}

/// Login user use case
pub struct LoginUser {
    user_repo: Arc<dyn UserRepository>,
    jwt_service: Arc<JwtService>,
}

impl LoginUser {
    pub fn new(user_repo: Arc<dyn UserRepository>, jwt_service: Arc<JwtService>) -> Self {
        Self {
            user_repo,
            jwt_service,
        }
    }

    pub async fn execute(&self, input: LoginUserInput) -> Result<LoginUserOutput, LoginError> {
        // Validate input
        if input.username.trim().is_empty() {
            return Err(LoginError::Validation("Username is required".into()));
        }
        if input.password.is_empty() {
            return Err(LoginError::Validation("Password is required".into()));
        }

        // Find user
        let user = self
            .user_repo
            .find_by_username(&input.username)
            .await?
            .ok_or(LoginError::InvalidCredentials)?;

        // Check if user is a bot
        if user.is_bot() {
            return Err(LoginError::InvalidCredentials);
        }

        // Verify password
        let password_hash = user
            .password_hash
            .as_ref()
            .ok_or(LoginError::InvalidCredentials)?;

        let valid = PasswordService::verify(&input.password, password_hash)
            .map_err(|e| LoginError::Internal(e.to_string()))?;

        if !valid {
            return Err(LoginError::InvalidCredentials);
        }

        // Update last login
        self.user_repo.update_last_login(&user.id).await?;

        // Check if password needs rehash (bcrypt -> argon2 migration)
        if PasswordService::needs_rehash(password_hash) {
            // Rehash with Argon2
            if let Ok(new_hash) = PasswordService::hash(&input.password) {
                let mut updated_user = user.clone();
                updated_user.password_hash = Some(new_hash);
                let _ = self.user_repo.save(&updated_user).await;
            }
        }

        // Generate token
        let token = self
            .jwt_service
            .sign(&user.id, &user.username, user.is_admin)
            .map_err(|e| LoginError::Internal(e.to_string()))?;

        Ok(LoginUserOutput { user, token })
    }
}

/// Login error types
#[derive(Debug, thiserror::Error)]
pub enum LoginError {
    #[error("Validation error: {0}")]
    Validation(String),
    #[error("Invalid username or password")]
    InvalidCredentials,
    #[error("Internal error: {0}")]
    Internal(String),
    #[error("Repository error: {0}")]
    Repository(#[from] crate::domain::repositories::RepositoryError),
}
