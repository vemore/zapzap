//! Create a bot user. Port of `src/use-cases/bot/CreateBot.js`; the error messages are
//! Node's, including the username checks of its `User` entity (`src/domain/entities/User.js:47-62`).

use std::sync::Arc;

use uuid::Uuid;

use crate::domain::entities::{BotDifficulty, User};
use crate::domain::repositories::UserRepository;

/// Difficulties `POST /api/bots` accepts (Node's list: `thibot` is not creatable)
pub const CREATABLE_DIFFICULTIES: [&str; 7] =
    ["easy", "medium", "hard", "hard_vince", "ml", "drl", "llm"];

/// Create bot use case
pub struct CreateBot {
    user_repo: Arc<dyn UserRepository>,
}

impl CreateBot {
    pub fn new(user_repo: Arc<dyn UserRepository>) -> Self {
        Self { user_repo }
    }

    /// `username` and `difficulty` are `None` when absent from the body or not strings
    pub async fn execute(
        &self,
        username: Option<&str>,
        difficulty: Option<&str>,
    ) -> Result<User, BotAdminError> {
        let username = username
            .filter(|u| !u.is_empty())
            .ok_or_else(|| BotAdminError::Invalid("Username is required".into()))?;

        let difficulty = difficulty
            .map(str::to_lowercase)
            .filter(|d| CREATABLE_DIFFICULTIES.contains(&d.as_str()))
            .and_then(|d| BotDifficulty::from_str(&d))
            .ok_or_else(|| {
                BotAdminError::Invalid(format!(
                    "Difficulty must be one of: {}",
                    CREATABLE_DIFFICULTIES.join(", ")
                ))
            })?;

        let username = username.trim();
        if self.user_repo.find_by_username(username).await?.is_some() {
            return Err(BotAdminError::Invalid(format!(
                "Username \"{}\" already exists",
                username
            )));
        }
        validate_username(username)?;

        let bot = User::new_bot(Uuid::new_v4().to_string(), username.to_string(), difficulty);
        self.user_repo.save(&bot).await?;
        tracing::info!("Bot created: {} ({})", bot.username, bot.id);
        Ok(bot)
    }
}

fn validate_username(username: &str) -> Result<(), BotAdminError> {
    let invalid = |m: &str| Err(BotAdminError::Invalid(m.to_string()));
    if username.is_empty() {
        return invalid("Username is required and must be a string");
    }
    let len = username.chars().count();
    if len < 3 {
        return invalid("Username must be at least 3 characters long");
    }
    if len > 50 {
        return invalid("Username must not exceed 50 characters");
    }
    if !username
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return invalid(
            "Username can only contain alphanumeric characters, hyphens, and underscores",
        );
    }
    Ok(())
}

/// Bot admin errors. Node answers every one of them with 400 `{success:false, error}`.
#[derive(Debug, thiserror::Error)]
pub enum BotAdminError {
    #[error("{0}")]
    Invalid(String),
    #[error("{0}")]
    Repository(#[from] crate::domain::repositories::RepositoryError),
}
