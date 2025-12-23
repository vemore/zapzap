use std::sync::Arc;

use crate::domain::entities::PartyStatus;
use crate::domain::repositories::{PartyRepository, RepositoryError, UserRepository};

/// Leave party input
pub struct LeavePartyInput {
    pub user_id: String,
    pub party_id: String,
}

/// Leave party output
pub struct LeavePartyOutput {
    pub new_owner_id: Option<String>,
    pub party_deleted: bool,
}

/// Leave party use case
pub struct LeaveParty<U: UserRepository, P: PartyRepository> {
    user_repo: Arc<U>,
    party_repo: Arc<P>,
}

impl<U: UserRepository, P: PartyRepository> LeaveParty<U, P> {
    pub fn new(user_repo: Arc<U>, party_repo: Arc<P>) -> Self {
        Self {
            user_repo,
            party_repo,
        }
    }

    pub async fn execute(
        &self,
        input: LeavePartyInput,
    ) -> Result<LeavePartyOutput, LeavePartyError> {
        // Find party
        let mut party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(LeavePartyError::PartyNotFound)?;

        // Check party status
        if party.status != PartyStatus::Waiting {
            return Err(LeavePartyError::PartyNotWaiting);
        }

        // Check if user is in party
        if !self
            .party_repo
            .is_player_in_party(&input.party_id, &input.user_id)
            .await?
        {
            return Err(LeavePartyError::NotInParty);
        }

        // Remove player from party
        self.party_repo
            .remove_party_player(&input.party_id, &input.user_id)
            .await?;

        // Get remaining players
        let remaining_players = self.party_repo.get_party_players(&input.party_id).await?;

        // Check if party should be deleted (no human players left)
        let human_players: Vec<_> = {
            let mut humans = Vec::new();
            for player in &remaining_players {
                if let Some(user) = self.user_repo.find_by_id(&player.user_id).await? {
                    if !user.is_bot() {
                        humans.push(player.clone());
                    }
                }
            }
            humans
        };

        if human_players.is_empty() {
            // Delete party
            self.party_repo.delete(&input.party_id).await?;
            return Ok(LeavePartyOutput {
                new_owner_id: None,
                party_deleted: true,
            });
        }

        // If owner left, transfer ownership
        let mut new_owner_id = None;
        if party.owner_id == input.user_id {
            // Find new owner (first human player)
            if let Some(new_owner) = human_players.first() {
                party.owner_id = new_owner.user_id.clone();
                new_owner_id = Some(new_owner.user_id.clone());
                self.party_repo.save(&party).await?;
            }
        }

        Ok(LeavePartyOutput {
            new_owner_id,
            party_deleted: false,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum LeavePartyError {
    #[error("Party not found")]
    PartyNotFound,
    #[error("Party is not in waiting state")]
    PartyNotWaiting,
    #[error("Not in party")]
    NotInParty,
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
