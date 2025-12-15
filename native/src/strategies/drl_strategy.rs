//! DRLStrategy - Bot strategy using FastDQN for action selection
//!
//! Uses the optimized lightweight neural network for inference during game simulation.
//! Supports epsilon-greedy exploration and weight synchronization.
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
    fn action_to_play(&self, action: usize, hand: &[u8], _state: &GameState) -> Option<SmallVec<[u8; 8]>> {
        let valid_plays = card_analyzer::find_all_valid_plays(hand);
        if valid_plays.is_empty() {
            return None;
        }

        // Action mapping:
        // 0: optimal - best by remaining hand value
        // 1: single_high - play highest single card
        // 2: multi_high - play multi-card combo removing most value
        // 3: avoid_joker - avoid playing jokers if possible
        // 4: use_joker_combo - use joker in combos if possible

        match action {
            0 => self.find_optimal_play(&valid_plays, hand),
            1 => self.find_single_high_play(&valid_plays, hand),
            2 => self.find_multi_high_play(&valid_plays, hand),
            3 => self.find_avoid_joker_play(&valid_plays, hand),
            4 => self.find_joker_combo_play(&valid_plays, hand),
            _ => self.find_optimal_play(&valid_plays, hand),
        }
    }

    fn find_optimal_play(&self, plays: &[SmallVec<[u8; 8]>], hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
        plays
            .iter()
            .min_by_key(|play| {
                let remaining: SmallVec<[u8; 10]> = hand
                    .iter()
                    .filter(|id| !play.contains(id))
                    .copied()
                    .collect();
                card_analyzer::calculate_hand_value(&remaining)
            })
            .cloned()
    }

    fn find_single_high_play(&self, plays: &[SmallVec<[u8; 8]>], _hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
        let single_plays: Vec<_> = plays.iter().filter(|p| p.len() == 1).collect();
        if !single_plays.is_empty() {
            return single_plays
                .into_iter()
                .max_by_key(|play| card_analyzer::get_card_points(play[0]))
                .cloned();
        }
        plays
            .iter()
            .max_by_key(|play| play.iter().map(|&c| card_analyzer::get_card_points(c) as u32).sum::<u32>())
            .cloned()
    }

    fn find_multi_high_play(&self, plays: &[SmallVec<[u8; 8]>], _hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
        let multi_plays: Vec<_> = plays.iter().filter(|p| p.len() > 1).collect();
        if !multi_plays.is_empty() {
            return multi_plays
                .into_iter()
                .max_by_key(|play| play.iter().map(|&c| card_analyzer::get_card_points(c) as u32).sum::<u32>())
                .cloned();
        }
        plays
            .iter()
            .max_by_key(|play| play.iter().map(|&c| card_analyzer::get_card_points(c) as u32).sum::<u32>())
            .cloned()
    }

    fn find_avoid_joker_play(&self, plays: &[SmallVec<[u8; 8]>], hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
        let no_joker_plays: Vec<_> = plays
            .iter()
            .filter(|p| !p.iter().any(|&c| card_analyzer::is_joker(c)))
            .collect();
        if !no_joker_plays.is_empty() {
            return no_joker_plays
                .into_iter()
                .min_by_key(|play| {
                    let remaining: SmallVec<[u8; 10]> = hand
                        .iter()
                        .filter(|id| !play.contains(id))
                        .copied()
                        .collect();
                    card_analyzer::calculate_hand_value(&remaining)
                })
                .cloned();
        }
        self.find_optimal_play(plays, hand)
    }

    fn find_joker_combo_play(&self, plays: &[SmallVec<[u8; 8]>], hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
        let joker_plays: Vec<_> = plays
            .iter()
            .filter(|p| p.iter().any(|&c| card_analyzer::is_joker(c)))
            .collect();
        if !joker_plays.is_empty() {
            return joker_plays
                .into_iter()
                .min_by_key(|play| {
                    let remaining: SmallVec<[u8; 10]> = hand
                        .iter()
                        .filter(|id| !play.contains(id))
                        .copied()
                        .collect();
                    card_analyzer::calculate_hand_value(&remaining)
                })
                .cloned();
        }
        self.find_optimal_play(plays, hand)
    }
}

impl BotStrategy for DRLStrategy {
    fn select_play(&self, hand: &[u8], state: &GameState) -> Option<SmallVec<[u8; 8]>> {
        if hand.is_empty() {
            return None;
        }

        // Extract features
        let features = FeatureExtractor::extract(state, self.player_index);

        // Get greedy action (clone DQN to get mutable access)
        let mut dqn_clone = self.dqn.clone();
        let action = dqn_clone.greedy_action(&features, DecisionType::PlayType);

        // Convert action to actual play
        self.action_to_play(action, hand, state)
    }

    fn should_zapzap(&self, hand: &[u8], state: &GameState) -> bool {
        let hand_value = card_analyzer::calculate_hand_value(hand);
        if hand_value > 5 {
            return false;
        }

        let features = FeatureExtractor::extract(state, self.player_index);
        let mut dqn_clone = self.dqn.clone();
        let action = dqn_clone.greedy_action(&features, DecisionType::ZapZap);
        action == 1
    }

    fn select_draw_source(&self, hand: &[u8], last_cards_played: &[u8], state: &GameState) -> bool {
        if last_cards_played.is_empty() {
            return true;
        }

        let features = FeatureExtractor::extract(state, self.player_index);
        let mut dqn_clone = self.dqn.clone();
        let action = dqn_clone.greedy_action(&features, DecisionType::DrawSource);
        action == 0
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

    /// Should zapzap with epsilon-greedy exploration
    pub fn should_zapzap_mut(&mut self, hand: &[u8], state: &GameState) -> bool {
        let hand_value = card_analyzer::calculate_hand_value(hand);
        if hand_value > 5 {
            return false;
        }

        self.extract_features(state);
        let action = self.dqn.select_action(&self.features_buf, DecisionType::ZapZap, self.epsilon);
        action == 1
    }

    /// Select draw source with epsilon-greedy exploration
    pub fn select_draw_source_mut(&mut self, hand: &[u8], last_cards_played: &[u8], state: &GameState) -> bool {
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
