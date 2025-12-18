//! DRLStrategy - Bot strategy using FastDQN for action selection
//!
//! Uses the optimized lightweight neural network for inference during game simulation.
//! Supports epsilon-greedy exploration and weight synchronization.
//!
//! ## Human Strategy Integration (based on 350 action analysis):
//! - PRESERVE_COMBOS: Play singles 67% of time, keep pairs/sequences for later
//! - CONSERVATIVE_ZAPZAP: 93% success rate, prefer hand values 3-4
//! - OPPONENT_AWARENESS: Pressure when opponents have ≤3 cards
//!
//! FastDQN is ~14x faster than LightweightDQN (2.3µs vs 32µs per inference).

use super::BotStrategy;
use crate::card_analyzer;
use crate::fast_dqn::{DecisionType, FastDQN};
use crate::feature_extractor::{FeatureExtractor, FEATURE_DIM};
use crate::game_state::GameState;
use smallvec::SmallVec;

/// DRL bot strategy using neural network for decisions
pub struct DRLStrategy {
    /// Neural network for Q-value prediction (optimized for speed)
    dqn: FastDQN,
    /// Exploration rate (0 = greedy, 1 = random)
    epsilon: f32,
    /// Player index (for feature extraction)
    player_index: u8,
    /// Pre-allocated feature buffer to avoid allocations
    features_buf: [f32; FEATURE_DIM],
}

impl DRLStrategy {
    /// Create new DRL strategy with random network weights
    pub fn new(player_index: u8) -> Self {
        Self {
            dqn: FastDQN::new(),
            epsilon: 0.1, // Default 10% exploration
            player_index,
            features_buf: [0.0; FEATURE_DIM],
        }
    }

    /// Create with specific epsilon value
    pub fn with_epsilon(player_index: u8, epsilon: f32) -> Self {
        Self {
            dqn: FastDQN::new(),
            epsilon,
            player_index,
            features_buf: [0.0; FEATURE_DIM],
        }
    }

    /// Create with seed for reproducibility
    pub fn with_seed(player_index: u8, seed: u64) -> Self {
        Self {
            dqn: FastDQN::with_seed(seed),
            epsilon: 0.1,
            player_index,
            features_buf: [0.0; FEATURE_DIM],
        }
    }

    /// Set exploration rate
    pub fn set_epsilon(&mut self, epsilon: f32) {
        self.epsilon = epsilon.clamp(0.0, 1.0);
    }

    /// Get current epsilon
    pub fn epsilon(&self) -> f32 {
        self.epsilon
    }

    /// Set player index
    pub fn set_player_index(&mut self, index: u8) {
        self.player_index = index;
    }

    /// Get reference to internal DQN
    pub fn dqn(&self) -> &FastDQN {
        &self.dqn
    }

    /// Get mutable reference to internal DQN
    pub fn dqn_mut(&mut self) -> &mut FastDQN {
        &mut self.dqn
    }

    /// Sync weights from flat vector (from training network)
    pub fn set_weights_flat(&mut self, weights: &[f32]) {
        self.dqn.set_weights_flat(weights);
    }

    /// Get weights as flat vector (for serialization)
    pub fn get_weights_flat(&self) -> Vec<f32> {
        self.dqn.get_weights_flat()
    }

    /// Extract features into pre-allocated buffer
    #[inline]
    fn extract_features(&mut self, state: &GameState) -> &[f32; FEATURE_DIM] {
        self.features_buf = FeatureExtractor::extract(state, self.player_index);
        &self.features_buf
    }

    /// Extract hand size features into pre-allocated buffer
    #[inline]
    fn extract_hand_size_features(&mut self, active_player_count: u8, is_golden_score: bool, my_score: u16) -> &[f32; FEATURE_DIM] {
        self.features_buf = FeatureExtractor::extract_hand_size_features(
            active_player_count,
            is_golden_score,
            my_score,
        );
        &self.features_buf
    }

    /// Convert DQN play type action to actual card play
    ///
    /// Strategic Action Space (5 actions) - Based on human strategy analysis:
    /// 0: HUMAN_DEFAULT - Singles (67%) with context-aware combos when needed
    /// 1: PRESERVE_COMBOS - Play singles, save pairs/sequences for later
    /// 2: BURN_HIGH - Prioritize removing high-value cards (when hand > 20)
    /// 3: AGGRESSIVE_COMBO - Use combos to pressure opponents close to ZapZap
    /// 4: OPTIMAL - Minimize remaining hand value (HardBot baseline)
    fn action_to_play(&self, action: usize, hand: &[u8], state: &GameState) -> Option<SmallVec<[u8; 8]>> {
        let valid_plays = card_analyzer::find_all_valid_plays(hand);
        if valid_plays.is_empty() {
            return None;
        }

        match action {
            0 => self.find_human_default_play(&valid_plays, hand, state),
            1 => self.find_preserve_combos_play(&valid_plays, hand),
            2 => self.find_burn_high_play(&valid_plays, hand),
            3 => self.find_aggressive_combo_play(&valid_plays, hand),
            4 => self.find_optimal_play(&valid_plays, hand),
            _ => self.find_human_default_play(&valid_plays, hand, state),
        }
    }

    /// Action 0: HUMAN_DEFAULT - Mimic human play patterns based on deep analysis
    ///
    /// KEY INSIGHT: Can PRESERVE as long as opponents can't ZapZap!
    /// Use card tracking to know if opponent has high cards (>5 points = can't ZapZap).
    ///
    /// Decision factors:
    /// 1. Can opponent ZapZap? (hand size + tracked card values)
    /// 2. If opponent CAN'T ZapZap (tracked value >5) -> PRESERVE regardless of hand size
    /// 3. If opponent MIGHT ZapZap -> adjust based on hand size
    ///
    /// MULTI-TURN PLANNING:
    /// Example: Hand K♠ K♥ Q♥, last_played has J♥
    /// -> Play K♠ (single), take J♥, next turn play K♥ Q♥ J♥ sequence
    fn find_human_default_play(&self, plays: &[SmallVec<[u8; 8]>], hand: &[u8], state: &GameState) -> Option<SmallVec<[u8; 8]>> {
        // Analyze ALL opponents to find the most dangerous one
        let mut min_opponent_hand_size = 10usize;
        let mut min_opponent_estimated_value = u16::MAX;
        let mut opponent_can_zapzap = false;

        for (i, h) in state.hands.iter().enumerate() {
            if i == self.player_index as usize || h.is_empty() {
                continue;
            }

            let hand_size = h.len();
            if hand_size < min_opponent_hand_size {
                min_opponent_hand_size = hand_size;
            }

            // Use card tracking to estimate opponent's MINIMUM hand value
            // If they took a 6 and never played it, they have at least 6 points
            let estimated_min = state.estimate_min_hand_value(i as u8);
            if estimated_min < min_opponent_estimated_value {
                min_opponent_estimated_value = estimated_min;
            }

            // Can this opponent ZapZap? (hand size small AND we don't know they have >5 points)
            if hand_size <= 3 && estimated_min <= 5 {
                opponent_can_zapzap = true;
            }
        }

        // KEY INSIGHT: If we KNOW opponent has >5 points, they CAN'T ZapZap!
        // We can safely PRESERVE combos regardless of their hand size
        let opponent_definitely_cant_zapzap = min_opponent_estimated_value > 5;

        // If opponent definitely can't ZapZap -> PRESERVE (play singles, build combos)
        if opponent_definitely_cant_zapzap {
            // Use multi-turn planning since we have time
            if !state.last_cards_played.is_empty() {
                if let Some((sacrifice_card, _take_card, future_value)) =
                    card_analyzer::find_setup_play(hand, &state.last_cards_played)
                {
                    if future_value >= 20 {
                        let mut play: SmallVec<[u8; 8]> = SmallVec::new();
                        play.push(sacrifice_card);
                        return Some(play);
                    }
                }
            }
            return self.find_preserve_combos_play_counted(plays, hand, state);
        }

        // From here: opponent MIGHT be able to ZapZap
        // Decision based on hand size + urgency

        // 1. If opponent has 1 card AND might ZapZap - RACE! (44% combos)
        if min_opponent_hand_size <= 1 && opponent_can_zapzap {
            return self.find_aggressive_combo_play(plays, hand);
        }

        // 2. If opponent has 2 cards AND might ZapZap - CONSERVATIVE (75% singles)
        // Preserve combos for counteract potential
        if min_opponent_hand_size == 2 && opponent_can_zapzap {
            return self.find_preserve_combos_play_counted(plays, hand, state);
        }

        // 3. If opponent has 3 cards AND might ZapZap - START BURNING (42% combos)
        if min_opponent_hand_size == 3 && opponent_can_zapzap {
            return self.find_burn_high_play(plays, hand);
        }

        // 4. Opponent has 4+ cards OR we're not sure if they can ZapZap
        // Use multi-turn planning if available
        if !state.last_cards_played.is_empty() {
            if let Some((sacrifice_card, _take_card, future_value)) =
                card_analyzer::find_setup_play(hand, &state.last_cards_played)
            {
                if future_value >= 20 {
                    let mut play: SmallVec<[u8; 8]> = SmallVec::new();
                    play.push(sacrifice_card);
                    return Some(play);
                }
            }
        }

        // Default: PRESERVE combos with card counting (play smart singles)
        self.find_preserve_combos_play_counted(plays, hand, state)
    }

    /// Action 0: OPTIMAL - Minimize remaining hand value (same as HardBot)
    /// Best general strategy, baseline for comparison
    fn find_optimal_play(&self, plays: &[SmallVec<[u8; 8]>], hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
        plays
            .iter()
            .max_by_key(|play| {
                let remaining: SmallVec<[u8; 10]> = hand
                    .iter()
                    .filter(|id| !play.contains(id))
                    .copied()
                    .collect();
                let remaining_value = card_analyzer::calculate_hand_value(&remaining) as i32;
                let play_size = play.len() as i32;
                -remaining_value + (play_size / 2)
            })
            .cloned()
    }

    /// Action 1: PRESERVE_COMBOS - Play single cards, save multi-card combos
    /// Strategic use: When close to ZapZap, save combos to catch opponents
    /// or when you want to keep options open for future turns
    fn find_preserve_combos_play(&self, plays: &[SmallVec<[u8; 8]>], hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
        // Prefer single card plays to preserve combos
        let single_plays: Vec<_> = plays.iter().filter(|p| p.len() == 1).collect();

        if !single_plays.is_empty() {
            // Among singles, pick the one that leaves best remaining value
            return single_plays
                .into_iter()
                .max_by_key(|play| {
                    let remaining: SmallVec<[u8; 10]> = hand
                        .iter()
                        .filter(|id| !play.contains(id))
                        .copied()
                        .collect();
                    let remaining_value = card_analyzer::calculate_hand_value(&remaining) as i32;
                    // Prefer higher value singles (get rid of bad cards while keeping combos)
                    let card_value = card_analyzer::get_card_points(play[0]) as i32;
                    -remaining_value + card_value
                })
                .cloned();
        }

        // No singles available, fall back to smallest combo
        plays
            .iter()
            .min_by_key(|play| play.len())
            .cloned()
    }

    /// Action 1 WITH CARD COUNTING: Play singles smartly based on dead ranks
    /// Example: If 3 jacks are in discard, discard the 4th jack (no pair possible)
    fn find_preserve_combos_play_counted(&self, plays: &[SmallVec<[u8; 8]>], hand: &[u8], state: &GameState) -> Option<SmallVec<[u8; 8]>> {
        // Prefer single card plays to preserve combos
        let single_plays: Vec<_> = plays.iter().filter(|p| p.len() == 1).collect();

        if !single_plays.is_empty() {
            // Among singles, pick the WORST card to keep (lowest keep score)
            return single_plays
                .into_iter()
                .min_by_key(|play| {
                    let card = play[0];
                    if card_analyzer::is_joker(card) {
                        return 10000i32; // Never discard jokers
                    }
                    let rank = card_analyzer::get_rank(card);
                    let drawable = state.count_drawable_rank(rank);
                    card_analyzer::card_keep_score(card, hand, drawable)
                })
                .cloned();
        }

        // No singles available, fall back to smallest combo
        plays
            .iter()
            .min_by_key(|play| play.len())
            .cloned()
    }

    /// Action 2: BURN_HIGH - Prioritize removing high-value cards
    /// Strategic use: When at high score (risk of elimination), get rid of
    /// dangerous cards even if it's not optimal for combos
    fn find_burn_high_play(&self, plays: &[SmallVec<[u8; 8]>], hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
        plays
            .iter()
            .max_by_key(|play| {
                // Score by total points removed
                let points_removed: i32 = play
                    .iter()
                    .map(|&c| card_analyzer::get_card_points(c) as i32)
                    .sum();

                // Also consider remaining hand value
                let remaining: SmallVec<[u8; 10]> = hand
                    .iter()
                    .filter(|id| !play.contains(id))
                    .copied()
                    .collect();
                let remaining_value = card_analyzer::calculate_hand_value(&remaining) as i32;

                // Heavy weight on points removed, but also care about remaining
                points_removed * 3 - remaining_value
            })
            .cloned()
    }

    /// Action 3: AGGRESSIVE_COMBO - Use multi-card plays to pressure opponents
    /// Strategic use: When opponents have small hands (≤3 cards), reduce your own
    /// hand size quickly to either ZapZap first or minimize loss if they ZapZap
    fn find_aggressive_combo_play(&self, plays: &[SmallVec<[u8; 8]>], hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
        // Prefer larger combos to reduce hand size quickly
        let multi_card_plays: Vec<_> = plays.iter().filter(|p| p.len() > 1).collect();

        if !multi_card_plays.is_empty() {
            // Among multi-card plays, prefer:
            // 1. Larger plays (reduce hand size faster)
            // 2. Higher value removed (reduce risk)
            return multi_card_plays
                .into_iter()
                .max_by_key(|play| {
                    let remaining: SmallVec<[u8; 10]> = hand
                        .iter()
                        .filter(|id| !play.contains(id))
                        .copied()
                        .collect();
                    let remaining_value = card_analyzer::calculate_hand_value(&remaining) as i32;
                    let play_size = play.len() as i32;
                    // Heavy weight on play size (reduce hand quickly) + value reduction
                    play_size * 10 - remaining_value
                })
                .cloned();
        }

        // No multi-card plays available, use optimal single
        self.find_optimal_play(plays, hand)
    }
}

impl BotStrategy for DRLStrategy {
    fn select_play(&self, hand: &[u8], state: &GameState) -> Option<SmallVec<[u8; 8]>> {
        if hand.is_empty() {
            return None;
        }

        // Use HUMAN_DEFAULT strategy (action 0) as the primary play style
        // This incorporates: singles preference, burn high when >20, pressure when opponent <=3
        self.find_human_default_play(
            &card_analyzer::find_all_valid_plays(hand),
            hand,
            state
        )
    }

    fn should_zapzap(&self, hand: &[u8], state: &GameState) -> bool {
        // Use conservative ZapZap strategy (93% success rate target)
        self.should_zapzap_conservative(hand, state)
    }

    fn select_draw_source(&self, hand: &[u8], last_cards_played: &[u8], _state: &GameState) -> bool {
        if last_cards_played.is_empty() {
            return true; // Must draw from deck
        }

        // Deep analysis revealed:
        // - 100% take jokers when available (critical for ZapZap)
        // - 87% take low cards (<=3) when available
        // - Take cards that complete sequences/pairs (multi-turn planning)
        // - 82% draw from deck when only high cards available

        // Priority 1: ALWAYS take jokers (100% in human data)
        let has_joker = last_cards_played.iter().any(|&c| card_analyzer::is_joker(c));
        if has_joker {
            return false; // Take from played - jokers are critical
        }

        // Priority 2: Take low cards (A, 2, 3) - 87% in human data
        let has_low_card = last_cards_played.iter().any(|&c| {
            !card_analyzer::is_joker(c) && card_analyzer::get_card_points(c) <= 3
        });
        if has_low_card {
            return false; // Take from played - low cards help reach ZapZap
        }

        // Priority 3: MULTI-TURN PLANNING - Take card that completes a sequence
        // Example: Hand has Q♥, K♥ and J♥ is available -> take J♥ for future sequence
        for &card in last_cards_played {
            if card_analyzer::would_complete_sequence(hand, card) {
                return false; // Take from played - enables future combo
            }
        }

        // Priority 4: Take card that completes a pair (for 3+ card same rank play)
        for &card in last_cards_played {
            if card_analyzer::would_complete_pair(hand, card) {
                // Only take if it would make a 3+ card combo (pair already exists)
                let card_rank = card_analyzer::get_rank(card);
                let same_rank_count = hand.iter()
                    .filter(|&&c| !card_analyzer::is_joker(c) && card_analyzer::get_rank(c) == card_rank)
                    .count();
                if same_rank_count >= 2 {
                    return false; // Take from played - makes 3+ card set
                }
            }
        }

        // Priority 5: Draw from deck when only high cards available (82% in human data)
        true
    }

    fn select_hand_size(&self, active_player_count: u8, is_golden_score: bool) -> u8 {
        let features = FeatureExtractor::extract_hand_size_features(
            active_player_count,
            is_golden_score,
            50,
        );

        let mut dqn_clone = self.dqn.clone();
        let action = dqn_clone.greedy_action(&features, DecisionType::HandSize);
        let hand_size = (action + 4) as u8;
        hand_size.clamp(4, 10)
    }
}

/// Mutable version for use during training (supports exploration)
impl DRLStrategy {
    /// Select play with epsilon-greedy exploration
    pub fn select_play_mut(&mut self, hand: &[u8], state: &GameState) -> Option<SmallVec<[u8; 8]>> {
        if hand.is_empty() {
            return None;
        }

        self.extract_features(state);
        let action = self.dqn.select_action(&self.features_buf, DecisionType::PlayType, self.epsilon);
        self.action_to_play(action, hand, state)
    }

    /// Select play with epsilon-greedy exploration, returning both the play and the action chosen
    /// This is important for correct transition recording - we need the actual action, not a classification
    pub fn select_play_with_action(&mut self, hand: &[u8], state: &GameState) -> (Option<SmallVec<[u8; 8]>>, u8) {
        if hand.is_empty() {
            return (None, 0);
        }

        self.extract_features(state);
        let action = self.dqn.select_action(&self.features_buf, DecisionType::PlayType, self.epsilon);
        let play = self.action_to_play(action, hand, state);
        (play, action as u8)
    }

    /// Select play ALWAYS using optimal action (action=0)
    /// This is for testing if forcing optimal play improves winrate
    pub fn select_play_optimal(&mut self, hand: &[u8], state: &GameState) -> (Option<SmallVec<[u8; 8]>>, u8) {
        if hand.is_empty() {
            return (None, 0);
        }
        // Always use action 0 (optimal) - same as hard bot
        let play = self.action_to_play(0, hand, state);
        (play, 0)
    }

    /// Should zapzap with epsilon-greedy exploration
    /// Deep analysis: 50% fail when opponent has 1 card, 100% success otherwise
    pub fn should_zapzap_mut(&mut self, hand: &[u8], state: &GameState) -> bool {
        let hand_value = card_analyzer::calculate_hand_value(hand);
        if hand_value > 5 {
            return false;
        }

        let min_opponent_hand_size = state.hands.iter()
            .enumerate()
            .filter(|(i, h)| *i != self.player_index as usize && !h.is_empty())
            .map(|(_, h)| h.len())
            .min()
            .unwrap_or(10);

        // Deep analysis: 50% fail when opponent has 1 card - AVOID unless very low
        if min_opponent_hand_size <= 1 {
            // Only ZapZap at 0-1 points when opponent is also about to ZapZap
            if hand_value <= 1 {
                return true; // Safe
            }
            // For hand values 2-5, let neural network decide with exploration
            self.extract_features(state);
            return self.dqn.select_action(&self.features_buf, DecisionType::ZapZap, self.epsilon) == 1;
        }

        // 100% success when opponent has 2+ cards
        let confidence_threshold = if min_opponent_hand_size == 2 {
            3
        } else if min_opponent_hand_size == 3 {
            4
        } else {
            4
        };

        if (hand_value as u16) <= confidence_threshold {
            return true; // High confidence ZapZap
        }

        // For edge cases (hand value 5), let neural network decide
        self.extract_features(state);
        self.dqn.select_action(&self.features_buf, DecisionType::ZapZap, self.epsilon) == 1
    }

    /// Conservative ZapZap check (no exploration, used in greedy evaluation)
    ///
    /// Updated analysis (627 actions, 27 ZapZaps):
    /// - opponent 1 card: 25% success (1/4) - NEVER DO THIS!
    /// - opponent 2 cards: 67% success (4/6) - risky
    /// - opponent 3+ cards: 100% success (17/17) - safe
    ///
    /// By hand value:
    /// - 0-2 points: 100% success
    /// - 3 points: 67% success
    /// - 4-5 points: 80-83% success
    ///
    /// Enhanced with card tracking for opponent hand prediction
    pub fn should_zapzap_conservative(&self, hand: &[u8], state: &GameState) -> bool {
        let hand_value = card_analyzer::calculate_hand_value(hand);
        if hand_value > 5 {
            return false;
        }

        let mut min_opponent_hand_size = 10;
        let mut min_opponent_estimated_value = u16::MAX;

        for (i, h) in state.hands.iter().enumerate() {
            if i != self.player_index as usize && !h.is_empty() {
                let hand_size = h.len();
                if hand_size < min_opponent_hand_size {
                    min_opponent_hand_size = hand_size;
                }

                // Use card tracking to estimate opponent's minimum hand value
                let estimated_min = state.estimate_min_hand_value(i as u8);
                if estimated_min < min_opponent_estimated_value {
                    min_opponent_estimated_value = estimated_min;
                }
            }
        }

        if min_opponent_hand_size == 10 {
            min_opponent_hand_size = 5; // Fallback
        }

        // CARD TRACKING: If we tracked opponent's cards, use that info
        if min_opponent_estimated_value != u16::MAX && min_opponent_estimated_value > 0 {
            // We know opponent has at least this many points
            if min_opponent_estimated_value > hand_value as u16 {
                return true; // High confidence - we know they have more points
            }
            // If their estimated minimum is lower or equal, be more cautious
            if min_opponent_estimated_value <= hand_value as u16 && min_opponent_hand_size <= 2 {
                return false; // They likely have a winning hand
            }
        }

        // CRITICAL: 75% FAIL when opponent has 1 card (only 25% success!)
        // NEVER ZapZap unless we have 0 points
        if min_opponent_hand_size <= 1 {
            return hand_value == 0; // Only at exactly 0 points!
        }

        // 67% success when opponent has 2 cards - still risky
        // Only ZapZap at 0-2 points (100% success range)
        if min_opponent_hand_size == 2 {
            return hand_value <= 2;
        }

        // 100% success when opponent has 3+ cards
        // More aggressive thresholds
        let confidence_threshold = if min_opponent_hand_size == 3 {
            4 // 100% success at 3+ cards
        } else {
            5 // Safe at 4+ cards
        };

        (hand_value as u16) <= confidence_threshold
    }

    /// Select draw source with epsilon-greedy exploration
    pub fn select_draw_source_mut(&mut self, _hand: &[u8], last_cards_played: &[u8], state: &GameState) -> bool {
        if last_cards_played.is_empty() {
            return true;
        }

        self.extract_features(state);
        let action = self.dqn.select_action(&self.features_buf, DecisionType::DrawSource, self.epsilon);
        action == 0
    }

    /// Select hand size with epsilon-greedy exploration
    pub fn select_hand_size_mut(&mut self, active_player_count: u8, is_golden_score: bool, my_score: u16) -> u8 {
        self.extract_hand_size_features(active_player_count, is_golden_score, my_score);
        let action = self.dqn.select_action(&self.features_buf, DecisionType::HandSize, self.epsilon);
        let hand_size = (action + 4) as u8;
        hand_size.clamp(4, 10)
    }

    /// Get the action taken for a decision (for transition recording)
    pub fn get_action(&mut self, features: &[f32; FEATURE_DIM], decision_type: DecisionType) -> usize {
        self.dqn.select_action(features, decision_type, self.epsilon)
    }

    /// Get greedy action (no exploration)
    pub fn get_greedy_action(&mut self, features: &[f32; FEATURE_DIM], decision_type: DecisionType) -> usize {
        self.dqn.greedy_action(features, decision_type)
    }
}

impl Default for DRLStrategy {
    fn default() -> Self {
        Self::new(0)
    }
}

impl Clone for DRLStrategy {
    fn clone(&self) -> Self {
        Self {
            dqn: self.dqn.clone(),
            epsilon: self.epsilon,
            player_index: self.player_index,
            features_buf: [0.0; FEATURE_DIM],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new() {
        let strategy = DRLStrategy::new(0);
        assert_eq!(strategy.player_index, 0);
        assert!((strategy.epsilon - 0.1).abs() < 0.001);
    }

    #[test]
    fn test_with_epsilon() {
        let strategy = DRLStrategy::with_epsilon(1, 0.5);
        assert_eq!(strategy.player_index, 1);
        assert!((strategy.epsilon - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_set_epsilon() {
        let mut strategy = DRLStrategy::new(0);
        strategy.set_epsilon(0.3);
        assert!((strategy.epsilon - 0.3).abs() < 0.001);

        strategy.set_epsilon(1.5);
        assert!((strategy.epsilon - 1.0).abs() < 0.001);

        strategy.set_epsilon(-0.5);
        assert!(strategy.epsilon.abs() < 0.001);
    }

    #[test]
    fn test_select_play() {
        let strategy = DRLStrategy::new(0);
        let mut state = GameState::new(4);

        state.hands[0].push(0);  // A♠
        state.hands[0].push(13); // A♥
        state.hands[0].push(5);  // 6♠

        let hand = &state.hands[0].clone();
        let play = strategy.select_play(hand, &state);

        assert!(play.is_some());
        let play = play.unwrap();
        assert!(!play.is_empty());
    }

    #[test]
    fn test_should_zapzap() {
        let strategy = DRLStrategy::new(0);
        let state = GameState::new(4);

        let low_hand = vec![52, 53];  // Jokers = 0 points
        let _ = strategy.should_zapzap(&low_hand, &state);

        let high_hand = vec![10, 11, 12]; // J, Q, K = 36 points
        assert!(!strategy.should_zapzap(&high_hand, &state));
    }

    #[test]
    fn test_select_draw_source() {
        let strategy = DRLStrategy::new(0);
        let state = GameState::new(4);
        let hand = vec![0, 1, 2];

        assert!(strategy.select_draw_source(&hand, &[], &state));
        let _ = strategy.select_draw_source(&hand, &[5, 6], &state);
    }

    #[test]
    fn test_select_hand_size() {
        let strategy = DRLStrategy::new(0);

        let size = strategy.select_hand_size(4, false);
        assert!(size >= 4 && size <= 10);

        let gs_size = strategy.select_hand_size(2, true);
        assert!(gs_size >= 4 && gs_size <= 10);
    }

    #[test]
    fn test_mutable_methods() {
        let mut strategy = DRLStrategy::with_seed(0, 42);
        let mut state = GameState::new(4);
        state.hands[0].push(0);
        state.hands[0].push(13);
        state.hands[0].push(5);

        let hand = &state.hands[0].clone();

        let play = strategy.select_play_mut(hand, &state);
        assert!(play.is_some());

        let _ = strategy.should_zapzap_mut(&[52], &state);
        let _ = strategy.select_draw_source_mut(hand, &[10], &state);

        let size = strategy.select_hand_size_mut(4, false, 50);
        assert!(size >= 4 && size <= 10);
    }

    #[test]
    fn test_clone() {
        let strategy = DRLStrategy::with_epsilon(1, 0.3);
        let cloned = strategy.clone();

        assert_eq!(cloned.player_index, strategy.player_index);
        assert!((cloned.epsilon - strategy.epsilon).abs() < 0.001);
    }

    #[test]
    fn test_weights_serialization() {
        let strategy1 = DRLStrategy::new(0);
        let weights = strategy1.get_weights_flat();
        assert!(!weights.is_empty());

        let mut strategy2 = DRLStrategy::with_seed(1, 999);
        strategy2.set_weights_flat(&weights);

        // After setting weights, should produce same outputs
        let input = [0.5f32; FEATURE_DIM];
        let action1 = strategy1.dqn.clone().greedy_action(&input, DecisionType::PlayType);
        let mut dqn2 = strategy2.dqn.clone();
        let action2 = dqn2.greedy_action(&input, DecisionType::PlayType);

        assert_eq!(action1, action2, "Weights not properly transferred");
    }
}
