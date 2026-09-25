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
    /// `public` or `private`: SSE sends a public party's deletion to every stream
    pub deleted_party_visibility: String,
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

    pub async fn execute(
        &self,
        input: DeletePartyInput,
    ) -> Result<DeletePartyOutput, DeletePartyError> {
        // Find party
        let party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(DeletePartyError::PartyNotFound)?;

        // The Node backend's order: a member, then the owner or the only human
        // player, then a party not in play
        let players = self.party_repo.get_party_players(&input.party_id).await?;
        if !players.iter().any(|p| p.user_id == input.user_id) {
            return Err(DeletePartyError::NotInParty);
        }

        let mut is_human = false;
        let mut other_humans = 0;
        for p in &players {
            let Some(u) = self.user_repo.find_by_id(&p.user_id).await? else {
                continue;
            };
            if u.is_bot() {
                continue;
            }
            if p.user_id == input.user_id {
                is_human = true;
            } else {
                other_humans += 1;
            }
        }
        let is_only_human = is_human && other_humans == 0;

        if party.owner_id != input.user_id && !is_only_human {
            return Err(DeletePartyError::NotOwner);
        }

        // The only human in a game against bots may end it; anyone else waits for its end
        if party.status == PartyStatus::Playing && !is_only_human {
            return Err(DeletePartyError::PartyInProgress);
        }

        let party_id = party.id.clone();
        let party_name = party.name.clone();
        let deleted_party_visibility = party.visibility.as_str().to_string();

        // Delete party
        self.party_repo.delete(&input.party_id).await?;

        Ok(DeletePartyOutput {
            deleted_party_id: party_id,
            deleted_party_name: party_name,
            deleted_party_visibility,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum DeletePartyError {
    #[error("Party not found")]
    PartyNotFound,
    #[error("User is not in this party")]
    NotInParty,
    #[error("Not the party owner")]
    NotOwner,
    #[error("Cannot delete party in progress")]
    PartyInProgress,
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
