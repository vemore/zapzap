use serde::{Deserialize, Serialize};

use crate::domain::value_objects::PartySettings;

/// Party visibility
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PartyVisibility {
    Public,
    Private,
}

impl PartyVisibility {
    pub fn as_str(&self) -> &'static str {
        match self {
            PartyVisibility::Public => "public",
            PartyVisibility::Private => "private",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "public" => Some(PartyVisibility::Public),
            "private" => Some(PartyVisibility::Private),
            _ => None,
        }
    }
}

/// Party status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PartyStatus {
    Waiting,
    Playing,
    Finished,
}

impl PartyStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            PartyStatus::Waiting => "waiting",
            PartyStatus::Playing => "playing",
            PartyStatus::Finished => "finished",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "waiting" => Some(PartyStatus::Waiting),
            "playing" => Some(PartyStatus::Playing),
            "finished" => Some(PartyStatus::Finished),
            _ => None,
        }
    }
}

/// Party entity
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Party {
    pub id: String,
    pub name: String,
    pub owner_id: String,
    pub invite_code: String,
    pub visibility: PartyVisibility,
    pub status: PartyStatus,
    pub settings: PartySettings,
    pub current_round_id: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

impl Party {
    /// Create a new party
    pub fn new(
        id: String,
        name: String,
        owner_id: String,
        invite_code: String,
        visibility: PartyVisibility,
        settings: PartySettings,
    ) -> Self {
        let now = chrono::Utc::now().timestamp();
        Self {
            id,
            name,
            owner_id,
            invite_code,
            visibility,
            status: PartyStatus::Waiting,
            settings,
            current_round_id: None,
            created_at: now,
            updated_at: now,
        }
    }

    /// Check if party is full (max 8 players)
    pub fn is_full(&self, current_player_count: usize) -> bool {
        current_player_count >= 8
    }

    /// Check if party can be started
    pub fn can_start(&self, current_player_count: usize) -> bool {
        self.status == PartyStatus::Waiting
            && current_player_count >= 3
            && current_player_count <= 8
    }

    /// Start the party
    pub fn start(&mut self) {
        self.status = PartyStatus::Playing;
        self.updated_at = chrono::Utc::now().timestamp();
    }

    /// Finish the party
    pub fn finish(&mut self) {
        self.status = PartyStatus::Finished;
        self.updated_at = chrono::Utc::now().timestamp();
    }
}

/// Generate a random 8-character invite code
pub fn generate_invite_code() -> String {
    use rand::Rng;
    const CHARSET: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let mut rng = rand::thread_rng();
    (0..8)
        .map(|_| {
            let idx = rng.gen_range(0..CHARSET.len());
            CHARSET[idx] as char
        })
        .collect()
}
