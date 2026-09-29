use std::sync::Arc;

use uuid::Uuid;

use crate::domain::entities::{User, DELETED_PLAYER_NAME};
use crate::domain::repositories::UserRepository;
use crate::infrastructure::auth::{JwtService, PasswordService};

/// Names no player may take, whatever their case: the default admin's, whose row the admin
/// screens protect by its name, and the names the clients give a deleted player
/// (`DELETED_PLAYER_NAME`, "Deleted player"), which a live player must not pass for
pub const RESERVED_USERNAMES: &[&str] = &["admin", DELETED_PLAYER_NAME, "Deleted player"];

/// Whether `username` is one of `RESERVED_USERNAMES`, compared trimmed and case-insensitively
pub fn is_reserved_username(username: &str) -> bool {
    let wanted = username.trim().to_lowercase();
    RESERVED_USERNAMES
        .iter()
        .any(|reserved| reserved.to_lowercase() == wanted)
}

/// A username's rules, at sign-up and on a rename (`RenameUser`), those of the Flutter
/// client (`validators.dart`): trimmed, 3 to 30 characters of `[a-zA-Z0-9_-]`. The message
/// of the first one broken
pub fn validate_username(username: &str) -> Result<(), String> {
    let username = username.trim();
    if username.is_empty() {
        return Err("Username is required".into());
    }
    let len = username.chars().count();
    if len < 3 {
        return Err("Username must be at least 3 characters".into());
    }
    if len > 30 {
        return Err("Username must be at most 30 characters".into());
    }
    if !username
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return Err("Username may only contain letters, digits, underscores and hyphens".into());
    }
    Ok(())
}

/// A password's rules, at sign-up and on a change (`ChangePassword`): 6 to 100 characters,
/// not trimmed
pub fn validate_password(password: &str) -> Result<(), String> {
    let len = password.chars().count();
    if len < 6 {
        return Err("Password must be at least 6 characters".into());
    }
    if len > 100 {
        return Err("Password must be at most 100 characters".into());
    }
    Ok(())
}

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

    pub async fn execute(
        &self,
        input: RegisterUserInput,
    ) -> Result<RegisterUserOutput, RegisterError> {
        // Validate input
        validate_username(&input.username).map_err(RegisterError::Validation)?;
        validate_password(&input.password).map_err(RegisterError::Validation)?;
        if is_reserved_username(&input.username) {
            return Err(RegisterError::Reserved);
        }

        // Check if username exists
        let username = input.username.trim().to_string();
        if self.user_repo.exists_by_username_ci(&username).await? {
            return Err(RegisterError::UsernameExists);
        }

        // Hash password
        let password_hash = PasswordService::hash(&input.password)
            .map_err(|e| RegisterError::Internal(e.to_string()))?;

        // Create user
        let user_id = Uuid::new_v4().to_string();
        let user = User::new_human(user_id, username, password_hash);

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
    #[error("Username is reserved")]
    Reserved,
    #[error("Internal error: {0}")]
    Internal(String),
    #[error("Repository error: {0}")]
    Repository(#[from] crate::domain::repositories::RepositoryError),
}
