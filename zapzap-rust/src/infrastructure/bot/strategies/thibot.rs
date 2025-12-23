//! ThibotStrategy - Probability-based bot that tracks all played cards
//!
//! Thibot's strategy is based on:
//! 1. Tracking ALL played cards (full discard pile knowledge)
//! 2. Tracking cards taken by other players from the discard
//! 3. Using probabilities to maximize cards played per turn
//! 4. Goal: reach 1 card in hand as fast as possible
//! 5. Safeguard: discard max points if opponent is close to ZapZap
//! 6. Coordinated play/draw decisions for optimal combos

use super::{BotAction, BotStrategy, DrawSource};
use crate::domain::value_objects::GameState;
use crate::infrastructure::bot::card_analyzer::{
    calculate_hand_value, can_call_zapzap, find_all_valid_plays, find_max_point_play,
    get_card_points, get_rank, get_suit, is_joker, is_valid_same_rank, is_valid_sequence,
    would_complete_pair, would_complete_sequence,
};
use smallvec::SmallVec;
use std::sync::RwLock;

/// Thibot configurable parameters (genetically optimized)
#[derive(Debug, Clone, Copy)]
pub struct ThibotParams {
    // === Card Potential Evaluation ===
    pub joker_keep_score: i32,
    pub existing_pair_bonus: i32,
    pub good_pair_chance_bonus: i32,
    pub low_pair_chance_bonus: i32,
    pub dead_rank_penalty: i32,
    pub sequence_part_bonus: i32,
    pub potential_sequence_bonus: i32,
    pub joker_sequence_bonus: i32,
    pub close_with_joker_bonus: i32,

    // === Play Selection (Offensive) ===
    pub value_score_weight: i32,
    pub cards_score_weight: i32,
    pub potential_divisor: i32,
    pub joker_play_penalty: i32,
    pub zapzap_potential_bonus: i32,

    // === Draw Source Evaluation ===
    pub discard_joker_score: i32,
    pub low_points_base: i32,
    pub pair_completion_bonus: i32,
    pub three_of_kind_bonus: i32,
    pub sequence_completion_bonus: i32,
    pub dead_rank_discard_penalty: i32,
    pub discard_threshold: i32,

    // === Defensive Mode ===
    pub defensive_threshold: usize,

    // === ZapZap Decision ===
    pub zapzap_safe_hand_size: usize,
    pub zapzap_moderate_hand_size: usize,
    pub zapzap_moderate_value_threshold: u16,
    pub zapzap_risky_hand_size: usize,
    pub zapzap_risky_value_threshold: u16,
    pub zapzap_safe_value_threshold: u16,

    // === Coordination Play/Draw ===
    pub future_value_discount: i32,
    pub risk_penalty_multiplier: i32,
    pub coordination_threshold: i32,
    pub hold_pair_for_three_bonus: i32,
    pub hold_sequence_for_extend_bonus: i32,
}

impl Default for ThibotParams {
    fn default() -> Self {
        // Parameters optimized via genetic algorithm (44.25% winrate vs 40.55% baseline)
        Self {
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

            future_value_discount: 91,
            risk_penalty_multiplier: 17,
            coordination_threshold: 6,
            hold_pair_for_three_bonus: 226,
            hold_sequence_for_extend_bonus: 114,
        }
    }
}

/// Coordinated decision from select_cards to use in decide_draw_source
#[derive(Debug, Clone, Default)]
struct CoordinatedDecision {
    is_coordinated: bool,
    target_card: u8,
}

/// Thibot strategy - probability-based decisions with full card tracking
pub struct ThibotStrategy {
    params: ThibotParams,
    coordinated_decision: RwLock<CoordinatedDecision>,
}

impl ThibotStrategy {
    pub fn new() -> Self {
        Self {
            params: ThibotParams::default(),
            coordinated_decision: RwLock::new(CoordinatedDecision::default()),
        }
    }

    pub fn with_params(params: ThibotParams) -> Self {
        Self {
            params,
            coordinated_decision: RwLock::new(CoordinatedDecision::default()),
        }
    }

    /// Get the minimum opponent hand size
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
        min_size
    }

    /// Estimate if we can safely ZapZap based on tracked opponent cards
    fn can_safely_zapzap(&self, hand: &[u8], state: &GameState, player_index: u8) -> bool {
        let my_value = calculate_hand_value(hand);

        if my_value > 5 {
            return false;
        }

        if my_value == 0 || my_value == 1 {
            return true;
        }

        let mut risky_opponents = 0;
        for i in 0..state.player_count {
            if i != player_index && !state.is_eliminated(i) {
                let opponent_hand_size = state.hands[i as usize].len();
                let tracked_count = state.card_tracker.taken_count[i as usize];

                if opponent_hand_size >= self.params.zapzap_safe_hand_size && tracked_count == 0 {
                    continue;
                }

                if opponent_hand_size >= self.params.zapzap_moderate_hand_size
                    && tracked_count == 0
                    && my_value <= self.params.zapzap_moderate_value_threshold
                {
                    continue;
                }

                let estimated_min = state.estimate_min_hand_value(i);

                if tracked_count > 0 && estimated_min <= my_value {
                    risky_opponents += 1;
                }

                if opponent_hand_size <= self.params.zapzap_risky_hand_size && tracked_count == 0 {
                    if my_value >= self.params.zapzap_risky_value_threshold {
                        risky_opponents += 1;
                    }
                }
            }
        }

        risky_opponents == 0 || my_value <= self.params.zapzap_safe_value_threshold
    }

    /// Evaluate a card's usefulness for future combos
    fn evaluate_card_potential(&self, card: u8, hand: &[u8], state: &GameState) -> i32 {
        if is_joker(card) {
            return self.params.joker_keep_score;
        }

        let rank = get_rank(card);
        let suit = get_suit(card);
        let points = get_card_points(card) as i32;

        let mut score = -points;

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

    /// Find the best play balancing points, cards, and future potential
    fn find_best_offensive_play(
        &self,
        hand: &[u8],
        state: &GameState,
    ) -> Option<SmallVec<[u8; 8]>> {
        let plays = find_all_valid_plays(hand);

        if plays.is_empty() {
            return None;
        }

        let hand_value = calculate_hand_value(hand);

        plays.into_iter().max_by_key(|play| {
            let remaining: SmallVec<[u8; 10]> = hand
                .iter()
                .filter(|c| !play.contains(c))
                .copied()
                .collect();

            let remaining_value = calculate_hand_value(&remaining);
            let points_removed = (hand_value - remaining_value) as i32;
            let cards_removed = play.len() as i32;

            let remaining_potential: i32 = remaining
                .iter()
                .map(|&c| self.evaluate_card_potential(c, &remaining, state))
                .sum();

            let value_score = points_removed * self.params.value_score_weight;
            let cards_score = cards_removed * self.params.cards_score_weight;
            let potential_score = remaining_potential / self.params.potential_divisor.max(1);

            let joker_penalty = play.iter().filter(|&&c| is_joker(c)).count() as i32
                * self.params.joker_play_penalty;

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
        find_max_point_play(hand)
    }

    /// Evaluate how good a card from discard would be
    fn evaluate_discard_card(&self, card: u8, hand: &[u8], state: &GameState) -> i32 {
        if is_joker(card) {
            return self.params.discard_joker_score;
        }

        let rank = get_rank(card);
        let points = get_card_points(card) as i32;

        let mut score = self.params.low_points_base - points;

        if would_complete_pair(hand, card) {
            score += self.params.pair_completion_bonus;

            let same_rank_count = hand
                .iter()
                .filter(|&&c| !is_joker(c) && get_rank(c) == rank)
                .count();
            if same_rank_count >= 2 {
                score += self.params.three_of_kind_bonus;
            }
        }

        if would_complete_sequence(hand, card) {
            score += self.params.sequence_completion_bonus;
        }

        let drawable = state.count_drawable_rank(rank);
        if drawable == 0 && !would_complete_pair(hand, card) && !would_complete_sequence(hand, card)
        {
            score -= self.params.dead_rank_discard_penalty;
        }

        score
    }

    /// Find all valid plays that include a specific card
    fn find_plays_with_card(&self, hand: &[u8], card: u8) -> Vec<SmallVec<[u8; 8]>> {
        let mut hypothetical_hand: SmallVec<[u8; 10]> = hand.iter().copied().collect();
        hypothetical_hand.push(card);

        let all_plays = find_all_valid_plays(&hypothetical_hand);
        all_plays
            .into_iter()
            .filter(|play| play.contains(&card))
            .collect()
    }

    /// Score a coordinated scenario (play now + take discard + play future combo)
    fn score_coordinated_scenario(
        &self,
        play_now: &[u8],
        future_play: &[u8],
        hand: &[u8],
        discard_card: u8,
        state: &GameState,
        player_index: u8,
    ) -> i32 {
        let discount_factor = self.params.future_value_discount as f32 / 100.0;

        let play_now_value = calculate_hand_value(play_now) as i32;
        let joker_count_now = play_now.iter().filter(|&&c| is_joker(c)).count() as i32;
        let immediate_score = play_now_value * self.params.value_score_weight
            + play_now.len() as i32 * self.params.cards_score_weight
            - joker_count_now * self.params.joker_play_penalty;

        let future_play_value = calculate_hand_value(future_play) as i32;
        let joker_count_future = future_play.iter().filter(|&&c| is_joker(c)).count() as i32;
        let future_raw_score = future_play_value * self.params.value_score_weight
            + future_play.len() as i32 * self.params.cards_score_weight
            - joker_count_future * self.params.joker_play_penalty;
        let future_score = (future_raw_score as f32 * discount_factor) as i32;

        let mut coordination_bonus = 0i32;

        if future_play.len() >= 3 && is_valid_same_rank(future_play) {
            coordination_bonus += self.params.hold_pair_for_three_bonus;
            if future_play.len() >= 4 {
                coordination_bonus += self.params.hold_pair_for_three_bonus / 2;
            }
        }

        if future_play.len() >= 4 && is_valid_sequence(future_play) {
            coordination_bonus += self.params.hold_sequence_for_extend_bonus;
        }

        let min_opponent_size = self.min_opponent_hand_size(state, player_index);
        let remaining_after_play: SmallVec<[u8; 10]> = hand
            .iter()
            .filter(|c| !play_now.contains(c))
            .copied()
            .collect();
        let remaining_value = calculate_hand_value(&remaining_after_play) as i32;
        let risk_penalty = if min_opponent_size <= self.params.defensive_threshold {
            remaining_value * self.params.risk_penalty_multiplier / 100
        } else {
            0
        };

        let mut after_now_and_draw: SmallVec<[u8; 10]> = remaining_after_play.clone();
        after_now_and_draw.push(discard_card);
        let after_future_play: SmallVec<[u8; 10]> = after_now_and_draw
            .iter()
            .filter(|c| !future_play.contains(c))
            .copied()
            .collect();
        let after_future_value = calculate_hand_value(&after_future_play);
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
        player_index: u8,
    ) -> Option<(SmallVec<[u8; 8]>, i32)> {
        let plays_with_discard = self.find_plays_with_card(hand, discard_card);

        let valuable_plays: Vec<_> = plays_with_discard
            .into_iter()
            .filter(|play| {
                let hand_cards_in_play = play
                    .iter()
                    .filter(|&&c| c != discard_card && hand.contains(&c))
                    .count();
                hand_cards_in_play >= 1 && play.len() >= 2
            })
            .collect();

        if valuable_plays.is_empty() {
            return None;
        }

        let mut best_play: Option<SmallVec<[u8; 8]>> = None;
        let mut best_score = i32::MIN;

        for future_play in valuable_plays {
            let cards_to_keep: SmallVec<[u8; 8]> = future_play
                .iter()
                .filter(|&&c| c != discard_card)
                .copied()
                .collect();

            let playable_now: SmallVec<[u8; 10]> = hand
                .iter()
                .filter(|c| !cards_to_keep.contains(c))
                .copied()
                .collect();

            if playable_now.is_empty() {
                continue;
            }

            let mut plays_now = find_all_valid_plays(&playable_now);

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
                let score = self.score_coordinated_scenario(
                    &play_now,
                    &future_play,
                    hand,
                    discard_card,
                    state,
                    player_index,
                );

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
        state: &GameState,
        player_index: u8,
    ) -> (Option<SmallVec<[u8; 8]>>, bool, u8) {
        let normal_play = self.find_best_offensive_play(hand, state);
        let mut normal_score = i32::MIN;

        if let Some(ref play) = normal_play {
            let play_value = calculate_hand_value(play) as i32;
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
            let remaining_value = calculate_hand_value(&remaining);
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

        let mut best_coordinated: Option<(SmallVec<[u8; 8]>, i32, u8)> = None;

        for &discard_card in &state.last_cards_played {
            if let Some((play, score)) =
                self.evaluate_hold_and_take_scenario(hand, discard_card, state, player_index)
            {
                if best_coordinated.is_none() || score > best_coordinated.as_ref().unwrap().1 {
                    best_coordinated = Some((play, score, discard_card));
                }
            }
        }

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
    fn select_hand_size(&self, state: &GameState, _player_index: u8) -> u8 {
        if state.is_golden_score {
            4
        } else {
            4
        }
    }

    fn decide_action(&self, state: &GameState, player_index: u8) -> BotAction {
        let hand = state.get_hand(player_index);

        if can_call_zapzap(hand) {
            let hand_value = calculate_hand_value(hand);

            // Always call with 0 points
            if hand_value == 0 {
                return BotAction::ZapZap;
            }

            // Use probability-based decision
            if self.can_safely_zapzap(hand, state, player_index) {
                return BotAction::ZapZap;
            }
        }

        BotAction::Play
    }

    fn select_cards(&self, state: &GameState, player_index: u8) -> Vec<u8> {
        // Reset coordinated decision at start of turn
        if let Ok(mut coord) = self.coordinated_decision.write() {
            *coord = CoordinatedDecision::default();
        }

        let hand = state.get_hand(player_index);

        if hand.is_empty() {
            return Vec::new();
        }

        let min_opponent_size = self.min_opponent_hand_size(state, player_index);

        // Defensive mode: if any opponent has few cards, play max points
        if min_opponent_size <= self.params.defensive_threshold {
            return self
                .find_best_defensive_play(hand)
                .map(|p| p.into_iter().collect())
                .unwrap_or_default();
        }

        // Check for coordination opportunity with last played cards
        if !state.last_cards_played.is_empty() {
            let (play, is_coordinated, target_card) =
                self.evaluate_coordinated_scenarios(hand, state, player_index);

            if is_coordinated {
                if let Ok(mut coord) = self.coordinated_decision.write() {
                    *coord = CoordinatedDecision {
                        is_coordinated: true,
                        target_card,
                    };
                }
                return play.map(|p| p.into_iter().collect()).unwrap_or_default();
            }

            return play.map(|p| p.into_iter().collect()).unwrap_or_default();
        }

        // Offensive mode: maximize cards removed while keeping potential
        self.find_best_offensive_play(hand, state)
            .map(|p| p.into_iter().collect())
            .unwrap_or_default()
    }

    fn decide_draw_source(&self, state: &GameState, player_index: u8) -> DrawSource {
        let hand = state.get_hand(player_index);

        if state.last_cards_played.is_empty() {
            return DrawSource::Deck;
        }

        // Check if we have a coordinated decision from select_cards
        if let Ok(coord) = self.coordinated_decision.read() {
            if coord.is_coordinated && state.last_cards_played.contains(&coord.target_card) {
                return DrawSource::Discard(coord.target_card);
            }
        }

        // Evaluate each available discard card
        let mut best_discard_card = 0u8;
        let mut best_discard_score = i32::MIN;
        for &card in &state.last_cards_played {
            let score = self.evaluate_discard_card(card, hand, state);
            if score > best_discard_score {
                best_discard_score = score;
                best_discard_card = card;
            }
        }

        // Calculate expected value of drawing from deck
        let mut deck_expected_value = 0i32;
        let mut total_drawable = 0u32;

        for rank in 0..13u8 {
            let drawable = state.count_drawable_rank(rank) as u32;
            if drawable > 0 {
                let sample_card = rank;
                let card_value = self.evaluate_discard_card(sample_card, hand, state);
                deck_expected_value += card_value * drawable as i32;
                total_drawable += drawable;
            }
        }

        let joker_drawable = state.count_drawable_rank(13) as u32;
        if joker_drawable > 0 {
            deck_expected_value += self.params.discard_joker_score * joker_drawable as i32;
            total_drawable += joker_drawable;
        }

        let avg_deck_value = if total_drawable > 0 {
            deck_expected_value / total_drawable as i32
        } else {
            0
        };

        if best_discard_score > avg_deck_value + self.params.discard_threshold {
            DrawSource::Discard(best_discard_card)
        } else {
            DrawSource::Deck
        }
    }

    fn should_call_zapzap(&self, state: &GameState, player_index: u8) -> bool {
        let hand = state.get_hand(player_index);

        if !can_call_zapzap(hand) {
            return false;
        }

        let hand_value = calculate_hand_value(hand);

        if hand_value == 0 {
            return true;
        }

        self.can_safely_zapzap(hand, state, player_index)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_thibot() {
        let thibot = ThibotStrategy::new();
        let mut state = GameState::new(4);
        state.hands[0] = smallvec::smallvec![0, 1, 2, 13]; // A♠, 2♠, 3♠, A♥

        let cards = thibot.select_cards(&state, 0);
        assert!(!cards.is_empty());
    }

    #[test]
    fn test_zapzap_decision() {
        let thibot = ThibotStrategy::new();
        let mut state = GameState::new(4);

        // Setup opponents with many cards (low risk)
        state.hands[1] = smallvec::smallvec![0, 1, 2, 3, 4];
        state.hands[2] = smallvec::smallvec![0, 1, 2, 3, 4];
        state.hands[3] = smallvec::smallvec![0, 1, 2, 3, 4];

        // Hand with value 0 - always zapzap
        state.hands[0] = smallvec::smallvec![52, 53];
        assert!(thibot.should_call_zapzap(&state, 0));

        // Hand with value 3 - should zapzap when opponents have many cards
        state.hands[0] = smallvec::smallvec![0, 1]; // A + 2 = 3
        assert!(thibot.should_call_zapzap(&state, 0));

        // Hand with value > 5 - can't zapzap
        state.hands[0] = smallvec::smallvec![10, 11]; // J + Q = 23
        assert!(!thibot.should_call_zapzap(&state, 0));
    }

    #[test]
    fn test_draw_source() {
        let thibot = ThibotStrategy::new();
        let mut state = GameState::new(4);

        // No discard available - must draw from deck
        state.hands[0] = smallvec::smallvec![0, 1];
        assert!(matches!(thibot.decide_draw_source(&state, 0), DrawSource::Deck));

        // Discard has ace that would complete pair
        state.hands[0] = smallvec::smallvec![0]; // A♠
        state.last_cards_played = smallvec::smallvec![13]; // A♥
        // Should prefer discard (completes pair)
        assert!(matches!(
            thibot.decide_draw_source(&state, 0),
            DrawSource::Discard(13)
        ));
    }

    #[test]
    fn test_defensive_mode() {
        let thibot = ThibotStrategy::new();
        let mut state = GameState::new(4);

        // Set opponent to have only 2 cards (close to zapzap)
        state.hands[1] = smallvec::smallvec![0, 1];

        // Our hand: K♠, K♥, A♠ (should play KK for max points in defensive mode)
        state.hands[0] = smallvec::smallvec![12, 25, 0]; // K♠, K♥, A♠

        let cards = thibot.select_cards(&state, 0);
        assert!(!cards.is_empty());

        // Should play the kings (24 points) not the ace (1 point)
        assert!(cards.contains(&12) || cards.contains(&25));
    }
}
