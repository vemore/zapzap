//! ThibotStrategy - Probability-based bot that tracks all played cards
//!
//! Thibot's strategy is based on:
//! 1. Tracking ALL played cards (full discard pile knowledge)
//! 2. Tracking cards taken by other players from the discard
//! 3. Using probabilities to maximize cards played per turn
//! 4. Goal: reach 1 card in hand as fast as possible
//! 5. Safeguard: discard max points if opponent is close to ZapZap

use super::BotStrategy;
use crate::card_analyzer::{
    self, find_all_valid_plays, get_card_points, get_rank, get_suit, is_joker,
    would_complete_pair, would_complete_sequence,
};
use crate::game_state::GameState;
use smallvec::SmallVec;

/// Thibot configurable parameters for genetic optimization
#[derive(Debug, Clone, Copy)]
pub struct ThibotParams {
    // === Card Potential Evaluation ===
    /// Score for jokers (always keep)
    pub joker_keep_score: i32,
    /// Bonus when already have a pair of this rank
    pub existing_pair_bonus: i32,
    /// Bonus when 2+ cards drawable for pair completion
    pub good_pair_chance_bonus: i32,
    /// Bonus when 1 card drawable for pair completion
    pub low_pair_chance_bonus: i32,
    /// Penalty when rank is dead (no cards drawable)
    pub dead_rank_penalty: i32,
    /// Bonus for being part of a sequence (2+ adjacent)
    pub sequence_part_bonus: i32,
    /// Bonus for potential sequence (1 adjacent)
    pub potential_sequence_bonus: i32,
    /// Extra bonus for sequence potential with joker
    pub joker_sequence_bonus: i32,
    /// Bonus for close cards (diff=2) with joker
    pub close_with_joker_bonus: i32,

    // === Play Selection (Offensive) ===
    /// Weight for points removed per play
    pub value_score_weight: i32,
    /// Weight for cards removed per play
    pub cards_score_weight: i32,
    /// Divisor for remaining potential score
    pub potential_divisor: i32,
    /// Penalty per joker used in play
    pub joker_play_penalty: i32,
    /// Bonus for plays leaving hand value <= 5
    pub zapzap_potential_bonus: i32,

    // === Draw Source Evaluation ===
    /// Score for joker in discard
    pub discard_joker_score: i32,
    /// Base score for low point cards
    pub low_points_base: i32,
    /// Bonus for card completing a pair
    pub pair_completion_bonus: i32,
    /// Extra bonus for making 3-of-a-kind
    pub three_of_kind_bonus: i32,
    /// Bonus for card completing a sequence
    pub sequence_completion_bonus: i32,
    /// Penalty for dead rank card
    pub dead_rank_discard_penalty: i32,
    /// Threshold above deck expected value to take from discard
    pub discard_threshold: i32,

    // === Defensive Mode ===
    /// Opponent hand size threshold for defensive mode
    pub defensive_threshold: usize,

    // === ZapZap Decision ===
    /// Hand size threshold for "many cards" (safe to zapzap)
    pub zapzap_safe_hand_size: usize,
    /// Hand size threshold for "moderate cards"
    pub zapzap_moderate_hand_size: usize,
    /// My value threshold for moderate safety
    pub zapzap_moderate_value_threshold: u16,
    /// Opponent hand size for risk assessment
    pub zapzap_risky_hand_size: usize,
    /// My value threshold for risk assessment
    pub zapzap_risky_value_threshold: u16,
    /// My value threshold for automatic zapzap
    pub zapzap_safe_value_threshold: u16,

    // === Coordination Play/Draw ===
    /// % discount for future value (90 = 0.90)
    pub future_value_discount: i32,
    /// % risk penalty multiplier when opponent close to zapzap
    pub risk_penalty_multiplier: i32,
    /// Minimum score improvement to prefer coordination
    pub coordination_threshold: i32,
    /// Bonus for holding pair when 3rd card available in discard
    pub hold_pair_for_three_bonus: i32,
    /// Bonus for holding sequence when extension available
    pub hold_sequence_for_extend_bonus: i32,
}

impl Default for ThibotParams {
    fn default() -> Self {
        // Parameters optimized via genetic algorithm (44.25% winrate vs 40.55% baseline)
        // Optimization: 30 generations, 2000 games/eval, 872k total games
        Self {
            // Card Potential Evaluation
            joker_keep_score: 705,
            existing_pair_bonus: 68,
            good_pair_chance_bonus: 30,
            low_pair_chance_bonus: 12,
            dead_rank_penalty: 26,
            sequence_part_bonus: 33,
            potential_sequence_bonus: 27,
            joker_sequence_bonus: 31,
            close_with_joker_bonus: 17,

            // Play Selection (Offensive)
            value_score_weight: 15,
            cards_score_weight: 7,
            potential_divisor: 20,
            joker_play_penalty: 36,
            zapzap_potential_bonus: 79,

            // Draw Source Evaluation
            discard_joker_score: 116,
            low_points_base: 10,
            pair_completion_bonus: 56,
            three_of_kind_bonus: 24,
            sequence_completion_bonus: 73,
            dead_rank_discard_penalty: 46,
            discard_threshold: 8,

            // Defensive Mode
            defensive_threshold: 3,

            // ZapZap Decision
            zapzap_safe_hand_size: 2,
            zapzap_moderate_hand_size: 4,
            zapzap_moderate_value_threshold: 5,
            zapzap_risky_hand_size: 2,
            zapzap_risky_value_threshold: 2,
            zapzap_safe_value_threshold: 1,

            // Coordination Play/Draw
            future_value_discount: 91,
            risk_penalty_multiplier: 17,
            coordination_threshold: 6,
            hold_pair_for_three_bonus: 226,
            hold_sequence_for_extend_bonus: 114,
        }
    }
}

/// Global parameters (can be modified for optimization)
/// These are genetically optimized values
static mut THIBOT_PARAMS: ThibotParams = ThibotParams {
    joker_keep_score: 705,
    existing_pair_bonus: 68,
    good_pair_chance_bonus: 30,
    low_pair_chance_bonus: 12,
    dead_rank_penalty: 26,
    sequence_part_bonus: 33,
    potential_sequence_bonus: 27,
    joker_sequence_bonus: 31,
    close_with_joker_bonus: 17,
    value_score_weight: 15,
    cards_score_weight: 7,
    potential_divisor: 20,
    joker_play_penalty: 36,
    zapzap_potential_bonus: 79,
    discard_joker_score: 116,
    low_points_base: 10,
    pair_completion_bonus: 56,
    three_of_kind_bonus: 24,
    sequence_completion_bonus: 73,
    dead_rank_discard_penalty: 46,
    discard_threshold: 8,
    defensive_threshold: 3,
    zapzap_safe_hand_size: 2,
    zapzap_moderate_hand_size: 4,
    zapzap_moderate_value_threshold: 5,
    zapzap_risky_hand_size: 2,
    zapzap_risky_value_threshold: 2,
    zapzap_safe_value_threshold: 1,
    // Coordination Play/Draw
    future_value_discount: 91,
    risk_penalty_multiplier: 17,
    coordination_threshold: 6,
    hold_pair_for_three_bonus: 226,
    hold_sequence_for_extend_bonus: 114,
};

/// Set global Thibot parameters (for optimization)
pub fn set_thibot_params(params: ThibotParams) {
    unsafe {
        THIBOT_PARAMS = params;
    }
}

/// Get current Thibot parameters
pub fn get_thibot_params() -> ThibotParams {
    unsafe { THIBOT_PARAMS }
}

/// Coordinated decision from select_play to use in select_draw_source
#[derive(Debug, Clone, Default)]
struct CoordinatedDecision {
    /// Whether coordination is active
    is_coordinated: bool,
    /// Target card from discard to take
    target_card: u8,
}

/// Thibot strategy - probability-based decisions with full card tracking
pub struct ThibotStrategy {
    rng_state: u64,
    params: ThibotParams,
    /// Stored coordinated decision (set by select_play, used by select_draw_source)
    coordinated_decision: std::cell::RefCell<CoordinatedDecision>,
}

impl ThibotStrategy {
    pub fn new() -> Self {
        ThibotStrategy {
            rng_state: 54321,
            params: get_thibot_params(),
            coordinated_decision: std::cell::RefCell::new(CoordinatedDecision::default()),
        }
    }

    pub fn with_seed(seed: u64) -> Self {
        ThibotStrategy {
            rng_state: seed,
            params: get_thibot_params(),
            coordinated_decision: std::cell::RefCell::new(CoordinatedDecision::default()),
        }
    }

    pub fn with_params(params: ThibotParams) -> Self {
        ThibotStrategy {
            rng_state: 54321,
            params,
            coordinated_decision: std::cell::RefCell::new(CoordinatedDecision::default()),
        }
    }

    /// Simple xorshift64 RNG
    fn next_random(&mut self) -> u64 {
        let mut x = self.rng_state;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.rng_state = x;
        x
    }

    /// Check if any opponent is close to ZapZap (hand_size <= threshold)
    #[allow(dead_code)]
    fn is_opponent_close_to_zapzap(&self, state: &GameState, threshold: usize) -> bool {
        for i in 0..state.player_count {
            if i != state.current_turn && !state.is_eliminated(i) {
                let hand_size = state.hands[i as usize].len();
                if hand_size <= threshold {
                    return true;
                }
            }
        }
        false
    }

    /// Get the minimum opponent hand size
    fn min_opponent_hand_size(&self, state: &GameState) -> usize {
        let mut min_size = usize::MAX;
        for i in 0..state.player_count {
            if i != state.current_turn && !state.is_eliminated(i) {
                let hand_size = state.hands[i as usize].len();
                if hand_size < min_size {
                    min_size = hand_size;
                }
            }
        }
        min_size
    }

    /// Estimate if we can safely ZapZap based on tracked opponent cards
    /// Returns true if we're confident no opponent can counter
    fn can_safely_zapzap(&self, hand: &[u8], state: &GameState) -> bool {
        let my_value = card_analyzer::calculate_hand_value(hand);

        // Can't ZapZap if hand value > 5
        if my_value > 5 {
            return false;
        }

        // Always ZapZap with 0 points
        if my_value == 0 {
            return true;
        }

        // Always ZapZap with 1 point (very safe)
        if my_value == 1 {
            return true;
        }

        // Check each opponent's estimated minimum hand value
        let mut risky_opponents = 0;
        for i in 0..state.player_count {
            if i != state.current_turn && !state.is_eliminated(i) {
                let opponent_hand_size = state.hands[i as usize].len();
                let tracked_count = state.card_tracker.taken_count[i as usize];

                // If opponent has many cards and no tracked low cards, very safe
                if opponent_hand_size >= self.params.zapzap_safe_hand_size && tracked_count == 0 {
                    continue;
                }

                // If opponent has moderate cards, moderately safe
                if opponent_hand_size >= self.params.zapzap_moderate_hand_size
                    && tracked_count == 0
                    && my_value <= self.params.zapzap_moderate_value_threshold
                {
                    continue;
                }

                // Use card tracking to estimate their minimum possible value
                let estimated_min = state.estimate_min_hand_value(i);

                // If we know they have low cards, be careful
                if tracked_count > 0 && estimated_min <= my_value {
                    risky_opponents += 1;
                }

                // If opponent has few cards and we don't know what they have
                if opponent_hand_size <= self.params.zapzap_risky_hand_size && tracked_count == 0 {
                    // Could be anything - slight risk
                    if my_value >= self.params.zapzap_risky_value_threshold {
                        risky_opponents += 1;
                    }
                }
            }
        }

        // ZapZap if no risky opponents or if our value is very low
        risky_opponents == 0 || my_value <= self.params.zapzap_safe_value_threshold
    }

    /// Evaluate a card's usefulness for future combos
    /// Higher score = more valuable to keep
    fn evaluate_card_potential(&self, card: u8, hand: &[u8], state: &GameState) -> i32 {
        if is_joker(card) {
            return self.params.joker_keep_score;
        }

        let rank = get_rank(card);
        let suit = get_suit(card);
        let points = get_card_points(card) as i32;

        let mut score = -points; // Prefer keeping low cards

        // Check pair potential
        let drawable = state.count_drawable_rank(rank);
        let same_rank_in_hand = hand
            .iter()
            .filter(|&&c| !is_joker(c) && get_rank(c) == rank && c != card)
            .count();

        if same_rank_in_hand >= 1 {
            score += self.params.existing_pair_bonus;
        } else if drawable >= 2 {
            score += self.params.good_pair_chance_bonus;
        } else if drawable == 1 {
            score += self.params.low_pair_chance_bonus;
        } else {
            score -= self.params.dead_rank_penalty;
        }

        // Check sequence potential
        let same_suit: SmallVec<[u8; 10]> = hand
            .iter()
            .filter(|&&c| c != card && !is_joker(c) && get_suit(c) == suit)
            .map(|&c| get_rank(c))
            .collect();

        let card_rank_i8 = rank as i8;
        let mut adjacent_count = 0;
        let mut close_count = 0;

        for &other_rank in &same_suit {
            let diff = (card_rank_i8 - other_rank as i8).abs();
            if diff == 1 {
                adjacent_count += 1;
            } else if diff == 2 {
                close_count += 1;
            }
        }

        // Have joker? Sequences become more valuable
        let has_joker = hand.iter().any(|&c| is_joker(c));

        if adjacent_count >= 2 {
            score += self.params.sequence_part_bonus;
        } else if adjacent_count == 1 {
            score += self.params.potential_sequence_bonus;
            if has_joker {
                score += self.params.joker_sequence_bonus;
            }
        } else if close_count >= 1 && has_joker {
            score += self.params.close_with_joker_bonus;
        }

        score
    }

    /// Find the best play balancing:
    /// 1. Points removed (primary for hand value reduction)
    /// 2. Cards removed (secondary for fast reduction)
    /// 3. Future combo potential of remaining hand
    fn find_best_offensive_play(
        &self,
        hand: &[u8],
        state: &GameState,
    ) -> Option<SmallVec<[u8; 8]>> {
        let plays = find_all_valid_plays(hand);

        if plays.is_empty() {
            return None;
        }

        let hand_value = card_analyzer::calculate_hand_value(hand);

        // Score each play
        plays
            .into_iter()
            .max_by_key(|play| {
                // Remaining hand after this play
                let remaining: SmallVec<[u8; 10]> = hand
                    .iter()
                    .filter(|c| !play.contains(c))
                    .copied()
                    .collect();

                let remaining_value = card_analyzer::calculate_hand_value(&remaining);
                let points_removed = (hand_value - remaining_value) as i32;
                let cards_removed = play.len() as i32;

                // Evaluate remaining hand's combo potential
                let remaining_potential: i32 = remaining
                    .iter()
                    .map(|&c| self.evaluate_card_potential(c, &remaining, state))
                    .sum();

                // PRIMARY: Minimize remaining hand value (maximize points removed)
                // This is weighted heavily because low hand value = can ZapZap sooner
                let value_score = points_removed * self.params.value_score_weight;

                // SECONDARY: Prefer multi-card plays (faster hand reduction)
                // But only as a tiebreaker when point removal is similar
                let cards_score = cards_removed * self.params.cards_score_weight;

                // TERTIARY: Keep cards with good future potential
                let potential_score = remaining_potential / self.params.potential_divisor.max(1);

                // Penalty for using jokers (save for combos/ZapZap)
                let joker_penalty =
                    play.iter().filter(|&&c| is_joker(c)).count() as i32 * self.params.joker_play_penalty;

                // Bonus for plays that leave low remaining value (ZapZap potential)
                let zapzap_bonus = if remaining_value <= 5 {
                    self.params.zapzap_potential_bonus
                } else {
                    0
                };

                value_score + cards_score + potential_score - joker_penalty + zapzap_bonus
            })
    }

    /// Find the play that maximizes points removed (defensive mode)
    fn find_best_defensive_play(&self, hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
        card_analyzer::find_max_point_play(hand)
    }

    /// Evaluate how good a card from discard would be
    fn evaluate_discard_card(&self, card: u8, hand: &[u8], state: &GameState) -> i32 {
        if is_joker(card) {
            return self.params.discard_joker_score;
        }

        let rank = get_rank(card);
        let points = get_card_points(card) as i32;

        let mut score = 0;

        // Low points are good
        score += self.params.low_points_base - points;

        // Check if it completes a pair
        if would_complete_pair(hand, card) {
            score += self.params.pair_completion_bonus;

            // Even better if we already have 2 of this rank (makes 3-of-a-kind)
            let same_rank_count = hand
                .iter()
                .filter(|&&c| !is_joker(c) && get_rank(c) == rank)
                .count();
            if same_rank_count >= 2 {
                score += self.params.three_of_kind_bonus;
            }
        }

        // Check if it completes a sequence
        if would_complete_sequence(hand, card) {
            score += self.params.sequence_completion_bonus;
        }

        // Penalty if the rank is mostly dead (hard to use in pairs)
        let drawable = state.count_drawable_rank(rank);
        if drawable == 0 {
            // Only useful if it completes something NOW
            if !would_complete_pair(hand, card) && !would_complete_sequence(hand, card) {
                score -= self.params.dead_rank_discard_penalty;
            }
        }

        score
    }

    // ========================================
    // COORDINATED PLAY/DRAW DECISION METHODS
    // ========================================

    /// Find all valid plays that include a specific card
    fn find_plays_with_card(&self, hand: &[u8], card: u8) -> Vec<SmallVec<[u8; 8]>> {
        let mut hypothetical_hand: SmallVec<[u8; 10]> = hand.iter().copied().collect();
        hypothetical_hand.push(card);

        let all_plays = find_all_valid_plays(&hypothetical_hand);
        all_plays.into_iter().filter(|play| play.contains(&card)).collect()
    }

    /// Score a coordinated scenario (play now + take discard + play future combo)
    fn score_coordinated_scenario(
        &self,
        play_now: &[u8],
        future_play: &[u8],
        hand: &[u8],
        discard_card: u8,
        state: &GameState,
    ) -> i32 {
        let discount_factor = self.params.future_value_discount as f32 / 100.0;

        // Score for playing NOW
        let play_now_value = card_analyzer::calculate_hand_value(play_now) as i32;
        let joker_count_now = play_now.iter().filter(|&&c| is_joker(c)).count() as i32;
        let immediate_score = play_now_value * self.params.value_score_weight
            + play_now.len() as i32 * self.params.cards_score_weight
            - joker_count_now * self.params.joker_play_penalty;

        // Score for future play (discounted)
        let future_play_value = card_analyzer::calculate_hand_value(future_play) as i32;
        let joker_count_future = future_play.iter().filter(|&&c| is_joker(c)).count() as i32;
        let future_raw_score = future_play_value * self.params.value_score_weight
            + future_play.len() as i32 * self.params.cards_score_weight
            - joker_count_future * self.params.joker_play_penalty;
        let future_score = (future_raw_score as f32 * discount_factor) as i32;

        // Bonus for coordination patterns
        let mut coordination_bonus = 0i32;

        // Bonus for making a 3-of-a-kind or 4-of-a-kind
        if future_play.len() >= 3 && card_analyzer::is_valid_same_rank(future_play) {
            coordination_bonus += self.params.hold_pair_for_three_bonus;
            if future_play.len() >= 4 {
                coordination_bonus += self.params.hold_pair_for_three_bonus / 2;
            }
        }

        // Bonus for extending a sequence to 4+ cards
        if future_play.len() >= 4 && card_analyzer::is_valid_sequence(future_play) {
            coordination_bonus += self.params.hold_sequence_for_extend_bonus;
        }

        // Risk penalty: holding high value cards when opponent might ZapZap
        let min_opponent_size = self.min_opponent_hand_size(state);
        let remaining_after_play: SmallVec<[u8; 10]> = hand
            .iter()
            .filter(|c| !play_now.contains(c))
            .copied()
            .collect();
        let remaining_value = card_analyzer::calculate_hand_value(&remaining_after_play) as i32;
        let risk_penalty = if min_opponent_size <= self.params.defensive_threshold {
            remaining_value * self.params.risk_penalty_multiplier / 100
        } else {
            0
        };

        // ZapZap bonus for hand after future play
        let mut after_now_and_draw: SmallVec<[u8; 10]> = remaining_after_play.clone();
        after_now_and_draw.push(discard_card);
        let after_future_play: SmallVec<[u8; 10]> = after_now_and_draw
            .iter()
            .filter(|c| !future_play.contains(c))
            .copied()
            .collect();
        let after_future_value = card_analyzer::calculate_hand_value(&after_future_play);
        let zapzap_bonus = if after_future_value <= 5 {
            (self.params.zapzap_potential_bonus as f32 * discount_factor) as i32
        } else {
            0
        };

        immediate_score + future_score + coordination_bonus + zapzap_bonus - risk_penalty
    }

    /// Evaluate the "hold and take" scenario for a specific discard card
    fn evaluate_hold_and_take_scenario(
        &self,
        hand: &[u8],
        discard_card: u8,
        state: &GameState,
    ) -> Option<(SmallVec<[u8; 8]>, i32)> {
        let plays_with_discard = self.find_plays_with_card(hand, discard_card);

        // Filter to valuable plays (2+ cards including at least one from hand)
        let valuable_plays: Vec<_> = plays_with_discard
            .into_iter()
            .filter(|play| {
                let hand_cards_in_play = play.iter().filter(|&&c| c != discard_card && hand.contains(&c)).count();
                hand_cards_in_play >= 1 && play.len() >= 2
            })
            .collect();

        if valuable_plays.is_empty() {
            return None;
        }

        let mut best_play: Option<SmallVec<[u8; 8]>> = None;
        let mut best_score = i32::MIN;

        for future_play in valuable_plays {
            // Cards from hand needed for this future play
            let cards_to_keep: SmallVec<[u8; 8]> = future_play
                .iter()
                .filter(|&&c| c != discard_card)
                .copied()
                .collect();

            // What can we play NOW while keeping cards_to_keep?
            let playable_now: SmallVec<[u8; 10]> = hand
                .iter()
                .filter(|c| !cards_to_keep.contains(c))
                .copied()
                .collect();

            // Skip if we can't play anything
            if playable_now.is_empty() {
                continue;
            }

            // Find valid plays from the playable cards
            let mut plays_now = find_all_valid_plays(&playable_now);

            // If no valid combo, just play the lowest single card
            if plays_now.is_empty() {
                let lowest_card = playable_now
                    .iter()
                    .min_by_key(|&&c| get_card_points(c))
                    .copied()
                    .unwrap();
                let mut single_play = SmallVec::new();
                single_play.push(lowest_card);
                plays_now.push(single_play);
            }

            for play_now in plays_now {
                let score = self.score_coordinated_scenario(&play_now, &future_play, hand, discard_card, state);

                if score > best_score {
                    best_score = score;
                    best_play = Some(play_now);
                }
            }
        }

        best_play.map(|play| (play, best_score))
    }

    /// Evaluate coordination and return best play with coordination info
    fn evaluate_coordinated_scenarios(
        &self,
        hand: &[u8],
        last_cards_played: &[u8],
        state: &GameState,
    ) -> (Option<SmallVec<[u8; 8]>>, bool, u8) {
        // Calculate the "normal" play scenario score
        let normal_play = self.find_best_offensive_play(hand, state);
        let mut normal_score = i32::MIN;

        if let Some(ref play) = normal_play {
            let play_value = card_analyzer::calculate_hand_value(play) as i32;
            let remaining: SmallVec<[u8; 10]> = hand
                .iter()
                .filter(|c| !play.contains(c))
                .copied()
                .collect();
            let remaining_potential: i32 = remaining
                .iter()
                .map(|&c| self.evaluate_card_potential(c, &remaining, state))
                .sum();

            let joker_count = play.iter().filter(|&&c| is_joker(c)).count() as i32;
            let remaining_value = card_analyzer::calculate_hand_value(&remaining);
            let zapzap_bonus = if remaining_value <= 5 {
                self.params.zapzap_potential_bonus
            } else {
                0
            };

            normal_score = play_value * self.params.value_score_weight
                + play.len() as i32 * self.params.cards_score_weight
                + remaining_potential / self.params.potential_divisor.max(1)
                - joker_count * self.params.joker_play_penalty
                + zapzap_bonus;
        }

        // Evaluate coordination scenarios for each discard card
        let mut best_coordinated: Option<(SmallVec<[u8; 8]>, i32, u8)> = None;

        for &discard_card in last_cards_played {
            if let Some((play, score)) = self.evaluate_hold_and_take_scenario(hand, discard_card, state) {
                if best_coordinated.is_none() || score > best_coordinated.as_ref().unwrap().1 {
                    best_coordinated = Some((play, score, discard_card));
                }
            }
        }

        // Compare and decide
        if let Some((coord_play, coord_score, target_card)) = best_coordinated {
            if coord_score > normal_score + self.params.coordination_threshold {
                return (Some(coord_play), true, target_card);
            }
        }

        (normal_play, false, 0)
    }
}

impl Default for ThibotStrategy {
    fn default() -> Self {
        Self::new()
    }
}

impl BotStrategy for ThibotStrategy {
    fn select_play(&self, hand: &[u8], state: &GameState) -> Option<SmallVec<[u8; 8]>> {
        // Reset coordinated decision at start of turn
        *self.coordinated_decision.borrow_mut() = CoordinatedDecision::default();

        if hand.is_empty() {
            return None;
        }

        let min_opponent_size = self.min_opponent_hand_size(state);

        // Defensive mode: if any opponent has few cards, play max points
        if min_opponent_size <= self.params.defensive_threshold {
            return self.find_best_defensive_play(hand);
        }

        // Check for coordination opportunity with last played cards
        let last_cards_played = &state.last_cards_played;
        if !last_cards_played.is_empty() {
            let (play, is_coordinated, target_card) =
                self.evaluate_coordinated_scenarios(hand, last_cards_played, state);

            if is_coordinated {
                // Store the coordinated decision for select_draw_source
                *self.coordinated_decision.borrow_mut() = CoordinatedDecision {
                    is_coordinated: true,
                    target_card,
                };
                return play;
            }

            // Use the normal play from evaluation
            return play;
        }

        // Offensive mode: maximize cards removed while keeping potential
        self.find_best_offensive_play(hand, state)
    }

    fn should_zapzap(&self, hand: &[u8], state: &GameState) -> bool {
        let hand_value = card_analyzer::calculate_hand_value(hand);

        // Can't ZapZap if > 5 points
        if hand_value > 5 {
            return false;
        }

        // Always ZapZap with 0 points
        if hand_value == 0 {
            return true;
        }

        // Use probability-based decision
        self.can_safely_zapzap(hand, state)
    }

    fn select_draw_source(
        &self,
        hand: &[u8],
        last_cards_played: &[u8],
        state: &GameState,
    ) -> bool {
        // If no cards available in discard, must draw from deck
        if last_cards_played.is_empty() {
            return true;
        }

        // Check if we have a coordinated decision from select_play
        let coord = self.coordinated_decision.borrow();
        if coord.is_coordinated {
            // Verify the target card is still available
            if last_cards_played.contains(&coord.target_card) {
                return false; // Take from discard
            }
        }
        drop(coord); // Release borrow

        // Evaluate each available discard card
        let mut best_discard_score = i32::MIN;
        for &card in last_cards_played {
            let score = self.evaluate_discard_card(card, hand, state);
            if score > best_discard_score {
                best_discard_score = score;
            }
        }

        // Calculate expected value of drawing from deck
        // This is harder - we estimate based on what's drawable
        let mut deck_expected_value = 0i32;
        let mut total_drawable = 0u32;

        // For each rank, calculate contribution to expected value
        for rank in 0..13u8 {
            let drawable = state.count_drawable_rank(rank) as u32;
            if drawable > 0 {
                // Simulate what this card would be worth
                // Create a representative card of this rank (use spades as default)
                let sample_card = rank; // 0-12 are spades
                let card_value = self.evaluate_discard_card(sample_card, hand, state);
                deck_expected_value += card_value * drawable as i32;
                total_drawable += drawable;
            }
        }

        // Add joker contribution (rank 13 in our count system)
        let joker_drawable = state.count_drawable_rank(13) as u32;
        if joker_drawable > 0 {
            // Jokers are very valuable
            deck_expected_value += self.params.discard_joker_score * joker_drawable as i32;
            total_drawable += joker_drawable;
        }

        // Calculate average expected value from deck
        let avg_deck_value = if total_drawable > 0 {
            deck_expected_value / total_drawable as i32
        } else {
            0
        };

        // Decision: take from discard if best discard card beats expected deck value
        // Add a small threshold to prefer known cards over unknown
        if best_discard_score > avg_deck_value + self.params.discard_threshold {
            false // Take from discard
        } else {
            true // Draw from deck
        }
    }

    fn select_hand_size(&self, _active_player_count: u8, is_golden_score: bool) -> u8 {
        // Thibot prefers smaller hands to reach 1 card faster
        if is_golden_score {
            4 // Minimum in golden score
        } else {
            4 // Small hand = faster to reduce
        }
    }
}

// Need mutable version for hand size with some randomness
impl ThibotStrategy {
    pub fn select_hand_size_mut(&mut self, _active_player_count: u8, is_golden_score: bool) -> u8 {
        if is_golden_score {
            4
        } else {
            // Slightly randomize between 4-5 to not be too predictable
            4 + ((self.next_random() % 2) as u8)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_thibot() {
        let thibot = ThibotStrategy::new();
        let state = GameState::new(4);
        let hand = vec![0, 1, 2, 13]; // A♠, 2♠, 3♠, A♥

        let play = thibot.select_play(&hand, &state);
        assert!(play.is_some());
    }

    #[test]
    fn test_zapzap_decision() {
        let thibot = ThibotStrategy::new();
        let state = GameState::new(4);

        // Hand with value 0 - always zapzap
        assert!(thibot.should_zapzap(&[52, 53], &state));

        // Hand with value 3 - should zapzap with low risk
        assert!(thibot.should_zapzap(&[0, 1], &state)); // A + 2 = 3

        // Hand with value > 5 - can't zapzap
        assert!(!thibot.should_zapzap(&[10, 11], &state)); // J + Q = 23
    }

    #[test]
    fn test_draw_source() {
        let thibot = ThibotStrategy::new();
        let state = GameState::new(4);

        // No discard available - must draw from deck
        assert!(thibot.select_draw_source(&[0, 1], &[], &state));

        // Discard has ace that would complete pair
        let hand = vec![0]; // A♠
        let discard = vec![13]; // A♥
        // Should prefer discard (completes pair)
        assert!(!thibot.select_draw_source(&hand, &discard, &state));
    }

    #[test]
    fn test_defensive_mode() {
        let thibot = ThibotStrategy::new();
        let mut state = GameState::new(4);

        // Set opponent to have only 2 cards (close to zapzap)
        state.hands[1].clear();
        state.hands[1].push(0);
        state.hands[1].push(1);

        // Our hand: K♠, K♥, A♠ (should play KK for max points in defensive mode)
        let hand = vec![12, 25, 0]; // K♠, K♥, A♠

        let play = thibot.select_play(&hand, &state);
        assert!(play.is_some());

        let play = play.unwrap();
        // Should play the kings (24 points) not the ace (1 point)
        assert!(play.contains(&12) || play.contains(&25));
    }
}
