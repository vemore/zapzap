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

/// The lowest seat no player holds: a player who left a waiting party leaves a gap in the
/// seats, which `players.len()` would collide with (`UNIQUE(party_id, player_index)`).
pub fn lowest_free_seat(players: &[PartyPlayer]) -> u8 {
    (0u8..)
        .find(|i| !players.iter().any(|p| p.player_index == *i))
        .unwrap_or(u8::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lowest_free_seat_fills_the_first_gap() {
        let seat = |i| PartyPlayer::new("p".into(), format!("u{i}"), i);
        assert_eq!(lowest_free_seat(&[]), 0);
        assert_eq!(lowest_free_seat(&[seat(0), seat(1)]), 2);
        assert_eq!(lowest_free_seat(&[seat(0), seat(2), seat(3)]), 1);
    }
}
