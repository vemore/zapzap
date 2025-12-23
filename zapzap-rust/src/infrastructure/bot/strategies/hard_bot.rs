//! Hard bot strategy
//!
//! Rule-based bot with intelligent card evaluation.

use super::{BotAction, BotStrategy, DrawSource};
use crate::domain::value_objects::GameState;
use crate::infrastructure::bot::card_analyzer::{
    can_call_zapzap, calculate_hand_value, find_all_valid_plays, get_card_points,
    would_complete_pair, would_complete_sequence,
};

/// Hard difficulty bot strategy
pub struct HardBotStrategy;

impl HardBotStrategy {
    pub fn new() -> Self {
        Self
    }
}

impl Default for HardBotStrategy {
    fn default() -> Self {
        Self::new()
    }
}

impl BotStrategy for HardBotStrategy {
    fn select_hand_size(&self, state: &GameState, _player_index: u8) -> u8 {
        if state.is_golden_score {
            // In golden score, prefer smaller hand for faster play
            4
        } else {
            // Normal play: random 4-5
            use rand::Rng;
            let mut rng = rand::thread_rng();
            rng.gen_range(4..=5)
        }
    }

    fn decide_action(&self, state: &GameState, player_index: u8) -> BotAction {
        let hand = state.get_hand(player_index);

        // Check if we can call ZapZap
        if can_call_zapzap(hand) {
            let hand_value = calculate_hand_value(hand);

            // Always call with very low hand
            if hand_value <= 2 {
                return BotAction::ZapZap;
            }

            // Call if late game and hand is good enough
            if state.round_number > 3 && hand_value <= 4 {
                return BotAction::ZapZap;
            }

            // Call if only one card left
            if hand.len() == 1 {
                return BotAction::ZapZap;
            }
        }

        BotAction::Play
    }

    fn select_cards(&self, state: &GameState, player_index: u8) -> Vec<u8> {
        let hand = state.get_hand(player_index);
        let plays = find_all_valid_plays(hand);

        if plays.is_empty() {
            return Vec::new();
        }

        // Find play that minimizes remaining hand value
        let best_play = plays
            .into_iter()
            .max_by_key(|play| {
                // Score based on points removed and cards removed
                let points_removed: u32 = play.iter().map(|&c| get_card_points(c) as u32).sum();
                let cards_removed = play.len() as u32;

                // Prefer removing high-value cards
                // Bonus for multi-card plays
                points_removed * 2 + cards_removed * 3
            })
            .unwrap_or_default();

        best_play.into_iter().collect()
    }

    fn decide_draw_source(&self, state: &GameState, player_index: u8) -> DrawSource {
        let hand = state.get_hand(player_index);

        // Check if any card in last_cards_played would help
        for &card in &state.last_cards_played {
            // Would it complete a pair?
            if would_complete_pair(hand, card) {
                return DrawSource::Discard(card);
            }

            // Would it complete a sequence?
            if would_complete_sequence(hand, card) {
                return DrawSource::Discard(card);
            }

            // Is it a very low value card?
            if get_card_points(card) <= 2 {
                return DrawSource::Discard(card);
            }
        }

        // Default to deck
        DrawSource::Deck
    }

    fn should_call_zapzap(&self, state: &GameState, player_index: u8) -> bool {
        let hand = state.get_hand(player_index);

        if !can_call_zapzap(hand) {
            return false;
        }

        let hand_value = calculate_hand_value(hand);

        // Always call with very low hand
        if hand_value <= 2 {
            return true;
        }

        // Be more aggressive in golden score
        if state.is_golden_score && hand_value <= 4 {
            return true;
        }

        // Call with one card
        if hand.len() == 1 {
            return true;
        }

        // Otherwise, wait for better opportunity
        false
    }
}
