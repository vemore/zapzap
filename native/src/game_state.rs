//! GameState - Compact game state representation for fast simulation
//!
//! Optimized for cache-friendly memory layout and fast cloning.

use smallvec::SmallVec;

/// Maximum players supported
pub const MAX_PLAYERS: usize = 8;
/// Maximum hand size
pub const MAX_HAND_SIZE: usize = 10;

/// Current game action
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GameAction {
    SelectHandSize,
    Draw,
    Play,
    ZapZap,
    Finished,
}

impl Default for GameAction {
    fn default() -> Self {
        GameAction::SelectHandSize
    }
}

/// Last action information
#[derive(Debug, Clone, Default)]
pub struct LastAction {
    pub action_type: u8,  // 0=none, 1=draw, 2=play, 3=zapzap
    pub player_index: u8,
    pub was_counteracted: bool,
    pub caller_hand_points: u8,
}

/// Compact game state for simulation
#[derive(Debug, Clone)]
pub struct GameState {
    // Deck (cards remaining to draw) - use Vec for large collections
    pub deck: Vec<u8>,

    // Player hands - array of hands, each hand is a SmallVec
    pub hands: [SmallVec<[u8; MAX_HAND_SIZE]>; MAX_PLAYERS],

    // Last cards played (visible discard)
    pub last_cards_played: SmallVec<[u8; 8]>,

    // Current turn's played cards
    pub cards_played: SmallVec<[u8; 8]>,

    // Full discard pile (for reshuffling) - use Vec for large collections
    pub discard_pile: Vec<u8>,

    // Player scores
    pub scores: [u16; MAX_PLAYERS],

    // Current turn (player index)
    pub current_turn: u8,

    // Current action
    pub current_action: GameAction,

    // Round number
    pub round_number: u16,

    // Number of players
    pub player_count: u8,

    // Golden score mode
    pub is_golden_score: bool,

    // Eliminated players bitmask (bit i = player i eliminated)
    pub eliminated_mask: u8,

    // Last action info
    pub last_action: LastAction,
}

impl Default for GameState {
    fn default() -> Self {
        Self::new(4)
    }
}

impl GameState {
    /// Create a new game state with given player count
    pub fn new(player_count: u8) -> Self {
        GameState {
            deck: Vec::with_capacity(54),
            hands: Default::default(),
            last_cards_played: SmallVec::new(),
            cards_played: SmallVec::new(),
            discard_pile: Vec::with_capacity(54),
            scores: [0; MAX_PLAYERS],
            current_turn: 0,
            current_action: GameAction::SelectHandSize,
            round_number: 1,
            player_count,
            is_golden_score: false,
            eliminated_mask: 0,
            last_action: LastAction::default(),
        }
    }

    /// Check if player is eliminated
    #[inline]
    pub fn is_eliminated(&self, player_index: u8) -> bool {
        (self.eliminated_mask & (1 << player_index)) != 0
    }

    /// Mark player as eliminated
    #[inline]
    pub fn eliminate_player(&mut self, player_index: u8) {
        self.eliminated_mask |= 1 << player_index;
    }

    /// Get active (non-eliminated) players
    pub fn active_players(&self) -> SmallVec<[u8; MAX_PLAYERS]> {
        let mut active = SmallVec::new();
        for i in 0..self.player_count {
            if !self.is_eliminated(i) {
                active.push(i);
            }
        }
        active
    }

    /// Get number of active players
    pub fn active_player_count(&self) -> u8 {
        let mut count = 0;
        for i in 0..self.player_count {
            if !self.is_eliminated(i) {
                count += 1;
            }
        }
        count
    }

    /// Get player's hand
    #[inline]
    pub fn get_hand(&self, player_index: u8) -> &SmallVec<[u8; MAX_HAND_SIZE]> {
        &self.hands[player_index as usize]
    }

    /// Get mutable player's hand
    #[inline]
    pub fn get_hand_mut(&mut self, player_index: u8) -> &mut SmallVec<[u8; MAX_HAND_SIZE]> {
        &mut self.hands[player_index as usize]
    }

    /// Get player's score
    #[inline]
    pub fn get_score(&self, player_index: u8) -> u16 {
        self.scores[player_index as usize]
    }

    /// Set player's score
    #[inline]
    pub fn set_score(&mut self, player_index: u8, score: u16) {
        self.scores[player_index as usize] = score;
    }

    /// Add to player's score
    #[inline]
    pub fn add_score(&mut self, player_index: u8, points: u16) {
        self.scores[player_index as usize] += points;
    }

    /// Get deck size
    #[inline]
    pub fn deck_size(&self) -> usize {
        self.deck.len()
    }

    /// Draw card from deck
    #[inline]
    pub fn draw_from_deck(&mut self) -> Option<u8> {
        self.deck.pop()
    }

    /// Draw card from last played
    #[inline]
    pub fn draw_from_played(&mut self) -> Option<u8> {
        self.last_cards_played.pop()
    }

    /// Advance to next active player
    pub fn advance_turn(&mut self) {
        let mut next = (self.current_turn + 1) % self.player_count;
        let mut attempts = 0;
        while self.is_eliminated(next) && attempts < self.player_count {
            next = (next + 1) % self.player_count;
            attempts += 1;
        }
        self.current_turn = next;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_game_state() {
        let state = GameState::new(4);
        assert_eq!(state.player_count, 4);
        assert_eq!(state.current_turn, 0);
        assert_eq!(state.round_number, 1);
        assert!(!state.is_golden_score);
    }

    #[test]
    fn test_elimination() {
        let mut state = GameState::new(4);
        assert!(!state.is_eliminated(0));
        assert!(!state.is_eliminated(1));

        state.eliminate_player(1);
        assert!(!state.is_eliminated(0));
        assert!(state.is_eliminated(1));

        let active = state.active_players();
        assert_eq!(active.len(), 3);
        assert!(!active.contains(&1));
    }

    #[test]
    fn test_advance_turn() {
        let mut state = GameState::new(4);
        state.eliminate_player(1);

        state.current_turn = 0;
        state.advance_turn();
        assert_eq!(state.current_turn, 2); // Skips player 1

        state.advance_turn();
        assert_eq!(state.current_turn, 3);

        state.advance_turn();
        assert_eq!(state.current_turn, 0); // Wraps around, skipping 1
    }
}
