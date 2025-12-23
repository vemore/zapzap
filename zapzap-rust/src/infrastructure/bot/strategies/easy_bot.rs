//! Easy bot strategy
//!
//! Simple bot that makes random but valid plays.

use rand::seq::SliceRandom;
use rand::Rng;

use super::{BotAction, BotStrategy, DrawSource};
use crate::domain::value_objects::GameState;
use crate::infrastructure::bot::card_analyzer::{
    can_call_zapzap, calculate_hand_value, find_all_valid_plays,
};

/// Easy difficulty bot strategy
/// Makes random valid plays with minimal strategy
pub struct EasyBotStrategy;

impl EasyBotStrategy {
    pub fn new() -> Self {
        Self
    }
}

impl Default for EasyBotStrategy {
    fn default() -> Self {
        Self::new()
    }
}

impl BotStrategy for EasyBotStrategy {
    fn select_hand_size(&self, _state: &GameState, _player_index: u8) -> u8 {
        // Always choose 5 cards (simpler, more cards = more options for beginner bot)
        5
    }

    fn decide_action(&self, state: &GameState, player_index: u8) -> BotAction {
        let hand = state.get_hand(player_index);

        // Only call ZapZap with very low hand (easy bot is not aggressive)
        if can_call_zapzap(hand) {
            let hand_value = calculate_hand_value(hand);

            // Only call with very obvious winning hand
            if hand_value <= 1 || hand.len() == 1 {
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

        // Just pick a random valid play
        let mut rng = rand::thread_rng();
        let play = plays.choose(&mut rng).cloned().unwrap_or_default();

        play.into_iter().collect()
    }

    fn decide_draw_source(&self, state: &GameState, _player_index: u8) -> DrawSource {
        // Easy bot mostly draws from deck (doesn't analyze discard pile)
        // 20% chance to take from discard if available
        let mut rng = rand::thread_rng();

        if !state.last_cards_played.is_empty() && rng.gen_bool(0.2) {
            // Take random card from discard
            if let Some(&card) = state.last_cards_played.choose(&mut rng) {
                return DrawSource::Discard(card);
            }
        }

        DrawSource::Deck
    }

    fn should_call_zapzap(&self, state: &GameState, player_index: u8) -> bool {
        let hand = state.get_hand(player_index);

        if !can_call_zapzap(hand) {
            return false;
        }

        let hand_value = calculate_hand_value(hand);

        // Only call with very low hand
        hand_value <= 1 || hand.len() == 1
    }
}
