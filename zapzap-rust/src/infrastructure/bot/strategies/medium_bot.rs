//! Medium bot strategy
//!
//! Balanced bot with some strategic awareness but not optimal play.

use rand::seq::SliceRandom;
use rand::Rng;

use super::{BotAction, BotStrategy, DrawSource};
use crate::domain::value_objects::GameState;
use crate::infrastructure::bot::card_analyzer::{
    can_call_zapzap, calculate_hand_value, find_all_valid_plays, get_card_points,
    would_complete_pair,
};

/// Medium difficulty bot strategy
/// Has some strategic awareness but makes suboptimal plays sometimes
pub struct MediumBotStrategy;

impl MediumBotStrategy {
    pub fn new() -> Self {
        Self
    }
}

impl Default for MediumBotStrategy {
    fn default() -> Self {
        Self::new()
    }
}

impl BotStrategy for MediumBotStrategy {
    fn select_hand_size(&self, state: &GameState, _player_index: u8) -> u8 {
        // Medium bot chooses based on game situation
        if state.is_golden_score {
            4 // Smaller hand in golden score
        } else {
            // Random 4 or 5
            let mut rng = rand::thread_rng();
            rng.gen_range(4..=5)
        }
    }

    fn decide_action(&self, state: &GameState, player_index: u8) -> BotAction {
        let hand = state.get_hand(player_index);

        if can_call_zapzap(hand) {
            let hand_value = calculate_hand_value(hand);

            // Call with low hand
            if hand_value <= 3 {
                return BotAction::ZapZap;
            }

            // Call with one card
            if hand.len() == 1 {
                return BotAction::ZapZap;
            }

            // 50% chance to call with hand value 4-5
            if hand_value <= 5 {
                let mut rng = rand::thread_rng();
                if rng.gen_bool(0.5) {
                    return BotAction::ZapZap;
                }
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

        let mut rng = rand::thread_rng();

        // 70% chance to make a strategic choice, 30% random
        if rng.gen_bool(0.7) {
            // Find play that removes most points
            let best_play = plays
                .into_iter()
                .max_by_key(|play| {
                    let points_removed: u32 = play.iter().map(|&c| get_card_points(c) as u32).sum();
                    points_removed
                })
                .unwrap_or_default();

            best_play.into_iter().collect()
        } else {
            // Random play
            let play = plays.choose(&mut rng).cloned().unwrap_or_default();
            play.into_iter().collect()
        }
    }

    fn decide_draw_source(&self, state: &GameState, player_index: u8) -> DrawSource {
        let hand = state.get_hand(player_index);
        let mut rng = rand::thread_rng();

        // Check discard pile for useful cards
        for &card in &state.last_cards_played {
            // Would it complete a pair? (medium bot understands pairs)
            if would_complete_pair(hand, card) {
                return DrawSource::Discard(card);
            }

            // Is it a very low value card?
            if get_card_points(card) <= 2 {
                // 80% chance to take low value card
                if rng.gen_bool(0.8) {
                    return DrawSource::Discard(card);
                }
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

        // Call with low hand
        if hand_value <= 3 {
            return true;
        }

        // Call with one card
        if hand.len() == 1 {
            return true;
        }

        // More aggressive in golden score
        if state.is_golden_score && hand_value <= 4 {
            return true;
        }

        false
    }
}
