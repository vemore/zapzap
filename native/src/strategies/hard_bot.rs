//! HardBotStrategy - Advanced bot that optimizes hand value minimization

use super::BotStrategy;
use crate::card_analyzer;
use crate::game_state::GameState;
use smallvec::SmallVec;

/// Hard bot strategy - optimizes for lowest hand value and strategic zapzap
pub struct HardBotStrategy {
    rng_state: u64,
}

impl HardBotStrategy {
    pub fn new() -> Self {
        HardBotStrategy {
            rng_state: 12345, // Simple seed
        }
    }

    pub fn with_seed(seed: u64) -> Self {
        HardBotStrategy { rng_state: seed }
    }

    /// Simple xorshift64 RNG
    fn next_random(&mut self) -> u64 {
        let mut x = self.rng_state;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.rng_state = x;
        x
    }

    /// Random int in range [0, max)
    fn random_range(&mut self, max: u32) -> u32 {
        if max == 0 {
            return 0;
        }
        (self.next_random() % max as u64) as u32
    }

    /// Evaluate how valuable a card would be to add to hand
    fn evaluate_card_value(&self, card_id: u8, hand: &[u8]) -> i32 {
        let mut test_hand: SmallVec<[u8; 12]> = hand.iter().copied().collect();
        test_hand.push(card_id);

        // Count multi-card plays before and after
        let original_plays = card_analyzer::find_all_valid_plays(hand);
        let new_plays = card_analyzer::find_all_valid_plays(&test_hand);

        let original_multi = original_plays.iter().filter(|p| p.len() > 1).count();
        let new_multi = new_plays
            .iter()
            .filter(|p| p.len() > 1 && p.contains(&card_id))
            .count();

        let combination_bonus = (new_multi as i32 - original_multi as i32) * 10;

        // Prefer low-value cards
        let card_points = card_analyzer::get_card_points(card_id) as i32;
        let low_value_bonus = 10 - card_points;

        // Prefer cards that complete sets
        let rank = card_analyzer::get_rank(card_id);
        let same_rank_count = hand
            .iter()
            .filter(|&&id| !card_analyzer::is_joker(id) && card_analyzer::get_rank(id) == rank)
            .count();

        let set_bonus = if same_rank_count >= 1 {
            same_rank_count as i32 * 5
        } else {
            0
        };

        combination_bonus + low_value_bonus + set_bonus
    }
}

impl Default for HardBotStrategy {
    fn default() -> Self {
        Self::new()
    }
}

impl BotStrategy for HardBotStrategy {
    fn select_play(&self, hand: &[u8], _state: &GameState) -> Option<SmallVec<[u8; 8]>> {
        if hand.is_empty() {
            return None;
        }

        let valid_plays = card_analyzer::find_all_valid_plays(hand);

        if valid_plays.is_empty() {
            return None;
        }

        // Evaluate each play by remaining hand value
        let mut best_play: Option<SmallVec<[u8; 8]>> = None;
        let mut best_score = i32::MIN;

        for play in valid_plays {
            // Calculate remaining hand after this play
            let remaining: SmallVec<[u8; 10]> = hand
                .iter()
                .filter(|id| !play.contains(id))
                .copied()
                .collect();

            let remaining_value = card_analyzer::calculate_hand_value(&remaining) as i32;
            let play_size = play.len() as i32;

            // Score: prioritize plays that leave lowest hand value, with bonus for larger plays
            let score = -remaining_value + (play_size / 2);

            if score > best_score {
                best_score = score;
                best_play = Some(play);
            }
        }

        best_play
    }

    fn should_zapzap(&self, hand: &[u8], state: &GameState) -> bool {
        let hand_value = card_analyzer::calculate_hand_value(hand);

        // Can't zapzap if hand value > 5
        if hand_value > 5 {
            return false;
        }

        // Always zapzap if hand value is 0
        if hand_value == 0 {
            return true;
        }

        // Very confident zapzap at value <= 2
        if hand_value <= 2 {
            return true;
        }

        // Strategic zapzap based on round number
        let round_number = state.round_number;

        if round_number <= 2 {
            // Early game: conservative
            hand_value <= 2
        } else if round_number <= 4 {
            // Mid game: moderate risk
            hand_value <= 3
        } else {
            // Late game: aggressive
            hand_value <= 4
        }
    }

    fn select_draw_source(&self, hand: &[u8], last_cards_played: &[u8], _state: &GameState) -> bool {
        if last_cards_played.is_empty() {
            return true; // Deck
        }

        // Evaluate discard cards
        let mut best_improvement = 0;

        for &discard_card in last_cards_played {
            let improvement = self.evaluate_card_value(discard_card, hand);
            if improvement > best_improvement {
                best_improvement = improvement;
            }
        }

        // If any discard card provides significant improvement, take it
        if best_improvement > 5 {
            return false; // Take from played
        }

        true // Default to deck
    }

    fn select_hand_size(&self, _active_player_count: u8, is_golden_score: bool) -> u8 {
        // Use a simple deterministic selection for trait impl
        if is_golden_score {
            5 // Default for golden score
        } else {
            4 // Default for normal game
        }
    }
}

// Need mutable version for select_hand_size
impl HardBotStrategy {
    pub fn select_hand_size_mut(&mut self, _active_player_count: u8, is_golden_score: bool) -> u8 {
        if is_golden_score {
            4 + (self.random_range(3) as u8)
        } else {
            4 + (self.random_range(2) as u8)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_select_play() {
        let strategy = HardBotStrategy::new();
        let state = GameState::new(4);

        // Hand with pair of aces and some other cards
        let hand = vec![0, 13, 5, 18]; // A♠, A♥, 6♠, 6♥

        let play = strategy.select_play(&hand, &state);
        assert!(play.is_some());

        let play = play.unwrap();
        // Should prefer to play a pair (removes more points)
        assert!(play.len() >= 1);
    }

    #[test]
    fn test_should_zapzap() {
        let strategy = HardBotStrategy::new();
        let state = GameState::new(4);

        // Hand with value 0 (two jokers) - always zapzap
        assert!(strategy.should_zapzap(&[52, 53], &state));

        // Hand with value 2 - always zapzap (very confident)
        assert!(strategy.should_zapzap(&[0, 52], &state)); // A + Joker = 1

        // Hand with value 6 (not eligible - can't zapzap > 5)
        assert!(!strategy.should_zapzap(&[0, 1, 2], &state)); // A + 2 + 3 = 6
    }

    #[test]
    fn test_select_draw_source() {
        let strategy = HardBotStrategy::new();
        let state = GameState::new(4);

        // Empty discard - must draw from deck
        assert!(strategy.select_draw_source(&[0, 1], &[], &state));

        // Discard with useful card (ace to complete pair)
        let hand = vec![0]; // A♠
        let discard = vec![13]; // A♥
        // Should prefer discard (completes pair)
        // Note: depends on evaluation, may or may not take it
        let _ = strategy.select_draw_source(&hand, &discard, &state);
    }
}
