//! DRLStrategy - Bot strategy using LightweightDQN for action selection
//!
//! Uses the lightweight neural network for inference during game simulation.
//! Supports epsilon-greedy exploration and weight synchronization.

use super::BotStrategy;
use crate::card_analyzer;
use crate::feature_extractor::FeatureExtractor;
use crate::game_state::GameState;
use crate::lightweight_dqn::{DecisionType, LightweightDQN};
use smallvec::SmallVec;

/// DRL bot strategy using neural network for decisions
pub struct DRLStrategy {
    /// Neural network for Q-value prediction
    dqn: LightweightDQN,
    /// Exploration rate (0 = greedy, 1 = random)
    epsilon: f32,
    /// Player index (for feature extraction)
    player_index: u8,
}

impl DRLStrategy {
    /// Create new DRL strategy with random network weights
    pub fn new(player_index: u8) -> Self {
        Self {
            dqn: LightweightDQN::new(),
            epsilon: 0.1, // Default 10% exploration
            player_index,
        }
    }

    /// Create with specific epsilon value
    pub fn with_epsilon(player_index: u8, epsilon: f32) -> Self {
        Self {
            dqn: LightweightDQN::new(),
            epsilon,
            player_index,
        }
    }

    /// Create with seed for reproducibility
    pub fn with_seed(player_index: u8, seed: u64) -> Self {
        Self {
            dqn: LightweightDQN::with_seed(seed),
            epsilon: 0.1,
            player_index,
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
    pub fn dqn(&self) -> &LightweightDQN {
        &self.dqn
    }

    /// Get mutable reference to internal DQN
    pub fn dqn_mut(&mut self) -> &mut LightweightDQN {
        &mut self.dqn
    }

    /// Sync weights from flat vector (from training network)
    ///
    /// The flat weights should be in the format produced by the burn DuelingDQN
    /// network's `get_weights_flat()` method.
    pub fn set_weights_flat(&mut self, weights: &[f32]) {
        // Parse flat weights into layer structure
        // Architecture: 45 -> 256 -> 128 -> 64 -> 32 -> action_dim
        // Each layer has weights (in_dim * out_dim) + bias (out_dim)

        let layer_sizes = [(45, 256), (256, 128), (128, 64), (64, 32)];
        let action_dims = [7, 2, 5, 2]; // HandSize, ZapZap, PlayType, DrawSource

        // For now, we'll need to implement proper weight mapping
        // This is a placeholder - actual implementation depends on burn's weight format
        if weights.is_empty() {
            return;
        }

        // TODO: Implement proper weight mapping from burn DuelingDQN format
        // to LightweightDQN LayerWeights format
        // This requires understanding the exact layout of burn's serialized weights
    }

    /// Convert DQN play type action to actual card play
    fn action_to_play(&self, action: usize, hand: &[u8], state: &GameState) -> Option<SmallVec<[u8; 8]>> {
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
            0 => {
                // Optimal: minimize remaining hand value
                self.find_optimal_play(&valid_plays, hand)
            }
            1 => {
                // Single high: play highest value single card
                self.find_single_high_play(&valid_plays, hand)
            }
            2 => {
                // Multi high: prefer multi-card plays that remove most value
                self.find_multi_high_play(&valid_plays, hand)
            }
            3 => {
                // Avoid joker: prefer plays without jokers
                self.find_avoid_joker_play(&valid_plays, hand)
            }
            4 => {
                // Use joker combo: prefer plays with jokers
                self.find_joker_combo_play(&valid_plays, hand)
            }
            _ => {
                // Fallback to optimal
                self.find_optimal_play(&valid_plays, hand)
            }
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
        // Prefer single cards, pick highest value
        let single_plays: Vec<_> = plays.iter().filter(|p| p.len() == 1).collect();
        if !single_plays.is_empty() {
            return single_plays
                .into_iter()
                .max_by_key(|play| card_analyzer::get_card_points(play[0]))
                .cloned();
        }
        // Fallback to any play with highest total value
        plays
            .iter()
            .max_by_key(|play| play.iter().map(|&c| card_analyzer::get_card_points(c) as u32).sum::<u32>())
            .cloned()
    }

    fn find_multi_high_play(&self, plays: &[SmallVec<[u8; 8]>], _hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
        // Prefer multi-card plays that remove most value
        let multi_plays: Vec<_> = plays.iter().filter(|p| p.len() > 1).collect();
        if !multi_plays.is_empty() {
            return multi_plays
                .into_iter()
                .max_by_key(|play| play.iter().map(|&c| card_analyzer::get_card_points(c) as u32).sum::<u32>())
                .cloned();
        }
        // Fallback to highest single
        plays
            .iter()
            .max_by_key(|play| play.iter().map(|&c| card_analyzer::get_card_points(c) as u32).sum::<u32>())
            .cloned()
    }

    fn find_avoid_joker_play(&self, plays: &[SmallVec<[u8; 8]>], hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
        // Prefer plays without jokers
        let no_joker_plays: Vec<_> = plays
            .iter()
            .filter(|p| !p.iter().any(|&c| card_analyzer::is_joker(c)))
            .collect();
        if !no_joker_plays.is_empty() {
            // Among non-joker plays, pick optimal
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
        // Fallback to optimal
        self.find_optimal_play(plays, hand)
    }

    fn find_joker_combo_play(&self, plays: &[SmallVec<[u8; 8]>], hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
        // Prefer plays with jokers (use joker strategically)
        let joker_plays: Vec<_> = plays
            .iter()
            .filter(|p| p.iter().any(|&c| card_analyzer::is_joker(c)))
            .collect();
        if !joker_plays.is_empty() {
            // Among joker plays, pick one with best remaining value
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
        // Fallback to optimal
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

        // Get action from DQN (need mutable for epsilon-greedy RNG)
        // For trait impl, we use greedy action (epsilon handled externally)
        let action = self.dqn.greedy_action(&features, DecisionType::PlayType);

        // Convert action to actual play
        self.action_to_play(action, hand, state)
    }

    fn should_zapzap(&self, hand: &[u8], state: &GameState) -> bool {
        let hand_value = card_analyzer::calculate_hand_value(hand);

        // Can't zapzap if hand value > 5
        if hand_value > 5 {
            return false;
        }

        // Extract features
        let features = FeatureExtractor::extract(state, self.player_index);

        // Get action from DQN
        let action = self.dqn.greedy_action(&features, DecisionType::ZapZap);

        // Action 0 = don't zapzap, 1 = zapzap
        action == 1
    }

    fn select_draw_source(&self, hand: &[u8], last_cards_played: &[u8], state: &GameState) -> bool {
        if last_cards_played.is_empty() {
            return true; // Must draw from deck
        }

        // Extract features
        let features = FeatureExtractor::extract(state, self.player_index);

        // Get action from DQN
        let action = self.dqn.greedy_action(&features, DecisionType::DrawSource);

        // Action 0 = deck, 1 = discard
        action == 0
    }

    fn select_hand_size(&self, active_player_count: u8, is_golden_score: bool) -> u8 {
        // Extract features for hand size decision
        let features = FeatureExtractor::extract_hand_size_features(
            active_player_count,
            is_golden_score,
            50, // Default score estimate
        );

        // Get action from DQN
        let action = self.dqn.greedy_action(&features, DecisionType::HandSize);

        // Map action to hand size: 0-6 -> 4-10 cards
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

        let features = FeatureExtractor::extract(state, self.player_index);
        let action = self.dqn.select_action(&features, DecisionType::PlayType, self.epsilon);
        self.action_to_play(action, hand, state)
    }

    /// Should zapzap with epsilon-greedy exploration
    pub fn should_zapzap_mut(&mut self, hand: &[u8], state: &GameState) -> bool {
        let hand_value = card_analyzer::calculate_hand_value(hand);
        if hand_value > 5 {
            return false;
        }

        let features = FeatureExtractor::extract(state, self.player_index);
        let action = self.dqn.select_action(&features, DecisionType::ZapZap, self.epsilon);
        action == 1
    }

    /// Select draw source with epsilon-greedy exploration
    pub fn select_draw_source_mut(&mut self, hand: &[u8], last_cards_played: &[u8], state: &GameState) -> bool {
        if last_cards_played.is_empty() {
            return true;
        }

        let features = FeatureExtractor::extract(state, self.player_index);
        let action = self.dqn.select_action(&features, DecisionType::DrawSource, self.epsilon);
        action == 0
    }

    /// Select hand size with epsilon-greedy exploration
    pub fn select_hand_size_mut(&mut self, active_player_count: u8, is_golden_score: bool, my_score: u16) -> u8 {
        let features = FeatureExtractor::extract_hand_size_features(
            active_player_count,
            is_golden_score,
            my_score,
        );

        let action = self.dqn.select_action(&features, DecisionType::HandSize, self.epsilon);
        let hand_size = (action + 4) as u8;
        hand_size.clamp(4, 10)
    }

    /// Get the action taken for a decision (for transition recording)
    pub fn get_action(&mut self, features: &[f32], decision_type: DecisionType) -> usize {
        self.dqn.select_action(features, decision_type, self.epsilon)
    }

    /// Get greedy action (no exploration)
    pub fn get_greedy_action(&self, features: &[f32], decision_type: DecisionType) -> usize {
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

        // Test clamping
        strategy.set_epsilon(1.5);
        assert!((strategy.epsilon - 1.0).abs() < 0.001);

        strategy.set_epsilon(-0.5);
        assert!(strategy.epsilon.abs() < 0.001);
    }

    #[test]
    fn test_select_play() {
        let strategy = DRLStrategy::new(0);
        let mut state = GameState::new(4);

        // Give player 0 some cards
        state.hands[0].push(0); // A♠
        state.hands[0].push(13); // A♥
        state.hands[0].push(5); // 6♠

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

        // Hand with value 0 (jokers)
        let low_hand = vec![52, 53];
        // This should return true (can zapzap) - actual decision depends on network
        let _ = strategy.should_zapzap(&low_hand, &state);

        // Hand with value > 5 - should never zapzap
        let high_hand = vec![10, 11, 12]; // J, Q, K = 11+12+13 = 36
        assert!(!strategy.should_zapzap(&high_hand, &state));
    }

    #[test]
    fn test_select_draw_source() {
        let strategy = DRLStrategy::new(0);
        let state = GameState::new(4);
        let hand = vec![0, 1, 2];

        // Empty discard - must draw from deck
        assert!(strategy.select_draw_source(&hand, &[], &state));

        // With discard - decision depends on network
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

        // Test mutable play selection
        let play = strategy.select_play_mut(hand, &state);
        assert!(play.is_some());

        // Test mutable zapzap
        let _ = strategy.should_zapzap_mut(&[52], &state);

        // Test mutable draw source
        let _ = strategy.select_draw_source_mut(hand, &[10], &state);

        // Test mutable hand size
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
}
