//! Bot strategies module

mod hard_bot;

pub use hard_bot::HardBotStrategy;

use crate::game_state::GameState;
use smallvec::SmallVec;

/// Bot strategy trait
pub trait BotStrategy {
    /// Select cards to play from hand
    fn select_play(&self, hand: &[u8], state: &GameState) -> Option<SmallVec<[u8; 8]>>;

    /// Decide whether to call ZapZap
    fn should_zapzap(&self, hand: &[u8], state: &GameState) -> bool;

    /// Select draw source: true = deck, false = played cards
    fn select_draw_source(&self, hand: &[u8], last_cards_played: &[u8], state: &GameState) -> bool;

    /// Select hand size for round
    fn select_hand_size(&self, active_player_count: u8, is_golden_score: bool) -> u8;
}

/// Random bot strategy (baseline)
pub struct RandomBotStrategy;

impl BotStrategy for RandomBotStrategy {
    fn select_play(&self, hand: &[u8], _state: &GameState) -> Option<SmallVec<[u8; 8]>> {
        if hand.is_empty() {
            return None;
        }
        // Just play the first card
        let mut play = SmallVec::new();
        play.push(hand[0]);
        Some(play)
    }

    fn should_zapzap(&self, hand: &[u8], _state: &GameState) -> bool {
        crate::card_analyzer::can_call_zapzap(hand)
    }

    fn select_draw_source(&self, _hand: &[u8], _last_cards_played: &[u8], _state: &GameState) -> bool {
        true // Always deck
    }

    fn select_hand_size(&self, _active_player_count: u8, is_golden_score: bool) -> u8 {
        if is_golden_score { 5 } else { 5 }
    }
}
