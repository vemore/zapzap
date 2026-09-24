//! Delete a bot user. Port of `src/use-cases/bot/DeleteBot.js`.

use std::sync::Arc;

use crate::application::bot::BotAdminError;
use crate::domain::repositories::UserRepository;

/// Delete bot use case
pub struct DeleteBot {
    user_repo: Arc<dyn UserRepository>,
}

impl DeleteBot {
    pub fn new(user_repo: Arc<dyn UserRepository>) -> Self {
        Self { user_repo }
    }

    /// Deletes the bot and returns its id; a human user is refused
    pub async fn execute(&self, bot_id: &str) -> Result<String, BotAdminError> {
        if bot_id.is_empty() {
            return Err(BotAdminError::Invalid("Bot ID is required".into()));
        }
        let bot = self
            .user_repo
            .find_by_id(bot_id)
            .await?
            .ok_or_else(|| BotAdminError::Invalid("Bot not found".into()))?;
        if !bot.is_bot() {
            return Err(BotAdminError::Invalid(
                "User is not a bot - cannot delete human users via this endpoint".into(),
            ));
        }
        self.user_repo.delete(bot_id).await?;
        tracing::info!("Bot deleted: {} ({})", bot.username, bot_id);
        Ok(bot_id.to_string())
    }
}
