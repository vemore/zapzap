//! GameState - Compact game state representation for fast simulation
//!
//! Optimized for cache-friendly memory layout and fast cloning.

use serde::{Deserialize, Serialize};
use smallvec::SmallVec;

/// Maximum players supported
pub const MAX_PLAYERS: usize = 8;
/// Maximum hand size
pub const MAX_HAND_SIZE: usize = 10;
/// Cards dealt when a round opens, before its starting player picks the hand size and
/// `select_hand_size` re-deals them
pub const PROVISIONAL_HAND_SIZE: u8 = 5;

/// Current game action
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[derive(Default)]
pub enum GameAction {
    #[default]
    SelectHandSize,
    Draw,
    Play,
    ZapZap,
    Finished,
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

/// `lastAction.type` codes of [`LastAction::action_type`]
pub const LAST_ACTION_NONE: u8 = 0;
pub const LAST_ACTION_DRAW: u8 = 1;
pub const LAST_ACTION_PLAY: u8 = 2;
pub const LAST_ACTION_ZAPZAP: u8 = 3;
pub const LAST_ACTION_SELECT_HAND_SIZE: u8 = 4;

/// The last move of the round, the `lastAction` the Node backend wrote
/// (select hand size, play, draw, zapzap).
/// Which fields mean something depends on [`Self::action_type`]; the zapzap's
/// `roundScores` and `counterActedByPlayerIndex` live on [`GameState`].
#[derive(Debug, Clone, Default)]
pub struct LastAction {
    /// One of the `LAST_ACTION_*` codes
    pub action_type: u8,
    pub player_index: u8,
    /// zapzap
    pub was_counteracted: bool,
    /// zapzap: the caller's hand value (Joker = 0)
    pub caller_hand_points: u8,
    /// selectHandSize
    pub hand_size: u8,
    /// play: the cards played
    pub card_ids: SmallVec<[u8; 8]>,
    /// draw: from the played pile, else from the deck (also when a state written before
    /// the source was kept does not say: then no card is named)
    pub from_played: bool,
    /// draw from the played pile: the card taken, which every player saw on the table.
    /// A card drawn from the deck is never kept: naming it would show it to everyone
    /// (Node's `cardId` leak, `2026-09-22-node-play-draw-leak-all-hands`)
    pub card_id: Option<u8>,
    /// draw: the discard pile was shuffled into the empty deck
    pub deck_reshuffled: bool,
    /// Unix milliseconds of the move, 0 when unknown (selectHandSize has none on Node)
    pub timestamp: u64,
}

impl LastAction {
    fn type_str(&self) -> &'static str {
        match self.action_type {
            LAST_ACTION_DRAW => "draw",
            LAST_ACTION_PLAY => "play",
            LAST_ACTION_ZAPZAP => "zapzap",
            LAST_ACTION_SELECT_HAND_SIZE => "selectHandSize",
            _ => "unknown",
        }
    }
}

/// Now, in Unix milliseconds (Node's `Date.now()`)
pub fn now_millis() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
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

/// The seat holding the lowest hand of a finished round, as `execute_zapzap` decides it
/// (`zapzap-rust/src/domain/services/game_service.rs`): from the caller's value, the last
/// other seat, in seat order, whose hand is as low or lower; the caller when none is.
/// Seats without cards (eliminated before the round) take no part. `None` when no seat
/// holds a card.
fn lowest_hand_of(
    hands: &[SmallVec<[u8; MAX_HAND_SIZE]>; MAX_PLAYERS],
    player_count: u8,
    caller: Option<u8>,
) -> Option<u8> {
    use crate::infrastructure::bot::card_analyzer::calculate_hand_value;
    let seats = (0..player_count.min(MAX_PLAYERS as u8)).filter(|&i| !hands[i as usize].is_empty());
    let mut lowest: Option<(u8, u16)> = caller
        .filter(|&c| (c as usize) < MAX_PLAYERS && !hands[c as usize].is_empty())
        .map(|c| (c, calculate_hand_value(&hands[c as usize])));
    for seat in seats.filter(|&i| Some(i) != caller) {
        let value = calculate_hand_value(&hands[seat as usize]);
        match lowest {
            // Without a caller the first lowest seat holds it; after one, ties go on
            Some((_, low)) if value > low || (caller.is_none() && value == low) => {}
            _ => lowest = Some((seat, value)),
        }
    }
    lowest.map(|(seat, _)| seat)
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

    /// `lastAction` as Node's use cases write it, per action type: `{type, playerIndex}`
    /// plus `handSize` (selectHandSize), `cardIds` (play), `source`, `cardId` (played pile
    /// only), `deckReshuffled` (draw), `wasCounterActed`, `counterActedByPlayerIndex`,
    /// `callerHandPoints`, `roundScores` (zapzap), and `timestamp` but on selectHandSize.
    /// `None` before the round's first move. Both the API response and the stored state.
    pub fn get_last_action_json(&self) -> Option<serde_json::Value> {
        use serde_json::{json, Value};
        let la = &self.last_action;
        if la.action_type == LAST_ACTION_NONE {
            return None;
        }
        let mut obj = serde_json::Map::new();
        obj.insert("type".into(), json!(la.type_str()));
        obj.insert("playerIndex".into(), json!(la.player_index));
        match la.action_type {
            LAST_ACTION_SELECT_HAND_SIZE => {
                obj.insert("handSize".into(), json!(la.hand_size));
            }
            LAST_ACTION_PLAY => {
                obj.insert("cardIds".into(), json!(la.card_ids.to_vec()));
            }
            LAST_ACTION_DRAW => {
                let source = if la.from_played { "played" } else { "deck" };
                obj.insert("source".into(), json!(source));
                if la.from_played {
                    if let Some(card) = la.card_id {
                        obj.insert("cardId".into(), json!(card));
                    }
                }
                obj.insert("deckReshuffled".into(), json!(la.deck_reshuffled));
            }
            LAST_ACTION_ZAPZAP => {
                obj.insert("wasCounterActed".into(), json!(la.was_counteracted));
                obj.insert(
                    "counterActedByPlayerIndex".into(),
                    json!(self.counter_acted_by_player_index),
                );
                obj.insert("callerHandPoints".into(), json!(la.caller_hand_points));
                let round_scores = self.round_scores.map(|scores| {
                    scores
                        .iter()
                        .take(self.player_count as usize)
                        .enumerate()
                        .map(|(i, s)| (i.to_string(), json!(s)))
                        .collect::<serde_json::Map<String, Value>>()
                });
                obj.insert("roundScores".into(), json!(round_scores));
            }
            _ => {}
        }
        if la.timestamp != 0 {
            obj.insert("timestamp".into(), json!(la.timestamp));
        }
        Some(Value::Object(obj))
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

        let last_action_json = self.get_last_action_json();

        // Convert round_scores to object if present
        let round_scores_map: Option<HashMap<String, u16>> = self.round_scores.map(|scores| {
            let mut map = HashMap::new();
            for (i, score) in scores.iter().take(self.player_count as usize).enumerate() {
                map.insert(i.to_string(), *score);
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
            "eliminatedPlayers": (0..self.player_count)
                .filter(|&i| self.is_eliminated(i))
                .collect::<Vec<u8>>(),
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

        let v: Value =
            serde_json::from_str(json_str).map_err(|e| format!("JSON parse error: {}", e))?;

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
            .map(|arr| {
                arr.iter()
                    .filter_map(|x| x.as_u64().map(|n| n as u8))
                    .collect()
            })
            .unwrap_or_default();

        let cards_played: SmallVec<[u8; 8]> = v["cardsPlayed"]
            .as_array()
            .map(|arr| {
                arr.iter()
                    .filter_map(|x| x.as_u64().map(|n| n as u8))
                    .collect()
            })
            .unwrap_or_default();

        let discard_pile: Vec<u8> = v["discardPile"]
            .as_array()
            .map(|arr| {
                arr.iter()
                    .filter_map(|x| x.as_u64().map(|n| n as u8))
                    .collect()
            })
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
        // Node stores `eliminatedPlayers: [index…]` and no mask
        let eliminated_mask = match v["eliminatedMask"].as_u64() {
            Some(mask) => mask as u8,
            None => v["eliminatedPlayers"]
                .as_array()
                .map(|seats| {
                    seats
                        .iter()
                        .filter_map(|x| x.as_u64())
                        .filter(|&i| (i as usize) < MAX_PLAYERS)
                        .fold(0u8, |mask, i| mask | (1 << i))
                })
                .unwrap_or(0),
        };

        // Parse lastAction: Node's format, which this one follows, and the older Rust one
        // `{type, playerIndex, wasCounterActed, callerHandPoints}`
        let la_obj = v["lastAction"].as_object();
        let last_action = if let Some(la) = la_obj {
            let action_type = match la.get("type").and_then(|t| t.as_str()) {
                Some("draw") => LAST_ACTION_DRAW,
                Some("play") => LAST_ACTION_PLAY,
                Some("zapzap") => LAST_ACTION_ZAPZAP,
                Some("selectHandSize") => LAST_ACTION_SELECT_HAND_SIZE,
                _ => LAST_ACTION_NONE,
            };
            let u8_of = |key: &str| la.get(key).and_then(|x| x.as_u64()).map(|n| n as u8);
            let from_played = la.get("source").and_then(|s| s.as_str()) == Some("played");
            LastAction {
                action_type,
                player_index: u8_of("playerIndex").unwrap_or(0),
                was_counteracted: la
                    .get("wasCounterActed")
                    .and_then(|w| w.as_bool())
                    .unwrap_or(false),
                caller_hand_points: u8_of("callerHandPoints").unwrap_or(0),
                hand_size: u8_of("handSize").unwrap_or(0),
                card_ids: la
                    .get("cardIds")
                    .and_then(|c| c.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|x| x.as_u64().map(|n| n as u8))
                            .collect()
                    })
                    .unwrap_or_default(),
                from_played,
                // Node also names the card drawn from the deck: dropped, never shown
                card_id: if from_played { u8_of("cardId") } else { None },
                deck_reshuffled: la
                    .get("deckReshuffled")
                    .and_then(|d| d.as_bool())
                    .unwrap_or(false),
                timestamp: la.get("timestamp").and_then(|t| t.as_u64()).unwrap_or(0),
            }
        } else {
            LastAction::default()
        };
        // Node keeps the zapzap's outcome in lastAction only; Rust also at the top level
        let zapzap_la = la_obj.filter(|_| last_action.action_type == LAST_ACTION_ZAPZAP);
        let top_or_zapzap = |key: &str| -> Option<&Value> {
            v.get(key).filter(|x| !x.is_null()).or_else(|| {
                zapzap_la
                    .and_then(|la| la.get(key))
                    .filter(|x| !x.is_null())
            })
        };

        // Parse round end data if present
        let round_scores = top_or_zapzap("roundScores").and_then(|rs| {
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
        let zapzap_caller = v
            .get("zapZapCaller")
            .and_then(|c| c.as_u64())
            .map(|c| c as u8)
            .or_else(|| zapzap_la.map(|_| last_action.player_index));
        let lowest_hand_player_index = v
            .get("lowestHandPlayerIndex")
            .and_then(|l| l.as_u64())
            .map(|l| l as u8)
            .or_else(|| {
                (current_action == GameAction::Finished)
                    .then(|| lowest_hand_of(&hands, player_count, zapzap_caller))
                    .flatten()
            });
        let was_counter_acted = top_or_zapzap("wasCounterActed").and_then(|w| w.as_bool());
        let counter_acted_by_player_index = top_or_zapzap("counterActedByPlayerIndex")
            .and_then(|c| c.as_u64())
            .map(|c| c as u8);

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

    /// A game state as the Node backend's `GameState.toJSON()` stored it, with `lastAction`
    /// as its draw wrote it
    fn node_state(last_action: serde_json::Value) -> String {
        serde_json::json!({
            "deck": [5, 6, 7],
            "hands": {"0": [0, 1], "1": [13, 14], "2": [26, 27]},
            "lastCardsPlayed": [40],
            "cardsPlayed": [41],
            "discardPile": [],
            "scores": {"0": 10, "1": 20, "2": 30},
            "currentTurn": 1,
            "currentAction": "play",
            "roundNumber": 3,
            "lastAction": last_action,
            "isGoldenScore": false,
            "eliminatedPlayers": [],
            "startingPlayer": 0
        })
        .to_string()
    }

    #[test]
    fn test_node_deck_draw_reads_without_the_card() {
        let json = node_state(serde_json::json!({
            "type": "draw", "playerIndex": 0, "source": "deck", "cardId": 52,
            "deckReshuffled": true, "timestamp": 1_758_000_000_000u64
        }));
        let state = GameState::from_json(&json).expect("Node's state reads");
        assert_eq!(state.player_count, 3);
        assert_eq!(state.scores[..3], [10, 20, 30]);
        assert_eq!(
            state.get_last_action_json().unwrap(),
            serde_json::json!({
                "type": "draw", "playerIndex": 0, "source": "deck",
                "deckReshuffled": true, "timestamp": 1_758_000_000_000u64
            })
        );
        // Nor is the card written back
        assert!(!state.to_json().contains("\"cardId\""));
    }

    #[test]
    fn test_node_played_draw_and_play_and_hand_size_read_back() {
        for la in [
            serde_json::json!({"type": "draw", "playerIndex": 2, "source": "played",
                "cardId": 40, "deckReshuffled": false, "timestamp": 1_758_000_000_001u64}),
            serde_json::json!({"type": "play", "playerIndex": 1, "cardIds": [3, 16],
                "timestamp": 1_758_000_000_002u64}),
            serde_json::json!({"type": "selectHandSize", "playerIndex": 0, "handSize": 7}),
        ] {
            let state = GameState::from_json(&node_state(la.clone())).unwrap();
            assert_eq!(state.get_last_action_json().unwrap(), la);
            // And through Rust's own storage
            let again = GameState::from_json(&state.to_json()).unwrap();
            assert_eq!(again.get_last_action_json().unwrap(), la);
        }
    }

    #[test]
    fn test_node_zapzap_outcome_is_read_from_last_action() {
        let mut v: serde_json::Value = serde_json::from_str(&node_state(serde_json::json!({
            "type": "zapzap", "playerIndex": 1, "wasCounterActed": true,
            "counterActedByPlayerIndex": 0, "callerHandPoints": 3,
            "roundScores": {"0": 0, "1": 13, "2": 6}, "timestamp": 1_758_000_000_003u64
        })))
        .unwrap();
        v["currentAction"] = "finished".into();
        let state = GameState::from_json(&v.to_string()).unwrap();
        assert_eq!(state.zapzap_caller, Some(1));
        assert_eq!(state.was_counter_acted, Some(true));
        assert_eq!(state.counter_acted_by_player_index, Some(0));
        assert_eq!(state.round_scores.unwrap()[..3], [0, 13, 6]);
        assert_eq!(
            state.get_last_action_json().unwrap(),
            v["lastAction"],
            "the zapzap's lastAction reads back whole"
        );
    }

    #[test]
    fn test_older_rust_last_action_still_reads() {
        // Rust before this format: `{type, playerIndex, wasCounterActed, callerHandPoints}`
        let json = node_state(serde_json::json!({
            "type": "draw", "playerIndex": 2, "wasCounterActed": false, "callerHandPoints": 0
        }));
        let state = GameState::from_json(&json).unwrap();
        let la = state.get_last_action_json().unwrap();
        assert_eq!(la["type"], "draw");
        assert_eq!(la["playerIndex"], 2);
        // An unknown source reads as a deck draw, which names no card
        assert_eq!(la["source"], "deck");
        assert_eq!(la["deckReshuffled"], false);
        assert!(la.get("cardId").is_none());
        assert!(la.get("timestamp").is_none());

        let none = GameState::from_json(&node_state(serde_json::Value::Null)).unwrap();
        assert!(none.get_last_action_json().is_none());
    }

    #[test]
    fn test_node_eliminated_players_become_the_mask() {
        let mut v: serde_json::Value =
            serde_json::from_str(&node_state(serde_json::Value::Null)).unwrap();
        v["eliminatedPlayers"] = serde_json::json!([1]);
        assert!(v.get("eliminatedMask").is_none());
        let state = GameState::from_json(&v.to_string()).unwrap();
        assert!(state.is_eliminated(1));
        assert!(!state.is_eliminated(0) && !state.is_eliminated(2));

        // Rust's own storage keeps the mask, and writes Node's list beside it
        let json = state.to_json();
        let stored: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(stored["eliminatedPlayers"], serde_json::json!([1]));
        let again = GameState::from_json(&json).unwrap();
        assert_eq!(again.eliminated_mask, state.eliminated_mask);
        assert_eq!(again.active_players().to_vec(), vec![0, 2]);
    }

    #[test]
    fn test_node_golden_score_zapzap_recovers_the_lowest_hand() {
        // Node's golden score: seats 1 and 2 left (seat 0 out, no cards); seat 1 calls
        // with A♥ 2♥ = 3 and seat 2 ties with A♣ 2♣: seat 2 counteracts and wins. Node
        // stores no lowestHandPlayerIndex: it is recomputed from the hands.
        let mut v: serde_json::Value = serde_json::from_str(&node_state(serde_json::json!({
            "type": "zapzap", "playerIndex": 1, "wasCounterActed": true,
            "counterActedByPlayerIndex": 2, "callerHandPoints": 3,
            "roundScores": {"1": 3, "2": 0}, "timestamp": 1_758_000_000_004u64
        })))
        .unwrap();
        v["currentAction"] = "finished".into();
        v["isGoldenScore"] = true.into();
        v["eliminatedPlayers"] = serde_json::json!([0]);
        v["hands"] = serde_json::json!({"0": [], "1": [13, 14], "2": [26, 27]});
        let state = GameState::from_json(&v.to_string()).unwrap();
        assert_eq!(state.lowest_hand_player_index, Some(2));
        assert_eq!(crate::domain::services::is_game_over(&state), Some(2));

        // Seat 0 holding the lowest hand is found too (not mistaken for "none")
        v["eliminatedPlayers"] = serde_json::json!([2]);
        v["hands"] = serde_json::json!({"0": [0], "1": [13, 14], "2": []});
        v["lastAction"]["counterActedByPlayerIndex"] = 0.into();
        v["lastAction"]["roundScores"] = serde_json::json!({"0": 0, "1": 13});
        let state = GameState::from_json(&v.to_string()).unwrap();
        assert_eq!(state.lowest_hand_player_index, Some(0));
        assert_eq!(crate::domain::services::is_game_over(&state), Some(0));

        // A round still being played recovers nothing
        v["currentAction"] = "play".into();
        let state = GameState::from_json(&v.to_string()).unwrap();
        assert_eq!(state.lowest_hand_player_index, None);
    }
}
