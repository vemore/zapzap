use std::sync::Arc;

use super::seat::{seat_player, Seating};
use crate::domain::entities::{Party, PartyStatus, User};
use crate::domain::repositories::{PartyRepository, RepositoryError, UserRepository};

/// Add bot input
pub struct AddBotToPartyInput {
    /// The user asking: must own the party
    pub user_id: String,
    pub party_id: String,
    pub bot_id: String,
}

/// Add bot output
pub struct AddBotToPartyOutput {
    pub party: Party,
    pub bot: User,
    pub player_index: u8,
}

/// The owner fills a free seat of a waiting party with a bot
pub struct AddBotToParty<U: UserRepository, P: PartyRepository> {
    user_repo: Arc<U>,
    party_repo: Arc<P>,
}

impl<U: UserRepository, P: PartyRepository> AddBotToParty<U, P> {
    pub fn new(user_repo: Arc<U>, party_repo: Arc<P>) -> Self {
        Self {
            user_repo,
            party_repo,
        }
    }

    pub async fn execute(
        &self,
        input: AddBotToPartyInput,
    ) -> Result<AddBotToPartyOutput, AddBotToPartyError> {
        let party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(AddBotToPartyError::PartyNotFound)?;

        if party.owner_id != input.user_id {
            return Err(AddBotToPartyError::NotOwner);
        }

        if party.status != PartyStatus::Waiting {
            return Err(AddBotToPartyError::PartyNotWaiting);
        }

        let bot = self
            .user_repo
            .find_by_id(&input.bot_id)
            .await?
            .ok_or(AddBotToPartyError::BotNotFound)?;
        if !bot.is_bot() {
            return Err(AddBotToPartyError::NotABot);
        }

        let player_index = match seat_player(&*self.party_repo, &party, &input.bot_id).await? {
            Seating::Seated(seat) => seat,
            Seating::Full => return Err(AddBotToPartyError::PartyFull),
            Seating::AlreadyIn => return Err(AddBotToPartyError::AlreadyInParty),
        };

        Ok(AddBotToPartyOutput {
            party,
            bot,
            player_index,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum AddBotToPartyError {
    #[error("Party not found")]
    PartyNotFound,
    #[error("Not the party owner")]
    NotOwner,
    #[error("Party is not in waiting state")]
    PartyNotWaiting,
    #[error("Party is full")]
    PartyFull,
    #[error("Bot not found")]
    BotNotFound,
    #[error("User is not a bot")]
    NotABot,
    #[error("Bot already in party")]
    AlreadyInParty,
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
