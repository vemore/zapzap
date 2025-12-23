use serde::{Deserialize, Serialize};

/// PartyPlayer entity - represents a player in a party
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PartyPlayer {
    pub id: i64,
    pub party_id: String,
    pub user_id: String,
    pub player_index: u8,
    pub joined_at: i64,
}

impl PartyPlayer {
    /// Create a new party player
    pub fn new(party_id: String, user_id: String, player_index: u8) -> Self {
        Self {
            id: 0, // Set by database
            party_id,
            user_id,
            player_index,
            joined_at: chrono::Utc::now().timestamp(),
        }
    }
}
