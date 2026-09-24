use serde::{Deserialize, Serialize};

/// Fewest seats a party can have (Node: `PartySettings.js`, `validate`)
pub const MIN_PLAYER_COUNT: u8 = 3;
/// Most seats a party can have; also the game state's `MAX_PLAYERS`
pub const MAX_PLAYER_COUNT: u8 = 8;

/// Party settings, Node's `{playerCount, allowSpectators, roundTimeLimit}`
/// (`src/domain/value-objects/PartySettings.js`). They are stored as JSON in
/// `parties.settings_json`, where Node writes the same three keys. The hand size is
/// not a setting: the starting player picks it at the start of each round.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PartySettings {
    /// The party's seats (3-8): a join past it answers 409 `PARTY_FULL`. A row Rust
    /// wrote before it stored this key reads as 8, the seats Rust gave every party.
    #[serde(default = "legacy_player_count")]
    pub player_count: u8,
    #[serde(default)]
    pub allow_spectators: bool,
    /// Seconds per round, 0 = unlimited (stored, not enforced, as on Node)
    #[serde(default)]
    pub round_time_limit: u32,
}

fn legacy_player_count() -> u8 {
    MAX_PLAYER_COUNT
}

impl Default for PartySettings {
    /// Node's `PartySettings.createDefault()`
    fn default() -> Self {
        Self {
            player_count: 5,
            allow_spectators: false,
            round_time_limit: 0,
        }
    }
}

impl PartySettings {
    /// Node's validation: 3 to 8 players
    pub fn validate(&self) -> Result<(), &'static str> {
        if !(MIN_PLAYER_COUNT..=MAX_PLAYER_COUNT).contains(&self.player_count) {
            return Err("Player count must be between 3 and 8");
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_settings_node_writes() {
        // PartySettings.toJSON() on Node
        let s: PartySettings =
            serde_json::from_str(r#"{"playerCount":4,"allowSpectators":true,"roundTimeLimit":60}"#)
                .unwrap();
        assert_eq!(
            s,
            PartySettings {
                player_count: 4,
                allow_spectators: true,
                round_time_limit: 60
            }
        );
    }

    #[test]
    fn writes_nodes_keys() {
        let json = serde_json::to_value(PartySettings::default()).unwrap();
        assert_eq!(
            json,
            serde_json::json!({"playerCount": 5, "allowSpectators": false, "roundTimeLimit": 0})
        );
    }

    #[test]
    fn a_row_rust_wrote_before_player_count_keeps_eight_seats() {
        let s: PartySettings = serde_json::from_str(
            r#"{"handSize":5,"maxScore":100,"enableGoldenScore":true,"goldenScoreThreshold":100}"#,
        )
        .unwrap();
        assert_eq!(s.player_count, 8);
        assert!(!s.allow_spectators);
        assert_eq!(s.round_time_limit, 0);
    }

    #[test]
    fn validates_three_to_eight_players() {
        for (count, ok) in [(2, false), (3, true), (8, true), (9, false)] {
            let s = PartySettings {
                player_count: count,
                ..Default::default()
            };
            assert_eq!(s.validate().is_ok(), ok, "{count}");
        }
    }
}
