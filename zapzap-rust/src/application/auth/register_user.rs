use std::sync::Arc;

use uuid::Uuid;

use crate::domain::entities::User;
use crate::domain::repositories::UserRepository;
use crate::infrastructure::auth::{JwtService, PasswordService};

/// Register user input
pub struct RegisterUserInput {
    pub username: String,
    pub password: String,
}

/// Register user output
pub struct RegisterUserOutput {
    pub user: User,
    pub token: String,
}

/// Register user use case
pub struct RegisterUser {
    user_repo: Arc<dyn UserRepository>,
    jwt_service: Arc<JwtService>,
}

impl RegisterUser {
    pub fn new(user_repo: Arc<dyn UserRepository>, jwt_service: Arc<JwtService>) -> Self {
        Self {
            user_repo,
            jwt_service,
        }
    }

    pub async fn execute(&self, input: RegisterUserInput) -> Result<RegisterUserOutput, RegisterError> {
        // Validate input
        if input.username.trim().is_empty() {
            return Err(RegisterError::Validation("Username is required".into()));
        }
        if input.username.len() < 3 {
            return Err(RegisterError::Validation("Username must be at least 3 characters".into()));
        }
        if input.password.len() < 4 {
            return Err(RegisterError::Validation("Password must be at least 4 characters".into()));
        }

        // Check if username exists
        if self.user_repo.exists_by_username(&input.username).await? {
            return Err(RegisterError::UsernameExists);
        }

        // Hash password
        let password_hash = PasswordService::hash(&input.password)
            .map_err(|e| RegisterError::Internal(e.to_string()))?;

        // Create user
        let user_id = Uuid::new_v4().to_string();
        let user = User::new_human(user_id, input.username.clone(), password_hash);

        // Save user
        self.user_repo.save(&user).await?;

        // Generate token
        let token = self
            .jwt_service
            .sign(&user.id, &user.username, user.is_admin)
            .map_err(|e| RegisterError::Internal(e.to_string()))?;

        Ok(RegisterUserOutput { user, token })
    }
}

/// Register error types
#[derive(Debug, thiserror::Error)]
pub enum RegisterError {
    #[error("Validation error: {0}")]
    Validation(String),
    #[error("Username already exists")]
    UsernameExists,
    #[error("Internal error: {0}")]
    Internal(String),
    #[error("Repository error: {0}")]
    Repository(#[from] crate::domain::repositories::RepositoryError),
}
