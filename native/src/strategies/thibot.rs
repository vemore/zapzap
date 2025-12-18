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
}

impl Default for ThibotParams {
    fn default() -> Self {
        // Parameters optimized via genetic algorithm (40.73% winrate vs 32.35% baseline)
        Self {
            // Card Potential Evaluation
            joker_keep_score: 923,
            existing_pair_bonus: 54,
            good_pair_chance_bonus: 25,
            low_pair_chance_bonus: 14,
            dead_rank_penalty: 34,
            sequence_part_bonus: 52,
            potential_sequence_bonus: 33,
            joker_sequence_bonus: 31,
            close_with_joker_bonus: 13,

            // Play Selection (Offensive)
            value_score_weight: 19,
            cards_score_weight: 14,
            potential_divisor: 15,
            joker_play_penalty: 50,
            zapzap_potential_bonus: 122,

            // Draw Source Evaluation
            discard_joker_score: 177,
            low_points_base: 9,
            pair_completion_bonus: 133,
            three_of_kind_bonus: 25,
            sequence_completion_bonus: 52,
            dead_rank_discard_penalty: 46,
            discard_threshold: 14,

            // Defensive Mode
            defensive_threshold: 4,

            // ZapZap Decision
            zapzap_safe_hand_size: 2,
            zapzap_moderate_hand_size: 5,
            zapzap_moderate_value_threshold: 5,
            zapzap_risky_hand_size: 2,
            zapzap_risky_value_threshold: 2,
            zapzap_safe_value_threshold: 1,
        }
    }
}

/// Global parameters (can be modified for optimization)
/// These are genetically optimized values
static mut THIBOT_PARAMS: ThibotParams = ThibotParams {
    joker_keep_score: 923,
    existing_pair_bonus: 54,
    good_pair_chance_bonus: 25,
    low_pair_chance_bonus: 14,
    dead_rank_penalty: 34,
    sequence_part_bonus: 52,
    potential_sequence_bonus: 33,
    joker_sequence_bonus: 31,
    close_with_joker_bonus: 13,
    value_score_weight: 19,
    cards_score_weight: 14,
    potential_divisor: 15,
    joker_play_penalty: 50,
    zapzap_potential_bonus: 122,
    discard_joker_score: 177,
    low_points_base: 9,
    pair_completion_bonus: 133,
    three_of_kind_bonus: 25,
    sequence_completion_bonus: 52,
    dead_rank_discard_penalty: 46,
    discard_threshold: 14,
    defensive_threshold: 4,
    zapzap_safe_hand_size: 2,
    zapzap_moderate_hand_size: 5,
    zapzap_moderate_value_threshold: 5,
    zapzap_risky_hand_size: 2,
    zapzap_risky_value_threshold: 2,
    zapzap_safe_value_threshold: 1,
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

/// Thibot strategy - probability-based decisions with full card tracking
pub struct ThibotStrategy {
    rng_state: u64,
    params: ThibotParams,
}

impl ThibotStrategy {
    pub fn new() -> Self {
        ThibotStrategy {
            rng_state: 54321,
            params: get_thibot_params(),
        }
    }

    pub fn with_seed(seed: u64) -> Self {
        ThibotStrategy {
            rng_state: seed,
            params: get_thibot_params(),
        }
    }

    pub fn with_params(params: ThibotParams) -> Self {
        ThibotStrategy {
            rng_state: 54321,
            params,
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
}

impl Default for ThibotStrategy {
    fn default() -> Self {
        Self::new()
    }
}

impl BotStrategy for ThibotStrategy {
    fn select_play(&self, hand: &[u8], state: &GameState) -> Option<SmallVec<[u8; 8]>> {
        if hand.is_empty() {
            return None;
        }

        let min_opponent_size = self.min_opponent_hand_size(state);

        // Defensive mode: if any opponent has few cards, play max points
        if min_opponent_size <= self.params.defensive_threshold {
            return self.find_best_defensive_play(hand);
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
