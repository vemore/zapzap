use std::sync::Arc;

use crate::domain::entities::{Party, PartyStatus};
use crate::domain::repositories::{PartyRepository, RepositoryError, UserRepository};

/// Join party input
pub struct JoinPartyInput {
    pub user_id: String,
    pub party_id: String,
    pub invite_code: Option<String>,
}

/// Join party output
pub struct JoinPartyOutput {
    pub party: Party,
    pub player_index: u8,
}

/// Join party use case
pub struct JoinParty<U: UserRepository, P: PartyRepository> {
    user_repo: Arc<U>,
    party_repo: Arc<P>,
}

impl<U: UserRepository, P: PartyRepository> JoinParty<U, P> {
    pub fn new(user_repo: Arc<U>, party_repo: Arc<P>) -> Self {
        Self {
            user_repo,
            party_repo,
        }
    }

    pub async fn execute(&self, input: JoinPartyInput) -> Result<JoinPartyOutput, JoinPartyError> {
        // Validate user exists
        let user = self
            .user_repo
            .find_by_id(&input.user_id)
            .await?
            .ok_or(JoinPartyError::UserNotFound)?;

        if user.is_bot() {
            return Err(JoinPartyError::Validation("Bots cannot join parties directly".into()));
        }

        // Find party
        let party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(JoinPartyError::PartyNotFound)?;

        // Check party status
        if party.status != PartyStatus::Waiting {
            return Err(JoinPartyError::PartyNotWaiting);
        }

        // Check if already in party
        if self
            .party_repo
            .is_player_in_party(&input.party_id, &input.user_id)
            .await?
        {
            return Err(JoinPartyError::AlreadyInParty);
        }

        // Get current players
        let players = self.party_repo.get_party_players(&input.party_id).await?;

        // Check if party is full
        if party.is_full(players.len()) {
            return Err(JoinPartyError::PartyFull);
        }

        // Assign next player index
        let player_index = players.len() as u8;

        // Add player to party
        self.party_repo
            .add_party_player(&input.party_id, &input.user_id, player_index)
            .await?;

        Ok(JoinPartyOutput {
            party,
            player_index,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum JoinPartyError {
    #[error("Validation error: {0}")]
    Validation(String),
    #[error("User not found")]
    UserNotFound,
    #[error("Party not found")]
    PartyNotFound,
    #[error("Party is not in waiting state")]
    PartyNotWaiting,
    #[error("Already in party")]
    AlreadyInParty,
    #[error("Party is full")]
    PartyFull,
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
