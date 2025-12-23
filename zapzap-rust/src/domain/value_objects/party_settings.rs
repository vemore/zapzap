use serde::{Deserialize, Serialize};

/// Party settings configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PartySettings {
    /// Cards dealt per player (4-7)
    pub hand_size: u8,
    /// Maximum score to win (default 100)
    pub max_score: u16,
    /// Enable golden score mode
    pub enable_golden_score: bool,
    /// Score threshold for golden score mode
    pub golden_score_threshold: u16,
}

impl Default for PartySettings {
    fn default() -> Self {
        Self {
            hand_size: 5,
            max_score: 100,
            enable_golden_score: true,
            golden_score_threshold: 100,
        }
    }
}

impl PartySettings {
    pub fn new(hand_size: u8) -> Self {
        Self {
            hand_size: hand_size.clamp(4, 7),
            ..Default::default()
        }
    }

    pub fn validate(&self) -> Result<(), &'static str> {
        if self.hand_size < 4 || self.hand_size > 7 {
            return Err("Hand size must be between 4 and 7");
        }
        Ok(())
    }
}
