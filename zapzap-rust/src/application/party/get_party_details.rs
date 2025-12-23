use std::sync::Arc;

use crate::domain::entities::Party;
use crate::domain::repositories::{PartyRepository, RepositoryError, UserRepository};

/// Get party details input
pub struct GetPartyDetailsInput {
    pub party_id: String,
    pub user_id: String,
}

/// Player info with user details
pub struct PlayerInfo {
    pub id: String,
    pub user_id: String,
    pub username: String,
    pub user_type: String,
    pub bot_difficulty: Option<String>,
    pub player_index: u8,
    pub joined_at: String,
}

/// Get party details output
pub struct GetPartyDetailsOutput {
    pub party: Party,
    pub players: Vec<PlayerInfo>,
    pub is_owner: bool,
    pub user_player_index: Option<u8>,
}

/// Get party details use case
pub struct GetPartyDetails<U: UserRepository, P: PartyRepository> {
    user_repo: Arc<U>,
    party_repo: Arc<P>,
}

impl<U: UserRepository, P: PartyRepository> GetPartyDetails<U, P> {
    pub fn new(user_repo: Arc<U>, party_repo: Arc<P>) -> Self {
        Self {
            user_repo,
            party_repo,
        }
    }

    pub async fn execute(
        &self,
        input: GetPartyDetailsInput,
    ) -> Result<GetPartyDetailsOutput, GetPartyDetailsError> {
        // Find party
        let party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(GetPartyDetailsError::PartyNotFound)?;

        // Get players
        let party_players = self.party_repo.get_party_players(&input.party_id).await?;

        // Find user's player index
        let user_player_index = party_players
            .iter()
            .find(|p| p.user_id == input.user_id)
            .map(|p| p.player_index);

        // Batch fetch all users (avoids N+1 queries)
        let user_ids: Vec<String> = party_players.iter().map(|pp| pp.user_id.clone()).collect();
        let users = self.user_repo.find_by_ids(&user_ids).await?;
        let users_map: std::collections::HashMap<String, _> = users
            .into_iter()
            .map(|u| (u.id.clone(), u))
            .collect();

        // Build player info
        let mut players = Vec::with_capacity(party_players.len());
        for pp in &party_players {
            if let Some(user) = users_map.get(&pp.user_id) {
                players.push(PlayerInfo {
                    id: pp.id.to_string(),
                    user_id: user.id.clone(),
                    username: user.username.clone(),
                    user_type: user.user_type.as_str().to_string(),
                    bot_difficulty: user.bot_difficulty.map(|d| d.as_str().to_string()),
                    player_index: pp.player_index,
                    joined_at: chrono::DateTime::from_timestamp(pp.joined_at, 0)
                        .map(|dt| dt.to_rfc3339())
                        .unwrap_or_default(),
                });
            }
        }

        // Sort by player index
        players.sort_by_key(|p| p.player_index);

        // Check if requester is owner
        let is_owner = input.user_id == party.owner_id;

        Ok(GetPartyDetailsOutput {
            party,
            players,
            is_owner,
            user_player_index,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum GetPartyDetailsError {
    #[error("Party not found")]
    PartyNotFound,
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
