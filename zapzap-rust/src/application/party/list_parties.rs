use std::sync::Arc;

use crate::domain::entities::PartyStatus;
use crate::domain::repositories::{PartyRepository, RepositoryError};
use crate::domain::value_objects::GameAction;

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
    pub status: String,
    pub player_count: usize,
    pub max_players: u8,
    pub is_member: bool,
    /// The caller is a member of this playing party and the current turn is theirs
    pub is_my_turn: bool,
    /// Unix seconds
    pub created_at: i64,
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
        let status = input.status.as_deref().and_then(PartyStatus::from_str);

        // Use optimized query that fetches parties with player counts in one query
        let parties_with_counts = self
            .party_repo
            .find_public_parties_with_counts(status, input.limit as u32, input.offset as u32)
            .await?;

        let total = parties_with_counts.len();
        let mut result: Vec<PartyListItem> = Vec::with_capacity(total);
        for pwc in parties_with_counts {
            let is_member = input
                .user_id
                .as_ref()
                .map(|uid| pwc.player_user_ids.contains(uid))
                .unwrap_or(false);

            // Whose turn: read only for the caller's own playing parties
            let is_my_turn = match (&input.user_id, is_member, pwc.party.status) {
                (Some(uid), true, PartyStatus::Playing) => {
                    self.is_players_turn(&pwc.party.id, uid).await?
                }
                _ => false,
            };

            result.push(PartyListItem {
                id: pwc.party.id.clone(),
                name: pwc.party.name.clone(),
                owner_id: pwc.party.owner_id.clone(),
                invite_code: pwc.party.invite_code.clone(),
                status: pwc.party.status.as_str().to_string(),
                player_count: pwc.player_count,
                max_players: pwc.party.settings.player_count,
                is_member,
                is_my_turn,
                created_at: pwc.party.created_at,
            });
        }

        Ok(ListPartiesOutput {
            parties: result,
            total,
            limit: input.limit,
            offset: input.offset,
        })
    }

    /// True when a round is under way and its current turn is this user's seat.
    async fn is_players_turn(
        &self,
        party_id: &str,
        user_id: &str,
    ) -> Result<bool, RepositoryError> {
        let Some(index) = self.party_repo.get_player_index(party_id, user_id).await? else {
            return Ok(false);
        };
        let Some(state) = self.party_repo.get_game_state(party_id).await? else {
            return Ok(false);
        };
        Ok(state.current_action != GameAction::Finished && state.current_turn == index)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ListPartiesError {
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
