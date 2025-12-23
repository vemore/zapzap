use std::sync::Arc;

use crate::domain::entities::PartyStatus;
use crate::domain::repositories::{PartyRepository, RepositoryError};

/// List parties input
pub struct ListPartiesInput {
    pub user_id: Option<String>,
    pub status: Option<String>,
    pub limit: i32,
    pub offset: i32,
}

/// Party list item
pub struct PartyListItem {
    pub id: String,
    pub name: String,
    pub owner_id: String,
    pub invite_code: String,
    pub visibility: String,
    pub status: String,
    pub player_count: usize,
    pub max_players: u8,
    pub is_member: bool,
    pub created_at: String,
}

/// List parties output
pub struct ListPartiesOutput {
    pub parties: Vec<PartyListItem>,
    pub total: usize,
    pub limit: i32,
    pub offset: i32,
}

/// List public parties use case
pub struct ListPublicParties<P: PartyRepository> {
    party_repo: Arc<P>,
}

impl<P: PartyRepository> ListPublicParties<P> {
    pub fn new(party_repo: Arc<P>) -> Self {
        Self { party_repo }
    }

    pub async fn execute(
        &self,
        input: ListPartiesInput,
    ) -> Result<ListPartiesOutput, ListPartiesError> {
        let status = input
            .status
            .as_deref()
            .and_then(PartyStatus::from_str);

        // Use optimized query that fetches parties with player counts in one query
        let parties_with_counts = self
            .party_repo
            .find_public_parties_with_counts(status, input.limit as u32, input.offset as u32)
            .await?;

        let total = parties_with_counts.len();
        let result: Vec<PartyListItem> = parties_with_counts
            .into_iter()
            .map(|pwc| {
                let is_member = input.user_id.as_ref()
                    .map(|uid| pwc.player_user_ids.contains(uid))
                    .unwrap_or(false);

                PartyListItem {
                    id: pwc.party.id.clone(),
                    name: pwc.party.name.clone(),
                    owner_id: pwc.party.owner_id.clone(),
                    invite_code: pwc.party.invite_code.clone(),
                    visibility: pwc.party.visibility.as_str().to_string(),
                    status: pwc.party.status.as_str().to_string(),
                    player_count: pwc.player_count,
                    max_players: 8, // Max players in game
                    is_member,
                    created_at: chrono::DateTime::from_timestamp(pwc.party.created_at, 0)
                        .map(|dt| dt.to_rfc3339())
                        .unwrap_or_default(),
                }
            })
            .collect();

        Ok(ListPartiesOutput {
            parties: result,
            total,
            limit: input.limit,
            offset: input.offset,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ListPartiesError {
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
