//! Delete a bot user. Port of `src/use-cases/bot/DeleteBot.js`, plus a refusal Node
//! lacks: a bot seated in a waiting or playing party is kept, since deleting it would
//! cascade its seat away mid-game.

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
        if self.user_repo.is_in_active_party(bot_id).await? {
            return Err(BotAdminError::Invalid(
                "Bot is in an active party - cannot delete it".into(),
            ));
        }
        // Another request may have deleted it since the lookup: Node's message then
        if !self.user_repo.delete(bot_id).await? {
            return Err(BotAdminError::Invalid("Failed to delete bot".into()));
        }
        tracing::info!("Bot deleted: {} ({})", bot.username, bot_id);
        Ok(bot_id.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::entities::{BotDifficulty, User};
    use crate::infrastructure::database::repositories::racing_user_repo::RacingUserRepo;

    async fn repo_with_bot() -> (Arc<RacingUserRepo>, User) {
        let repo = Arc::new(RacingUserRepo::new().await);
        let bot = User::new_bot("bot-1".into(), "RoboBot".into(), BotDifficulty::Easy);
        repo.save(&bot).await.unwrap();
        (repo, bot)
    }

    #[tokio::test]
    async fn bot_in_an_active_party_is_kept() {
        for status in ["waiting", "playing"] {
            let (repo, bot) = repo_with_bot().await;
            repo.seat_in_party(&bot.id, status).await;
            let err = DeleteBot::new(repo.clone())
                .execute(&bot.id)
                .await
                .unwrap_err();
            assert_eq!(
                err.to_string(),
                "Bot is in an active party - cannot delete it"
            );
            assert!(repo.find_by_id(&bot.id).await.unwrap().is_some());
        }

        // A finished party does not hold the bot
        let (repo, bot) = repo_with_bot().await;
        repo.seat_in_party(&bot.id, "finished").await;
        assert_eq!(
            DeleteBot::new(repo.clone()).execute(&bot.id).await.unwrap(),
            bot.id
        );
    }

    #[tokio::test]
    async fn second_concurrent_delete_fails_like_node() {
        let (repo, bot) = repo_with_bot().await;
        DeleteBot::new(repo.clone()).execute(&bot.id).await.unwrap();

        // The second request looked the bot up before the first one deleted it
        *repo.stale_user.lock().unwrap() = Some(bot.clone());
        let err = DeleteBot::new(repo.clone())
            .execute(&bot.id)
            .await
            .unwrap_err();
        assert_eq!(err.to_string(), "Failed to delete bot");
    }
}
