//! VinceBotStrategy (HardVince) - Advanced bot with 11 strategic layers
//!
//! Strategies implemented:
//! 1. Keep Jokers for sequences while opponents have > 3 cards
//! 2. Play Jokers in pairs/sets when any opponent has <= 3 cards
//! 3. Track when opponents pick cards from discard
//! 4. Track all played cards for probability calculation
//! 5. Priority Joker pickup when opponents have > 3 cards
//! 6. Golden Score Joker Strategy (hoard jokers, never play them)
//! 7. Early Game High Card Accumulation
//! 8. Enhanced Card Counting with probability
//! 9. Opponent Hand Modeling
//! 10. Strategic ZapZap Timing
//! 11. Bad Hand Fallback Strategy

use super::{BotAction, BotStrategy, DrawSource};
use crate::domain::value_objects::GameState;
use crate::infrastructure::bot::card_analyzer::{
    calculate_hand_value, can_call_zapzap, find_all_valid_plays, find_max_point_play,
    get_card_points, get_rank, get_suit, is_joker, is_valid_same_rank, is_valid_sequence,
};
use smallvec::SmallVec;
use std::collections::HashMap;
use std::sync::RwLock;

/// VinceBot parameters (genetically optimized)
#[derive(Debug, Clone)]
pub struct VinceParams {
    // Strategy 6: Golden Score Joker management
    pub golden_score_joker_penalty: f32,
    pub golden_score_joker_pickup_bonus: f32,

    // Strategy 1 & 2: Joker management based on opponent hand size
    pub joker_pair_set_penalty: f32,
    pub joker_sequence_penalty: f32,
    pub joker_pair_set_bonus_late_game: f32,
    pub joker_sequence_bonus_early: f32,
    pub joker_penalty_near_zapzap: f32,

    // Strategy 3: Opponent tracking
    pub opponent_wants_bonus_multiplier: f32,

    // Strategy 7: Early game high card accumulation
    pub intermediate_card_bonus_multiplier: f32,
    pub high_card_pair_breaking_penalty: f32,
    pub single_high_card_retention_penalty: f32,
    pub high_card_pair_preservation_bonus_multiplier: f32,

    // Card evaluation for draw decisions
    pub combination_bonus_multiplier: f32,
    pub set_bonus_multiplier: f32,
    pub set_bonus_reduction: f32,
    pub combination_bonus_reduction: f32,

    // Draw decision threshold
    pub discard_pickup_threshold: f32,

    // Strategy 8: Enhanced card counting
    pub deck_probability_weight: f32,
    pub low_probability_penalty: f32,

    // Strategy 9: Opponent modeling
    pub high_threat_zapzap_penalty: f32,
    pub opponent_threat_multiplier: f32,
    pub block_opponent_bonus: f32,

    // Strategy 10: Strategic ZapZap timing
    pub aggressive_zapzap_min_opponent_cards: f32,
    pub defensive_zapzap_risk_threshold: f32,
    pub defensive_zapzap_max_hand_value: u16,
    pub counter_zapzap_max_hand_value: u16,
    pub counter_zapzap_joker_bonus: f32,

    // Strategy 11: Bad Hand Fallback
    pub bad_hand_min_value: u16,
    pub bad_hand_high_card_bonus_multiplier: f32,
    pub bad_hand_max_pairs: usize,
    pub bad_hand_max_sequence_cards: usize,
}

impl Default for VinceParams {
    fn default() -> Self {
        // Parameters optimized via genetic algorithm (74,000 games)
        Self {
            golden_score_joker_penalty: -393.86,
            golden_score_joker_pickup_bonus: 23.89,

            joker_pair_set_penalty: -46.24,
            joker_sequence_penalty: -15.43,
            joker_pair_set_bonus_late_game: 93.69,
            joker_sequence_bonus_early: 11.47,
            joker_penalty_near_zapzap: -71.26,

            opponent_wants_bonus_multiplier: 5.63,

            intermediate_card_bonus_multiplier: 19.83,
            high_card_pair_breaking_penalty: -168.99,
            single_high_card_retention_penalty: -6.10,
            high_card_pair_preservation_bonus_multiplier: 44.28,

            combination_bonus_multiplier: 11.77,
            set_bonus_multiplier: 50.99,
            set_bonus_reduction: -6.41,
            combination_bonus_reduction: -21.53,

            discard_pickup_threshold: 15.45,

            deck_probability_weight: 6.87,
            low_probability_penalty: -25.65,

            high_threat_zapzap_penalty: -40.79,
            opponent_threat_multiplier: 2.40,
            block_opponent_bonus: 17.59,

            aggressive_zapzap_min_opponent_cards: 5.38,
            defensive_zapzap_risk_threshold: 0.13,
            defensive_zapzap_max_hand_value: 2,
            counter_zapzap_max_hand_value: 4,
            counter_zapzap_joker_bonus: 233.13,

            bad_hand_min_value: 67,
            bad_hand_high_card_bonus_multiplier: 3.92,
            bad_hand_max_pairs: 0,
            bad_hand_max_sequence_cards: 3,
        }
    }
}

/// Memory state for tracking game events
#[derive(Debug, Clone, Default)]
struct VinceMemory {
    /// All cards played this round
    played_cards_history: Vec<u8>,
    /// Cards picked by each opponent from discard
    opponent_picked_cards: HashMap<u8, Vec<u8>>,
    /// Last round number (to detect new round)
    last_round_number: Option<u16>,
    /// Bad hand mode active
    is_bad_hand_mode: bool,
    /// Initial hand analyzed this round
    initial_hand_analyzed: bool,
}

/// VinceBot strategy - advanced bot with multiple strategic layers
pub struct VinceBotStrategy {
    params: VinceParams,
    memory: RwLock<VinceMemory>,
}

impl VinceBotStrategy {
    pub fn new() -> Self {
        Self {
            params: VinceParams::default(),
            memory: RwLock::new(VinceMemory::default()),
        }
    }

    pub fn with_params(params: VinceParams) -> Self {
        Self {
            params,
            memory: RwLock::new(VinceMemory::default()),
        }
    }

    /// Update memory based on game state
    fn update_memory(&self, state: &GameState, player_index: u8) {
        let Ok(mut memory) = self.memory.write() else { return };

        // Detect new round - reset all memory
        if memory.last_round_number.is_some()
            && Some(state.round_number) != memory.last_round_number
        {
            memory.played_cards_history.clear();
            memory.opponent_picked_cards.clear();
            memory.is_bad_hand_mode = false;
            memory.initial_hand_analyzed = false;
        }
        memory.last_round_number = Some(state.round_number);

        // Track played cards from discard
        for &card in &state.last_cards_played {
            if !memory.played_cards_history.contains(&card) {
                memory.played_cards_history.push(card);
            }
        }

        // Track cards in full discard pile
        for &card in &state.discard_pile {
            if !memory.played_cards_history.contains(&card) {
                memory.played_cards_history.push(card);
            }
        }

        // Track opponent picks using card_tracker
        for i in 0..state.player_count {
            if i != player_index && !state.is_eliminated(i) {
                let known_cards = state.get_player_known_cards(i);
                if !known_cards.is_empty() {
                    memory
                        .opponent_picked_cards
                        .insert(i, known_cards.to_vec());
                }
            }
        }
    }

    /// Get minimum opponent hand size
    fn min_opponent_hand_size(&self, state: &GameState, player_index: u8) -> usize {
        let mut min_size = usize::MAX;
        for i in 0..state.player_count {
            if i != player_index && !state.is_eliminated(i) {
                let hand_size = state.hands[i as usize].len();
                if hand_size < min_size {
                    min_size = hand_size;
                }
            }
        }
        if min_size == usize::MAX {
            0
        } else {
            min_size
        }
    }

    /// Get average opponent hand size
    fn avg_opponent_hand_size(&self, state: &GameState, player_index: u8) -> f32 {
        let mut total = 0usize;
        let mut count = 0usize;
        for i in 0..state.player_count {
            if i != player_index && !state.is_eliminated(i) {
                total += state.hands[i as usize].len();
                count += 1;
            }
        }
        if count == 0 {
            0.0
        } else {
            total as f32 / count as f32
        }
    }

    /// Check if in early game phase (all players have >= 5 cards)
    fn is_early_game(&self, state: &GameState) -> bool {
        for i in 0..state.player_count {
            if !state.is_eliminated(i) && state.hands[i as usize].len() < 5 {
                return false;
            }
        }
        true
    }

    /// Get card category: low, intermediate, high, or joker
    fn get_card_category(&self, card: u8) -> &'static str {
        if is_joker(card) {
            return "joker";
        }
        let rank = get_rank(card);
        if rank <= 3 {
            "low"
        } else if rank <= 8 {
            "intermediate"
        } else {
            "high"
        }
    }

    /// Count high card pairs in hand
    fn count_high_card_pairs(&self, hand: &[u8]) -> usize {
        let mut rank_counts: HashMap<u8, usize> = HashMap::new();
        for &card in hand {
            if !is_joker(card) {
                let rank = get_rank(card);
                if rank >= 9 {
                    *rank_counts.entry(rank).or_insert(0) += 1;
                }
            }
        }
        rank_counts.values().filter(|&&c| c >= 2).count()
    }

    /// Analyze if hand is "bad" (poor starting position)
    fn analyze_bad_hand(&self, hand: &[u8]) -> bool {
        if hand.is_empty() {
            return false;
        }

        // Check for jokers
        if hand.iter().any(|&c| is_joker(c)) {
            return false;
        }

        let hand_value = calculate_hand_value(hand);
        if hand_value < self.params.bad_hand_min_value {
            return false;
        }

        // Count pairs
        let mut rank_counts: HashMap<u8, usize> = HashMap::new();
        for &card in hand {
            if !is_joker(card) {
                let rank = get_rank(card);
                *rank_counts.entry(rank).or_insert(0) += 1;
            }
        }
        let pair_count = rank_counts.values().filter(|&&c| c >= 2).count();
        if pair_count > self.params.bad_hand_max_pairs {
            return false;
        }

        // Check sequence potential
        let mut by_suit: HashMap<u8, Vec<u8>> = HashMap::new();
        for &card in hand {
            if !is_joker(card) {
                let suit = get_suit(card);
                by_suit.entry(suit).or_default().push(get_rank(card));
            }
        }

        let mut max_sequence_potential = 0usize;
        for ranks in by_suit.values() {
            if ranks.len() < 2 {
                continue;
            }
            let mut sorted_ranks = ranks.clone();
            sorted_ranks.sort_unstable();

            let mut seq_cards = 1usize;
            for i in 1..sorted_ranks.len() {
                if sorted_ranks[i] - sorted_ranks[i - 1] <= 2 {
                    seq_cards += 1;
                } else {
                    max_sequence_potential = max_sequence_potential.max(seq_cards);
                    seq_cards = 1;
                }
            }
            max_sequence_potential = max_sequence_potential.max(seq_cards);
        }

        if max_sequence_potential > self.params.bad_hand_max_sequence_cards {
            return false;
        }

        true
    }

    /// Calculate opponent ZapZap risk based on hand size and tracked cards
    fn estimate_opponent_zapzap_risk(&self, state: &GameState, player_index: u8) -> f32 {
        let mut max_risk = 0.0f32;
        for i in 0..state.player_count {
            if i != player_index && !state.is_eliminated(i) {
                let hand_size = state.hands[i as usize].len();
                let tracked_count = state.card_tracker.taken_count[i as usize];

                // Risk based on hand size
                let size_risk: f32 = if hand_size <= 1 {
                    0.9
                } else if hand_size <= 2 {
                    0.6
                } else if hand_size <= 3 {
                    0.3
                } else {
                    0.1
                };

                // Only use value_risk if we have tracked cards
                let risk = if tracked_count > 0 {
                    let known_value = state.estimate_min_hand_value(i);
                    let value_risk: f32 = if known_value <= 2 {
                        0.8
                    } else if known_value <= 5 {
                        0.5
                    } else {
                        0.2
                    };
                    size_risk.max(value_risk * 0.8)
                } else {
                    size_risk
                };

                max_risk = max_risk.max(risk);
            }
        }
        max_risk
    }

    /// Evaluate a play with all strategies applied
    fn evaluate_play(
        &self,
        play: &[u8],
        hand: &[u8],
        state: &GameState,
        player_index: u8,
    ) -> f32 {
        let remaining: Vec<u8> = hand.iter().filter(|c| !play.contains(c)).copied().collect();
        let remaining_value = calculate_hand_value(&remaining) as f32;
        let play_value = calculate_hand_value(play) as f32;
        let play_size = play.len() as f32;

        let mut score = -remaining_value + (play_size * 0.5);

        let jokers_in_play: Vec<u8> = play.iter().filter(|&&c| is_joker(c)).copied().collect();
        let has_jokers_in_play = !jokers_in_play.is_empty();

        let is_sequence = play.len() >= 3 && is_valid_sequence(play);
        let is_pair_or_set = play.len() >= 2 && is_valid_same_rank(play) && !is_sequence;

        let min_opponent_cards = self.min_opponent_hand_size(state, player_index);
        let opponents_have_more_than_3 = min_opponent_cards > 3;

        // STRATEGY 6: Golden Score Joker penalty
        if has_jokers_in_play && state.is_golden_score {
            score += self.params.golden_score_joker_penalty;
        }
        // STRATEGY 1 & 2: Joker management
        else if has_jokers_in_play {
            if opponents_have_more_than_3 {
                if is_pair_or_set {
                    score += self.params.joker_pair_set_penalty;
                } else if is_sequence {
                    score += self.params.joker_sequence_penalty;
                }
            } else if is_pair_or_set {
                score += self.params.joker_pair_set_bonus_late_game;
            }
        }

        // STRATEGY 3: Opponent tracking bonus
        let mut opponent_wants_bonus = 0.0f32;
        if let Ok(memory) = self.memory.read() {
            for (_player, picked_cards) in &memory.opponent_picked_cards {
                for &picked_card in picked_cards {
                    if is_joker(picked_card) {
                        continue;
                    }
                    let picked_rank = get_rank(picked_card);
                    let picked_suit = get_suit(picked_card);

                    for &remaining_card in &remaining {
                        if is_joker(remaining_card) {
                            continue;
                        }
                        let rank = get_rank(remaining_card);
                        let suit = get_suit(remaining_card);

                        if rank == picked_rank {
                            opponent_wants_bonus += self.params.opponent_wants_bonus_multiplier;
                        }
                        if suit == picked_suit && (rank as i8 - picked_rank as i8).abs() <= 2 {
                            opponent_wants_bonus += self.params.opponent_wants_bonus_multiplier;
                        }
                    }
                }
            }
        }
        score += opponent_wants_bonus;

        // STRATEGY 9: High threat penalty
        let zapzap_risk = self.estimate_opponent_zapzap_risk(state, player_index);
        if zapzap_risk > 0.5 {
            if remaining_value > 10.0 {
                score += self.params.high_threat_zapzap_penalty * zapzap_risk;
            }
            if play_value >= 15.0 {
                score += play_value * 0.5 * zapzap_risk;
            }
        }

        score
    }

    /// Check if any valid plays have triples or sequences
    fn has_triple_or_sequence(&self, plays: &[SmallVec<[u8; 8]>]) -> bool {
        for play in plays {
            if play.len() >= 3 && (is_valid_same_rank(play) || is_valid_sequence(play)) {
                return true;
            }
        }
        false
    }

    /// Evaluate card value for draw decision
    fn evaluate_card_value(
        &self,
        card: u8,
        hand: &[u8],
        state: &GameState,
        player_index: u8,
    ) -> f32 {
        let min_opponent_cards = self.min_opponent_hand_size(state, player_index);
        let opponents_have_more_than_3 = min_opponent_cards > 3;

        let mut test_hand: Vec<u8> = hand.to_vec();
        test_hand.push(card);

        // Count new combinations
        let original_plays = find_all_valid_plays(hand);
        let new_plays = find_all_valid_plays(&test_hand);

        let original_multi = original_plays.iter().filter(|p| p.len() > 1).count();
        let new_multi = new_plays
            .iter()
            .filter(|p| p.len() > 1 && p.contains(&card))
            .count();

        let mut combination_bonus =
            (new_multi as i32 - original_multi as i32) as f32 * self.params.combination_bonus_multiplier;

        // Low value bonus
        let card_points = get_card_points(card) as f32;
        let low_value_bonus = 10.0 - card_points;

        // Set bonus
        let rank = get_rank(card);
        let same_rank_count = hand
            .iter()
            .filter(|&&c| !is_joker(c) && get_rank(c) == rank)
            .count();

        let mut set_bonus = if same_rank_count >= 1 {
            same_rank_count as f32 * self.params.set_bonus_multiplier
        } else {
            0.0
        };

        // STRATEGY 4: Probability adjustment
        if !is_joker(card) {
            if let Ok(memory) = self.memory.read() {
                let same_rank_played = memory
                    .played_cards_history
                    .iter()
                    .filter(|&&c| !is_joker(c) && get_rank(c) == rank)
                    .count();

                if same_rank_played >= 2 {
                    set_bonus = (set_bonus + self.params.set_bonus_reduction).max(0.0);
                }
                if same_rank_played >= 3 {
                    set_bonus = 0.0;
                    combination_bonus = (combination_bonus + self.params.combination_bonus_reduction).max(0.0);
                }
            }

            // STRATEGY 8: Probability-based penalty
            let drawable = state.count_drawable_rank(rank);
            if drawable == 0 && same_rank_count == 1 {
                combination_bonus += self.params.low_probability_penalty;
            }
        }

        // STRATEGY 6 & 10: Joker handling
        if is_joker(card) {
            if state.is_golden_score {
                return self.params.golden_score_joker_pickup_bonus;
            }

            let hand_value = calculate_hand_value(hand);
            let zapzap_risk = self.estimate_opponent_zapzap_risk(state, player_index);

            if hand_value <= self.params.counter_zapzap_max_hand_value && zapzap_risk > 0.3 {
                return self.params.counter_zapzap_joker_bonus;
            }

            if opponents_have_more_than_3 {
                combination_bonus += self.params.joker_sequence_bonus_early;
            } else {
                return self.params.joker_penalty_near_zapzap;
            }
        }

        combination_bonus + low_value_bonus + set_bonus
    }
}

impl Default for VinceBotStrategy {
    fn default() -> Self {
        Self::new()
    }
}

impl BotStrategy for VinceBotStrategy {
    fn select_hand_size(&self, state: &GameState, _player_index: u8) -> u8 {
        if state.is_golden_score {
            8 + (rand::random::<u8>() % 3) // 8, 9, or 10
        } else {
            6 + (rand::random::<u8>() % 2) // 6 or 7
        }
    }

    fn decide_action(&self, state: &GameState, player_index: u8) -> BotAction {
        let hand = state.get_hand(player_index);
        self.update_memory(state, player_index);

        if !can_call_zapzap(hand) {
            return BotAction::Play;
        }

        let hand_value = calculate_hand_value(hand);

        // Always zapzap with 0 points
        if hand_value == 0 {
            return BotAction::ZapZap;
        }

        let zapzap_risk = self.estimate_opponent_zapzap_risk(state, player_index);
        let avg_opponent_cards = self.avg_opponent_hand_size(state, player_index);

        // STRATEGY 10 - DEFENSIVE MODE
        if zapzap_risk >= self.params.defensive_zapzap_risk_threshold {
            if hand_value <= self.params.defensive_zapzap_max_hand_value {
                return BotAction::ZapZap;
            }
            return BotAction::Play;
        }

        // STRATEGY 10 - AGGRESSIVE MODE
        if avg_opponent_cards >= self.params.aggressive_zapzap_min_opponent_cards {
            return BotAction::ZapZap;
        }

        // Standard logic
        if hand_value <= 2 {
            return BotAction::ZapZap;
        }

        let round = state.round_number;
        if round <= 2 && hand_value <= 2 {
            return BotAction::ZapZap;
        } else if round <= 4 && hand_value <= 3 {
            return BotAction::ZapZap;
        } else if hand_value <= 4 {
            return BotAction::ZapZap;
        }

        BotAction::Play
    }

    fn select_cards(&self, state: &GameState, player_index: u8) -> Vec<u8> {
        let hand = state.get_hand(player_index);
        self.update_memory(state, player_index);

        if hand.is_empty() {
            return Vec::new();
        }

        let valid_plays = find_all_valid_plays(hand);
        if valid_plays.is_empty() {
            return Vec::new();
        }

        let is_early_game = self.is_early_game(state);

        // STRATEGY 11: Bad hand detection
        if let Ok(mut memory) = self.memory.write() {
            if !memory.initial_hand_analyzed && is_early_game {
                memory.is_bad_hand_mode = self.analyze_bad_hand(hand);
                memory.initial_hand_analyzed = true;
            }
        }

        // STRATEGY 11: Bad hand fallback - play highest value cards
        let is_bad_hand_mode = self.memory.read().map(|m| m.is_bad_hand_mode).unwrap_or(false);
        if is_bad_hand_mode && !state.is_golden_score {
            if let Some(max_play) = find_max_point_play(hand) {
                return max_play.into_iter().collect();
            }
        }

        // Evaluate all plays
        let mut evaluated_plays: Vec<(SmallVec<[u8; 8]>, f32)> = valid_plays
            .into_iter()
            .map(|play| {
                let score = self.evaluate_play(&play, hand, state, player_index);
                (play, score)
            })
            .collect();

        // STRATEGY 7: Early game high card accumulation
        if is_early_game && !state.is_golden_score {
            let plays_ref: Vec<_> = evaluated_plays.iter().map(|(p, _)| p.clone()).collect();
            let has_triple_or_seq = self.has_triple_or_sequence(&plays_ref);

            if !has_triple_or_seq {
                for (play, score) in &mut evaluated_plays {
                    if play.len() <= 2 {
                        let mut intermediate_count = 0;
                        let mut high_count = 0;

                        for &card in play.iter() {
                            match self.get_card_category(card) {
                                "intermediate" => intermediate_count += 1,
                                "high" => high_count += 1,
                                _ => {}
                            }
                        }

                        let remaining: Vec<u8> =
                            hand.iter().filter(|c| !play.contains(c)).copied().collect();
                        let high_pairs_remaining = self.count_high_card_pairs(&remaining);

                        if intermediate_count > 0 {
                            *score +=
                                intermediate_count as f32 * self.params.intermediate_card_bonus_multiplier;
                        }

                        if high_count > 0 && play.len() == 1 {
                            let card_rank = get_rank(play[0]);
                            let same_rank_in_hand = hand
                                .iter()
                                .filter(|&&c| !is_joker(c) && get_rank(c) == card_rank)
                                .count();

                            if same_rank_in_hand >= 2 {
                                *score += self.params.high_card_pair_breaking_penalty;
                            } else if card_rank >= 9 {
                                *score += self.params.single_high_card_retention_penalty;
                            }
                        }

                        if high_pairs_remaining > 0 {
                            *score += high_pairs_remaining as f32
                                * self.params.high_card_pair_preservation_bonus_multiplier;
                        }
                    }
                }
            }
        }

        // Sort by score descending
        evaluated_plays.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        // Return best play
        evaluated_plays
            .into_iter()
            .next()
            .map(|(play, _)| play.into_iter().collect())
            .unwrap_or_default()
    }

    fn decide_draw_source(&self, state: &GameState, player_index: u8) -> DrawSource {
        let hand = state.get_hand(player_index);
        self.update_memory(state, player_index);

        if state.last_cards_played.is_empty() {
            return DrawSource::Deck;
        }

        let min_opponent_cards = self.min_opponent_hand_size(state, player_index);
        let opponents_have_more_than_3 = min_opponent_cards > 3;

        // Find jokers in discard
        let jokers_in_discard: Vec<u8> = state
            .last_cards_played
            .iter()
            .filter(|&&c| is_joker(c))
            .copied()
            .collect();

        // STRATEGY 6: Always pick jokers in Golden Score
        if !jokers_in_discard.is_empty() && state.is_golden_score {
            return DrawSource::Discard(jokers_in_discard[0]);
        }

        // STRATEGY 10: Counter-ZapZap joker pickup
        let hand_value = calculate_hand_value(hand);
        let zapzap_risk = self.estimate_opponent_zapzap_risk(state, player_index);

        if !jokers_in_discard.is_empty()
            && hand_value <= self.params.counter_zapzap_max_hand_value
            && zapzap_risk > 0.3
        {
            return DrawSource::Discard(jokers_in_discard[0]);
        }

        // STRATEGY 5: Priority joker pickup when opponents have > 3 cards
        if !jokers_in_discard.is_empty() && opponents_have_more_than_3 {
            return DrawSource::Discard(jokers_in_discard[0]);
        }

        // Evaluate each discard card
        let mut best_card = 0u8;
        let mut best_value = f32::MIN;

        for &card in &state.last_cards_played {
            let value = self.evaluate_card_value(card, hand, state, player_index);
            if value > best_value {
                best_value = value;
                best_card = card;
            }
        }

        // Compare with threshold
        if best_value > self.params.discard_pickup_threshold {
            DrawSource::Discard(best_card)
        } else {
            DrawSource::Deck
        }
    }

    fn should_call_zapzap(&self, state: &GameState, player_index: u8) -> bool {
        matches!(self.decide_action(state, player_index), BotAction::ZapZap)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_vince_bot() {
        let bot = VinceBotStrategy::new();
        let mut state = GameState::new(4);
        state.hands[0] = smallvec::smallvec![0, 1, 2, 13]; // A♠, 2♠, 3♠, A♥

        let cards = bot.select_cards(&state, 0);
        assert!(!cards.is_empty());
    }

    #[test]
    fn test_golden_score_joker_hoard() {
        let bot = VinceBotStrategy::new();
        let mut state = GameState::new(2);
        state.is_golden_score = true;
        state.hands[0] = smallvec::smallvec![0, 1];
        state.last_cards_played = smallvec::smallvec![52]; // Joker

        // Should pick up joker in golden score
        let draw = bot.decide_draw_source(&state, 0);
        assert!(matches!(draw, DrawSource::Discard(52)));
    }

    #[test]
    fn test_bad_hand_detection() {
        let bot = VinceBotStrategy::new();
        // High value hand with no combos
        let bad_hand = vec![12, 25, 38, 51, 10]; // K♠, K♥, K♣, K♦, J♠ = 61 pts, no pairs (all different)

        // Actually this has 4 kings so it's not bad...
        // Let's try scattered high cards
        let scattered_hand = vec![12, 24, 37, 50, 10, 23]; // Various high cards, different suits
        let is_bad = bot.analyze_bad_hand(&scattered_hand);
        // With 4 kings this should be good, not bad
        assert!(!is_bad || scattered_hand.len() < 5);
    }

    #[test]
    fn test_zapzap_aggressive() {
        let bot = VinceBotStrategy::new();
        let mut state = GameState::new(4);

        // Bot has 3 points, opponents have many cards
        state.hands[0] = smallvec::smallvec![0, 1, 52]; // A + 2 + Joker = 3 pts
        state.hands[1] = smallvec::smallvec![0, 1, 2, 3, 4, 5];
        state.hands[2] = smallvec::smallvec![0, 1, 2, 3, 4, 5];
        state.hands[3] = smallvec::smallvec![0, 1, 2, 3, 4, 5];
        state.current_turn = 0;

        // Should be aggressive and call zapzap
        assert!(bot.should_call_zapzap(&state, 0));
    }
}
