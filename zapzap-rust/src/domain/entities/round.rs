use serde::{Deserialize, Serialize};

/// Round status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RoundStatus {
    Active,
    Finished,
}

impl RoundStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            RoundStatus::Active => "active",
            RoundStatus::Finished => "finished",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "active" => Some(RoundStatus::Active),
            "finished" => Some(RoundStatus::Finished),
            _ => None,
        }
    }
}

/// Round entity
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Round {
    pub id: String,
    pub party_id: String,
    pub round_number: u32,
    pub status: RoundStatus,
    pub current_turn: u8,
    pub current_action: String,
    pub created_at: i64,
    pub finished_at: Option<i64>,
}

impl Round {
    /// Create a new round
    /// Note: current_action in Round table is only for draw/play/zapzap
    /// The selectHandSize action is stored in GameState JSON
    /// starting_player is stored in GameState, not in rounds table
    pub fn new(id: String, party_id: String, round_number: u32, starting_player: u8) -> Self {
        Self {
            id,
            party_id,
            round_number,
            status: RoundStatus::Active,
            current_turn: starting_player,
            current_action: "draw".to_string(), // Default to draw, selectHandSize is in GameState
            created_at: chrono::Utc::now().timestamp(),
            finished_at: None,
        }
    }

    /// Finish the round
    pub fn finish(&mut self) {
        self.status = RoundStatus::Finished;
        self.finished_at = Some(chrono::Utc::now().timestamp());
    }
}
