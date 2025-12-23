//! GameState - Compact game state representation for fast simulation
//!
//! Optimized for cache-friendly memory layout and fast cloning.

use serde::{Deserialize, Serialize};
use smallvec::SmallVec;

/// Maximum players supported
pub const MAX_PLAYERS: usize = 8;
/// Maximum hand size
pub const MAX_HAND_SIZE: usize = 10;

/// Current game action
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
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

impl GameAction {
    pub fn as_str(&self) -> &'static str {
        match self {
            GameAction::SelectHandSize => "selectHandSize",
            GameAction::Draw => "draw",
            GameAction::Play => "play",
            GameAction::ZapZap => "zapzap",
            GameAction::Finished => "finished",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "selectHandSize" => Some(GameAction::SelectHandSize),
            "draw" => Some(GameAction::Draw),
            "play" => Some(GameAction::Play),
            "zapzap" => Some(GameAction::ZapZap),
            "finished" => Some(GameAction::Finished),
            _ => None,
        }
    }
}

/// Last action information
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LastAction {
    pub action_type: u8, // 0=none, 1=draw, 2=play, 3=zapzap
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

    // Starting player for this round (for rotation)
    pub starting_player: u8,

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

    // Round end data (populated when round finishes)
    pub round_scores: Option<[u16; MAX_PLAYERS]>,
    pub zapzap_caller: Option<u8>,
    pub lowest_hand_player_index: Option<u8>,
    pub was_counter_acted: Option<bool>,
    pub counter_acted_by_player_index: Option<u8>,
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
            starting_player: 0,
            current_action: GameAction::SelectHandSize,
            round_number: 1,
            player_count,
            is_golden_score: false,
            eliminated_mask: 0,
            last_action: LastAction::default(),
            card_tracker: CardTracker::default(),
            round_scores: None,
            zapzap_caller: None,
            lowest_hand_player_index: None,
            was_counter_acted: None,
            counter_acted_by_player_index: None,
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
    pub fn estimate_min_hand_value(&self, player_index: u8) -> u16 {
        let hand_size = self.hands[player_index as usize].len() as u8;
        let known_cards = self.get_player_known_cards(player_index);
        let tracked_count = self.card_tracker.taken_count[player_index as usize];

        // If we know ALL cards in their hand, calculate exact value
        if tracked_count >= hand_size && !known_cards.is_empty() {
            let mut values: SmallVec<[u8; 10]> = known_cards
                .iter()
                .map(|&c| if c >= 52 { 0 } else { (c % 13) + 1 })
                .collect();
            values.sort_unstable();

            return values
                .iter()
                .take(hand_size as usize)
                .map(|&v| v as u16)
                .sum();
        }

        0
    }

    /// Count how many cards of a specific rank are visible
    pub fn count_visible_rank(&self, rank: u8) -> u8 {
        let mut count = 0u8;

        for &card in &self.discard_pile {
            if card >= 52 {
                if rank == 13 {
                    count += 1;
                }
            } else if card % 13 == rank {
                count += 1;
            }
        }

        for &card in &self.last_cards_played {
            if card >= 52 {
                if rank == 13 {
                    count += 1;
                }
            } else if card % 13 == rank {
                count += 1;
            }
        }

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
    pub fn count_drawable_rank(&self, rank: u8) -> u8 {
        let visible = self.count_visible_rank(rank);
        let max_cards: u8 = if rank == 13 { 2 } else { 4 };
        max_cards.saturating_sub(visible)
    }

    /// Get probability of drawing a specific rank from deck
    pub fn draw_probability(&self, rank: u8) -> f32 {
        let drawable = self.count_drawable_rank(rank) as f32;
        let deck_size = self.deck.len() as f32;
        if deck_size == 0.0 {
            return 0.0;
        }
        drawable / deck_size
    }

    /// Check if a rank is "dead" (all 4 cards visible)
    pub fn is_rank_dead(&self, rank: u8) -> bool {
        self.count_drawable_rank(rank) == 0
    }

    /// Find the rank with highest draw probability among given ranks
    pub fn best_drawable_rank(&self, ranks: &[u8]) -> Option<u8> {
        ranks.iter().copied().max_by(|&a, &b| {
            let prob_a = self.draw_probability(a);
            let prob_b = self.draw_probability(b);
            prob_a
                .partial_cmp(&prob_b)
                .unwrap_or(std::cmp::Ordering::Equal)
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

    /// Get last action as JSON value (for API response)
    pub fn get_last_action_json(&self) -> Option<serde_json::Value> {
        if self.last_action.action_type == 0 {
            return None;
        }
        let action_type_str = match self.last_action.action_type {
            1 => "draw",
            2 => "play",
            3 => "zapzap",
            _ => "unknown",
        };
        Some(serde_json::json!({
            "type": action_type_str,
            "playerIndex": self.last_action.player_index,
            "wasCounterActed": self.last_action.was_counteracted,
            "callerHandPoints": self.last_action.caller_hand_points
        }))
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

    /// Serialize to JSON string (compatible with JS format)
    pub fn to_json(&self) -> String {
        use serde_json::json;
        use std::collections::HashMap;

        // Convert hands to object with string keys
        let mut hands_map: HashMap<String, Vec<u8>> = HashMap::new();
        for i in 0..self.player_count as usize {
            hands_map.insert(i.to_string(), self.hands[i].to_vec());
        }

        // Convert scores to object with string keys
        let mut scores_map: HashMap<String, u16> = HashMap::new();
        for i in 0..self.player_count as usize {
            scores_map.insert(i.to_string(), self.scores[i]);
        }

        // Convert lastAction to JSON format if present
        let last_action_json = if self.last_action.action_type != 0 {
            let action_type_str = match self.last_action.action_type {
                1 => "draw",
                2 => "play",
                3 => "zapzap",
                _ => "unknown",
            };
            Some(json!({
                "type": action_type_str,
                "playerIndex": self.last_action.player_index,
                "wasCounterActed": self.last_action.was_counteracted,
                "callerHandPoints": self.last_action.caller_hand_points
            }))
        } else {
            None
        };

        // Convert round_scores to object if present
        let round_scores_map: Option<HashMap<String, u16>> = self.round_scores.map(|scores| {
            let mut map = HashMap::new();
            for i in 0..self.player_count as usize {
                map.insert(i.to_string(), scores[i]);
            }
            map
        });

        let json_value = json!({
            "deck": self.deck,
            "hands": hands_map,
            "lastCardsPlayed": self.last_cards_played.to_vec(),
            "cardsPlayed": self.cards_played.to_vec(),
            "discardPile": self.discard_pile,
            "scores": scores_map,
            "currentTurn": self.current_turn,
            "startingPlayer": self.starting_player,
            "currentAction": self.current_action.as_str(),
            "roundNumber": self.round_number,
            "playerCount": self.player_count,
            "isGoldenScore": self.is_golden_score,
            "eliminatedMask": self.eliminated_mask,
            "lastAction": last_action_json,
            "roundScores": round_scores_map,
            "zapZapCaller": self.zapzap_caller,
            "lowestHandPlayerIndex": self.lowest_hand_player_index,
            "wasCounterActed": self.was_counter_acted,
            "counterActedByPlayerIndex": self.counter_acted_by_player_index
        });

        json_value.to_string()
    }

    /// Deserialize from JSON string (compatible with JS format)
    pub fn from_json(json_str: &str) -> Result<Self, String> {
        use serde_json::Value;

        let v: Value = serde_json::from_str(json_str)
            .map_err(|e| format!("JSON parse error: {}", e))?;

        let deck: Vec<u8> = v["deck"]
            .as_array()
            .ok_or("Missing deck")?
            .iter()
            .filter_map(|x| x.as_u64().map(|n| n as u8))
            .collect();

        let player_count = v["playerCount"]
            .as_u64()
            .or_else(|| {
                // Fallback: count hands
                v["hands"].as_object().map(|h| h.len() as u64)
            })
            .unwrap_or(4) as u8;

        let mut hands: [SmallVec<[u8; MAX_HAND_SIZE]>; MAX_PLAYERS] = Default::default();
        if let Some(hands_obj) = v["hands"].as_object() {
            for (key, val) in hands_obj {
                if let Ok(idx) = key.parse::<usize>() {
                    if idx < MAX_PLAYERS {
                        if let Some(arr) = val.as_array() {
                            hands[idx] = arr
                                .iter()
                                .filter_map(|x| x.as_u64().map(|n| n as u8))
                                .collect();
                        }
                    }
                }
            }
        }

        let last_cards_played: SmallVec<[u8; 8]> = v["lastCardsPlayed"]
            .as_array()
            .map(|arr| arr.iter().filter_map(|x| x.as_u64().map(|n| n as u8)).collect())
            .unwrap_or_default();

        let cards_played: SmallVec<[u8; 8]> = v["cardsPlayed"]
            .as_array()
            .map(|arr| arr.iter().filter_map(|x| x.as_u64().map(|n| n as u8)).collect())
            .unwrap_or_default();

        let discard_pile: Vec<u8> = v["discardPile"]
            .as_array()
            .map(|arr| arr.iter().filter_map(|x| x.as_u64().map(|n| n as u8)).collect())
            .unwrap_or_default();

        let mut scores: [u16; MAX_PLAYERS] = [0; MAX_PLAYERS];
        if let Some(scores_obj) = v["scores"].as_object() {
            for (key, val) in scores_obj {
                if let Ok(idx) = key.parse::<usize>() {
                    if idx < MAX_PLAYERS {
                        scores[idx] = val.as_u64().unwrap_or(0) as u16;
                    }
                }
            }
        }

        let current_turn = v["currentTurn"].as_u64().unwrap_or(0) as u8;
        let starting_player = v["startingPlayer"].as_u64().unwrap_or(0) as u8;
        let current_action = v["currentAction"]
            .as_str()
            .and_then(GameAction::from_str)
            .unwrap_or(GameAction::SelectHandSize);
        let round_number = v["roundNumber"].as_u64().unwrap_or(1) as u16;
        let is_golden_score = v["isGoldenScore"].as_bool().unwrap_or(false);
        let eliminated_mask = v["eliminatedMask"].as_u64().unwrap_or(0) as u8;

        // Parse lastAction
        let last_action = if let Some(la) = v["lastAction"].as_object() {
            let action_type = match la.get("type").and_then(|t| t.as_str()) {
                Some("draw") => 1,
                Some("play") => 2,
                Some("zapzap") => 3,
                _ => 0,
            };
            LastAction {
                action_type,
                player_index: la.get("playerIndex").and_then(|p| p.as_u64()).unwrap_or(0) as u8,
                was_counteracted: la.get("wasCounterActed").and_then(|w| w.as_bool()).unwrap_or(false),
                caller_hand_points: la.get("callerHandPoints").and_then(|c| c.as_u64()).unwrap_or(0) as u8,
            }
        } else {
            LastAction::default()
        };

        // Parse round end data if present
        let round_scores = v.get("roundScores").and_then(|rs| {
            let obj = rs.as_object()?;
            let mut scores_arr = [0u16; MAX_PLAYERS];
            for (key, val) in obj {
                if let (Ok(idx), Some(score)) = (key.parse::<usize>(), val.as_u64()) {
                    if idx < MAX_PLAYERS {
                        scores_arr[idx] = score as u16;
                    }
                }
            }
            Some(scores_arr)
        });
        let zapzap_caller = v.get("zapZapCaller").and_then(|c| c.as_u64()).map(|c| c as u8);
        let lowest_hand_player_index = v.get("lowestHandPlayerIndex").and_then(|l| l.as_u64()).map(|l| l as u8);
        let was_counter_acted = v.get("wasCounterActed").and_then(|w| w.as_bool());
        let counter_acted_by_player_index = v.get("counterActedByPlayerIndex").and_then(|c| c.as_u64()).map(|c| c as u8);

        Ok(GameState {
            deck,
            hands,
            last_cards_played,
            cards_played,
            discard_pile,
            scores,
            current_turn,
            starting_player,
            current_action,
            round_number,
            player_count,
            is_golden_score,
            eliminated_mask,
            last_action,
            card_tracker: CardTracker::default(),
            round_scores,
            zapzap_caller,
            lowest_hand_player_index,
            was_counter_acted,
            counter_acted_by_player_index,
        })
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
