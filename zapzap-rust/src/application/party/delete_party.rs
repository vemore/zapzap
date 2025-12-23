use std::sync::Arc;

use crate::domain::entities::PartyStatus;
use crate::domain::repositories::{PartyRepository, RepositoryError, UserRepository};

/// Delete party input
pub struct DeletePartyInput {
    pub user_id: String,
    pub party_id: String,
}

/// Delete party output
pub struct DeletePartyOutput {
    pub deleted_party_id: String,
    pub deleted_party_name: String,
}

/// Delete party use case
pub struct DeleteParty<U: UserRepository, P: PartyRepository> {
    user_repo: Arc<U>,
    party_repo: Arc<P>,
}

impl<U: UserRepository, P: PartyRepository> DeleteParty<U, P> {
    pub fn new(user_repo: Arc<U>, party_repo: Arc<P>) -> Self {
        Self {
            user_repo,
            party_repo,
        }
    }

    pub async fn execute(&self, input: DeletePartyInput) -> Result<DeletePartyOutput, DeletePartyError> {
        // Find party
        let party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(DeletePartyError::PartyNotFound)?;

        // Check party status
        if party.status == PartyStatus::Playing {
            return Err(DeletePartyError::PartyInProgress);
        }

        // Check if user is owner
        if party.owner_id != input.user_id {
            // Check if user is the only human player
            let players = self.party_repo.get_party_players(&input.party_id).await?;
            let mut is_only_human = false;

            for player in &players {
                if player.user_id == input.user_id {
                    if let Some(user) = self.user_repo.find_by_id(&player.user_id).await? {
                        if !user.is_bot() {
                            // Count other humans
                            let mut other_humans = 0;
                            for p in &players {
                                if p.user_id != input.user_id {
                                    if let Some(u) = self.user_repo.find_by_id(&p.user_id).await? {
                                        if !u.is_bot() {
                                            other_humans += 1;
                                        }
                                    }
                                }
                            }
                            is_only_human = other_humans == 0;
                        }
                    }
                }
            }

            if !is_only_human {
                return Err(DeletePartyError::NotOwner);
            }
        }

        let party_id = party.id.clone();
        let party_name = party.name.clone();

        // Delete party
        self.party_repo.delete(&input.party_id).await?;

        Ok(DeletePartyOutput {
            deleted_party_id: party_id,
            deleted_party_name: party_name,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum DeletePartyError {
    #[error("Party not found")]
    PartyNotFound,
    #[error("Not the party owner")]
    NotOwner,
    #[error("Cannot delete party in progress")]
    PartyInProgress,
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
