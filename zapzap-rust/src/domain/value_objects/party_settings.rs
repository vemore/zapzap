use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::MAX_PLAYERS;

/// Fewest seats a party can have (as the Node backend validated)
pub const MIN_PLAYER_COUNT: u8 = 3;
/// Most seats a party can have: the game state's `MAX_PLAYERS`
pub const MAX_PLAYER_COUNT: u8 = MAX_PLAYERS as u8;
/// The turn time limits a party can have, in seconds: off, 30 s, 1 min, 2 min
/// (GAME_RULES.md "Turn Time Limit")
pub const TURN_TIME_LIMITS: [u32; 4] = [0, 30, 60, 120];

/// Party settings, `{playerCount, allowSpectators, turnTimeLimit}`, stored as JSON in
/// `parties.settings_json`. The hand size is not a setting: the starting player picks it
/// at the start of each round.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PartySettings {
    /// The party's seats (3-8): a join past it answers 409 `PARTY_FULL`
    pub player_count: u8,
    pub allow_spectators: bool,
    /// Seconds a human has for each turn, one of `TURN_TIME_LIMITS`, 0 = off. Enforced
    /// only when the party starts with at least two humans (`StartParty`)
    pub turn_time_limit: u32,
}

impl Default for PartySettings {
    /// Node's `PartySettings.createDefault()`
    fn default() -> Self {
        Self {
            player_count: 5,
            allow_spectators: false,
            turn_time_limit: 0,
        }
    }
}

/// The refusal of a turn time limit that is not one of `TURN_TIME_LIMITS`
pub fn turn_time_limit_message() -> String {
    "Turn time limit must be 0 (off), 30, 60 or 120 seconds".to_string()
}

/// The refusal of a player count outside 3-8
pub fn player_count_message() -> String {
    format!("Player count must be between {MIN_PLAYER_COUNT} and {MAX_PLAYER_COUNT}")
}

/// A JSON number that is a whole number, as `u64` (`6` and `6.0`, not `6.5` or `-1`)
fn whole_number(value: &Value) -> Option<u64> {
    if let Some(n) = value.as_u64() {
        return Some(n);
    }
    let f = value.as_f64()?;
    (f >= 0.0 && f.fract() == 0.0 && f <= u64::MAX as f64).then_some(f as u64)
}

/// JavaScript truthiness, for the flags Node stored from whatever a client sent
fn truthy(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64().is_some_and(|f| f != 0.0 && !f.is_nan()),
        Value::String(s) => !s.is_empty(),
        Value::Array(_) | Value::Object(_) => true,
    }
}

impl PartySettings {
    /// 3 to 8 players (Node's validation), and a turn time limit of `TURN_TIME_LIMITS`
    pub fn validate(&self) -> Result<(), String> {
        if !(MIN_PLAYER_COUNT..=MAX_PLAYER_COUNT).contains(&self.player_count) {
            return Err(player_count_message());
        }
        if !TURN_TIME_LIMITS.contains(&self.turn_time_limit) {
            return Err(turn_time_limit_message());
        }
        Ok(())
    }

    /// A player count from a request: a whole number from 3 to 8, else the 3-8 message
    pub fn player_count_from(value: f64) -> Result<u8, String> {
        if value.fract() == 0.0
            && value >= MIN_PLAYER_COUNT as f64
            && value <= MAX_PLAYER_COUNT as f64
        {
            Ok(value as u8)
        } else {
            Err(player_count_message())
        }
    }

    /// Read `parties.settings_json` field by field, never failing: a party must stay
    /// readable whatever Node or an older Rust wrote. A missing or unreadable
    /// `playerCount` gives 8 seats — Rust's limit for every party before it stored one,
    /// and never fewer seats than a party already has; `allowSpectators` is JavaScript
    /// truthiness; `turnTimeLimit` one of `TURN_TIME_LIMITS`, else 0 (off). The Node-era
    /// `roundTimeLimit`, never enforced, is ignored. Anything unreadable is logged.
    pub fn from_stored_json(json: &str) -> Self {
        let mut settings = Self {
            player_count: MAX_PLAYER_COUNT,
            allow_spectators: false,
            turn_time_limit: 0,
        };
        let object = match serde_json::from_str::<Value>(json) {
            Ok(Value::Object(object)) => object,
            _ => {
                tracing::warn!("Unreadable party settings {json:?}: 8 seats assumed");
                return settings;
            }
        };

        if let Some(value) = object.get("playerCount") {
            match whole_number(value)
                .filter(|n| (MIN_PLAYER_COUNT as u64..=MAX_PLAYER_COUNT as u64).contains(n))
            {
                Some(n) => settings.player_count = n as u8,
                None => tracing::warn!("Unreadable playerCount in {json:?}: 8 seats assumed"),
            }
        }
        if let Some(value) = object.get("allowSpectators") {
            settings.allow_spectators = truthy(value);
        }
        if let Some(value) = object.get("turnTimeLimit") {
            match whole_number(value)
                .and_then(|n| u32::try_from(n).ok())
                .filter(|n| TURN_TIME_LIMITS.contains(n))
            {
                Some(n) => settings.turn_time_limit = n,
                None => tracing::warn!("Unreadable turnTimeLimit in {json:?}: off assumed"),
            }
        }
        settings
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_settings_it_writes_and_ignores_nodes_round_time_limit() {
        let s = PartySettings::from_stored_json(
            r#"{"playerCount":4,"allowSpectators":true,"turnTimeLimit":60}"#,
        );
        assert_eq!(
            s,
            PartySettings {
                player_count: 4,
                allow_spectators: true,
                turn_time_limit: 60
            }
        );
        // PartySettings.toJSON() on Node: a per-round limit it never enforced
        let s = PartySettings::from_stored_json(
            r#"{"playerCount":4,"allowSpectators":true,"roundTimeLimit":60}"#,
        );
        assert_eq!(s.turn_time_limit, 0);
    }

    #[test]
    fn writes_its_keys() {
        let json = serde_json::to_value(PartySettings::default()).unwrap();
        assert_eq!(
            json,
            serde_json::json!({"playerCount": 5, "allowSpectators": false, "turnTimeLimit": 0})
        );
    }

    #[test]
    fn a_row_rust_wrote_before_player_count_keeps_eight_seats() {
        let s = PartySettings::from_stored_json(
            r#"{"handSize":5,"maxScore":100,"enableGoldenScore":true,"goldenScoreThreshold":100}"#,
        );
        assert_eq!(s.player_count, 8);
        assert!(!s.allow_spectators);
        assert_eq!(s.turn_time_limit, 0);
    }

    #[test]
    fn a_loosely_typed_field_keeps_the_others() {
        // Node stored what the client sent: a number for the flag, floats for counts
        let s = PartySettings::from_stored_json(r#"{"playerCount":6,"allowSpectators":1}"#);
        assert_eq!(s.player_count, 6);
        assert!(s.allow_spectators);

        let s = PartySettings::from_stored_json(
            r#"{"playerCount":4.0,"allowSpectators":"","turnTimeLimit":30.0}"#,
        );
        assert_eq!(
            (s.player_count, s.allow_spectators, s.turn_time_limit),
            (4, false, 30)
        );

        // An unreadable field falls back alone; a limit that is not offered is off
        for limit in ["-5", "45", "\"30\""] {
            let s = PartySettings::from_stored_json(&format!(
                r#"{{"playerCount":"six","allowSpectators":true,"turnTimeLimit":{limit}}}"#
            ));
            assert_eq!(
                (s.player_count, s.allow_spectators, s.turn_time_limit),
                (8, true, 0),
                "{limit}"
            );
        }
    }

    #[test]
    fn unreadable_settings_give_eight_seats() {
        for json in ["", "not json", "[]", "null", r#"{"playerCount":2}"#] {
            assert_eq!(
                PartySettings::from_stored_json(json).player_count,
                8,
                "{json}"
            );
        }
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
        assert_eq!(PartySettings::player_count_from(6.0), Ok(6));
        assert_eq!(PartySettings::default().validate(), Ok(()));
        for bad in [2.0, 9.0, 3.5, 300.0, -1.0, f64::NAN] {
            assert_eq!(
                PartySettings::player_count_from(bad),
                Err("Player count must be between 3 and 8".to_string()),
                "{bad}"
            );
        }
    }

    #[test]
    fn validates_the_turn_time_limits_offered() {
        for (limit, ok) in [
            (0, true),
            (30, true),
            (60, true),
            (120, true),
            (45, false),
            (90, false),
            (1, false),
        ] {
            let s = PartySettings {
                turn_time_limit: limit,
                ..Default::default()
            };
            assert_eq!(s.validate().is_ok(), ok, "{limit}");
        }
    }
}
