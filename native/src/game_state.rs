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

/// Card tracking for opponent hand prediction
/// Tracks cards seen taken from played pile by each player
#[derive(Debug, Clone, Default)]
pub struct CardTracker {
    /// Cards taken from played pile by each player (not yet played back)
    /// Index = player, value = bitmask of card IDs (limited to 64 cards)
    pub taken_cards: [u64; MAX_PLAYERS],
    /// Total cards tracked per player
    pub taken_count: [u8; MAX_PLAYERS],
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

    // Card tracking for opponent prediction
    pub card_tracker: CardTracker,
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
            card_tracker: CardTracker::default(),
        }
    }

    /// Track a card taken from played pile by a player
    pub fn track_card_taken(&mut self, player_index: u8, card_id: u8) {
        if card_id < 64 {
            self.card_tracker.taken_cards[player_index as usize] |= 1u64 << card_id;
            self.card_tracker.taken_count[player_index as usize] += 1;
        }
    }

    /// Track cards played by a player (remove from tracking)
    pub fn track_cards_played(&mut self, player_index: u8, cards: &[u8]) {
        for &card_id in cards {
            if card_id < 64 {
                self.card_tracker.taken_cards[player_index as usize] &= !(1u64 << card_id);
                if self.card_tracker.taken_count[player_index as usize] > 0 {
                    self.card_tracker.taken_count[player_index as usize] -= 1;
                }
            }
        }
    }

    /// Check if a player has taken a specific card (and not played it back)
    pub fn has_player_taken(&self, player_index: u8, card_id: u8) -> bool {
        if card_id >= 64 {
            return false;
        }
        (self.card_tracker.taken_cards[player_index as usize] & (1u64 << card_id)) != 0
    }

    /// Get all cards a player has taken but not played
    pub fn get_player_known_cards(&self, player_index: u8) -> SmallVec<[u8; 10]> {
        let mut cards = SmallVec::new();
        let mask = self.card_tracker.taken_cards[player_index as usize];
        for card_id in 0..54u8 {
            if (mask & (1u64 << card_id)) != 0 {
                cards.push(card_id);
            }
        }
        cards
    }

    /// Estimate minimum possible hand value for a player based on tracked cards
    /// If they took 2 aces and never played them, and have 2 cards, we know those are the aces
    pub fn estimate_min_hand_value(&self, player_index: u8) -> u16 {
        let hand_size = self.hands[player_index as usize].len() as u8;
        let known_cards = self.get_player_known_cards(player_index);
        let tracked_count = self.card_tracker.taken_count[player_index as usize];

        // If we know ALL cards in their hand, calculate exact value
        if tracked_count >= hand_size && !known_cards.is_empty() {
            // Take the lowest N cards from known cards
            let mut values: SmallVec<[u8; 10]> = known_cards.iter()
                .map(|&c| if c >= 52 { 0 } else { (c % 13) + 1 })
                .collect();
            values.sort_unstable();

            return values.iter()
                .take(hand_size as usize)
                .map(|&v| v as u16)
                .sum();
        }

        // Minimum possible if we only know some cards
        // They could have drawn jokers from deck, so min is 0
        0
    }

    // ========================================
    // CARD COUNTING - Track visible cards in discard
    // ========================================

    /// Count how many cards of a specific rank are visible (in discard pile + last_cards_played)
    /// Rank: 0-12 (A=0, 2=1, ..., K=12)
    /// Returns count (0-4 for normal cards, 0-2 for jokers)
    pub fn count_visible_rank(&self, rank: u8) -> u8 {
        let mut count = 0u8;

        // Count in discard pile
        for &card in &self.discard_pile {
            if card >= 52 {
                // Joker - treat as special rank 13
                if rank == 13 {
                    count += 1;
                }
            } else if card % 13 == rank {
                count += 1;
            }
        }

        // Count in last_cards_played (visible)
        for &card in &self.last_cards_played {
            if card >= 52 {
                if rank == 13 {
                    count += 1;
                }
            } else if card % 13 == rank {
                count += 1;
            }
        }

        // Count in cards_played (current turn, also visible)
        for &card in &self.cards_played {
            if card >= 52 {
                if rank == 13 {
                    count += 1;
                }
            } else if card % 13 == rank {
                count += 1;
            }
        }

        count
    }

    /// Count remaining cards of a rank that could be drawn
    /// If 3 jacks are in discard, only 1 jack can be drawn
    /// max_cards: 4 for normal ranks, 2 for jokers
    pub fn count_drawable_rank(&self, rank: u8) -> u8 {
        let visible = self.count_visible_rank(rank);
        let max_cards: u8 = if rank == 13 { 2 } else { 4 }; // 2 jokers, 4 of each rank
        max_cards.saturating_sub(visible)
    }

    /// Get probability of drawing a specific rank from deck
    /// Returns 0.0 if all cards of that rank are visible
    pub fn draw_probability(&self, rank: u8) -> f32 {
        let drawable = self.count_drawable_rank(rank) as f32;
        let deck_size = self.deck.len() as f32;
        if deck_size == 0.0 {
            return 0.0;
        }
        drawable / deck_size
    }

    /// Check if a rank is "dead" (all 4 cards visible, no pair possible)
    pub fn is_rank_dead(&self, rank: u8) -> bool {
        self.count_drawable_rank(rank) == 0
    }

    /// Find the rank with highest draw probability among given ranks
    /// Useful for deciding which card to keep vs discard
    pub fn best_drawable_rank(&self, ranks: &[u8]) -> Option<u8> {
        ranks.iter()
            .copied()
            .max_by(|&a, &b| {
                let prob_a = self.draw_probability(a);
                let prob_b = self.draw_probability(b);
                prob_a.partial_cmp(&prob_b).unwrap_or(std::cmp::Ordering::Equal)
            })
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
