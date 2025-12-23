//! Bot strategies module
//!
//! Contains various bot difficulty strategies for the game.

mod easy_bot;
mod hard_bot;
mod llm_bot;
mod medium_bot;
mod thibot;
mod vince_bot;

pub use easy_bot::*;
pub use hard_bot::*;
pub use llm_bot::*;
pub use medium_bot::*;
pub use thibot::*;
pub use vince_bot::*;

use crate::domain::value_objects::GameState;

/// Bot strategy trait
pub trait BotStrategy: Send + Sync {
    /// Select hand size at the start of a round
    fn select_hand_size(&self, state: &GameState, player_index: u8) -> u8;

    /// Decide whether to play cards or draw
    fn decide_action(&self, state: &GameState, player_index: u8) -> BotAction;

    /// Select cards to play
    fn select_cards(&self, state: &GameState, player_index: u8) -> Vec<u8>;

    /// Decide draw source (deck or discard)
    fn decide_draw_source(&self, state: &GameState, player_index: u8) -> DrawSource;

    /// Decide whether to call ZapZap
    fn should_call_zapzap(&self, state: &GameState, player_index: u8) -> bool;
}

/// Bot action decision
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BotAction {
    Play,
    ZapZap,
}

/// Draw source decision
#[derive(Debug, Clone)]
pub enum DrawSource {
    Deck,
    Discard(u8), // Card ID to take from discard
}
