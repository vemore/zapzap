//! LightweightDQN - Pure Rust neural network inference
//!
//! Architecture matches DuelingDQN from JavaScript:
//! - Input: 45 features
//! - Hidden: Dense(256, relu) -> Dense(128, relu) -> Dense(64, relu) -> Dense(32, relu)
//! - Output: Action Q-values per decision type

use crate::feature_extractor::FEATURE_DIM;

/// Decision types with their action dimensions
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DecisionType {
    HandSize,   // 7 actions (4-10 cards)
    ZapZap,     // 2 actions (no, yes)
    PlayType,   // 5 actions (different play strategies)
    DrawSource, // 2 actions (deck, discard)
}

impl DecisionType {
    pub fn action_dim(&self) -> usize {
        match self {
            DecisionType::HandSize => 7,
            DecisionType::ZapZap => 2,
            DecisionType::PlayType => 5,
            DecisionType::DrawSource => 2,
        }
    }

    pub fn all() -> &'static [DecisionType] {
        &[
            DecisionType::HandSize,
            DecisionType::ZapZap,
            DecisionType::PlayType,
            DecisionType::DrawSource,
        ]
    }

    pub fn from_str(s: &str) -> Option<DecisionType> {
        match s.to_lowercase().as_str() {
            "handsize" | "hand_size" => Some(DecisionType::HandSize),
            "zapzap" | "zap_zap" => Some(DecisionType::ZapZap),
            "playtype" | "play_type" => Some(DecisionType::PlayType),
            "drawsource" | "draw_source" => Some(DecisionType::DrawSource),
            _ => None,
        }
    }
}

/// Layer sizes for the network
const LAYER_SIZES: [usize; 6] = [FEATURE_DIM, 256, 128, 64, 32, 0]; // Last one is action_dim

/// Neural network layer (weights + bias)
#[derive(Debug, Clone)]
pub struct DenseLayer {
    weights: Vec<Vec<f32>>, // [out_features][in_features]
    bias: Vec<f32>,         // [out_features]
}

impl DenseLayer {
    /// Create layer with random weights (He initialization)
    pub fn new_random(in_features: usize, out_features: usize) -> Self {
        let scale = (2.0 / in_features as f32).sqrt();
        let mut rng_state = 12345u64;

        let weights: Vec<Vec<f32>> = (0..out_features)
            .map(|_| {
                (0..in_features)
                    .map(|_| {
                        // Simple xorshift RNG
                        rng_state ^= rng_state << 13;
                        rng_state ^= rng_state >> 7;
                        rng_state ^= rng_state << 17;
                        let r = (rng_state as f32 / u64::MAX as f32) * 2.0 - 1.0;
                        r * scale
                    })
                    .collect()
            })
            .collect();

        let bias = vec![0.0; out_features];

        DenseLayer { weights, bias }
    }

    /// Create layer from flat weight data (transposed from TensorFlow format)
    pub fn from_flat_weights(
        flat_weights: &[f32],
        flat_bias: &[f32],
        in_features: usize,
        out_features: usize,
    ) -> Self {
        // TensorFlow uses [in, out] format, we need [out, in]
        let mut weights = vec![vec![0.0; in_features]; out_features];
        for o in 0..out_features {
            for i in 0..in_features {
                // Original TF index: i * out_features + o
                weights[o][i] = flat_weights[i * out_features + o];
            }
        }
        let bias = flat_bias.to_vec();

        DenseLayer { weights, bias }
    }

    /// Forward pass: output = weights @ input + bias
    pub fn forward(&self, input: &[f32]) -> Vec<f32> {
        let mut output = Vec::with_capacity(self.bias.len());
        for (row, b) in self.weights.iter().zip(self.bias.iter()) {
            let sum: f32 = row.iter().zip(input.iter()).map(|(w, x)| w * x).sum();
            output.push(sum + b);
        }
        output
    }

    /// Forward pass with ReLU activation
    pub fn forward_relu(&self, input: &[f32]) -> Vec<f32> {
        let mut output = self.forward(input);
        for v in &mut output {
            *v = v.max(0.0);
        }
        output
    }
}

/// Neural network for a specific decision type
#[derive(Debug, Clone)]
pub struct DecisionNetwork {
    layers: Vec<DenseLayer>,
}

impl DecisionNetwork {
    /// Create network with random weights
    pub fn new_random(action_dim: usize) -> Self {
        let mut layers = Vec::with_capacity(5);

        // Layer 0: 45 -> 256
        layers.push(DenseLayer::new_random(LAYER_SIZES[0], LAYER_SIZES[1]));
        // Layer 1: 256 -> 128
        layers.push(DenseLayer::new_random(LAYER_SIZES[1], LAYER_SIZES[2]));
        // Layer 2: 128 -> 64
        layers.push(DenseLayer::new_random(LAYER_SIZES[2], LAYER_SIZES[3]));
        // Layer 3: 64 -> 32
        layers.push(DenseLayer::new_random(LAYER_SIZES[3], LAYER_SIZES[4]));
        // Layer 4: 32 -> action_dim
        layers.push(DenseLayer::new_random(LAYER_SIZES[4], action_dim));

        DecisionNetwork { layers }
    }

    /// Forward pass through the network
    pub fn predict(&self, input: &[f32]) -> Vec<f32> {
        let mut activation = input.to_vec();

        // Apply all layers except the last with ReLU
        for layer in self.layers.iter().take(self.layers.len() - 1) {
            activation = layer.forward_relu(&activation);
        }

        // Last layer without activation
        self.layers.last().unwrap().forward(&activation)
    }

    /// Set weights from compact format
    pub fn set_weights(&mut self, layer_weights: &[LayerWeights]) {
        if layer_weights.len() != self.layers.len() * 2 {
            return; // Invalid format
        }

        let mut idx = 0;
        for layer in &mut self.layers {
            let weights_data = &layer_weights[idx];
            let bias_data = &layer_weights[idx + 1];

            if weights_data.shape.len() == 2 {
                let in_features = weights_data.shape[0];
                let out_features = weights_data.shape[1];
                *layer =
                    DenseLayer::from_flat_weights(&weights_data.data, &bias_data.data, in_features, out_features);
            }
            idx += 2;
        }
    }
}

/// Compact weight representation for serialization
#[derive(Debug, Clone)]
pub struct LayerWeights {
    pub shape: Vec<usize>,
    pub data: Vec<f32>,
}

/// Lightweight DQN with networks for each decision type
#[derive(Debug, Clone)]
pub struct LightweightDQN {
    pub hand_size: DecisionNetwork,
    pub zapzap: DecisionNetwork,
    pub play_type: DecisionNetwork,
    pub draw_source: DecisionNetwork,
    rng_state: u64,
}

impl LightweightDQN {
    /// Create with random weights
    pub fn new() -> Self {
        LightweightDQN {
            hand_size: DecisionNetwork::new_random(DecisionType::HandSize.action_dim()),
            zapzap: DecisionNetwork::new_random(DecisionType::ZapZap.action_dim()),
            play_type: DecisionNetwork::new_random(DecisionType::PlayType.action_dim()),
            draw_source: DecisionNetwork::new_random(DecisionType::DrawSource.action_dim()),
            rng_state: 42,
        }
    }

    /// Create with seed for reproducibility
    pub fn with_seed(seed: u64) -> Self {
        let mut dqn = Self::new();
        dqn.rng_state = seed;
        dqn
    }

    /// Get Q-values for a decision type
    pub fn predict(&self, input: &[f32], decision_type: DecisionType) -> Vec<f32> {
        match decision_type {
            DecisionType::HandSize => self.hand_size.predict(input),
            DecisionType::ZapZap => self.zapzap.predict(input),
            DecisionType::PlayType => self.play_type.predict(input),
            DecisionType::DrawSource => self.draw_source.predict(input),
        }
    }

    /// Select action using epsilon-greedy policy
    pub fn select_action(
        &mut self,
        input: &[f32],
        decision_type: DecisionType,
        epsilon: f32,
    ) -> usize {
        // Exploration
        if self.random_f32() < epsilon {
            return self.random_action(decision_type);
        }

        // Exploitation - greedy action
        self.greedy_action(input, decision_type)
    }

    /// Select greedy action (best Q-value)
    pub fn greedy_action(&self, input: &[f32], decision_type: DecisionType) -> usize {
        let q_values = self.predict(input, decision_type);
        q_values
            .iter()
            .enumerate()
            .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
            .map(|(i, _)| i)
            .unwrap_or(0)
    }

    /// Random action for exploration
    fn random_action(&mut self, decision_type: DecisionType) -> usize {
        let action_dim = decision_type.action_dim();
        self.random_range(action_dim)
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

    fn random_f32(&mut self) -> f32 {
        self.next_random() as f32 / u64::MAX as f32
    }

    fn random_range(&mut self, max: usize) -> usize {
        if max == 0 {
            return 0;
        }
        (self.next_random() % max as u64) as usize
    }

    /// Set weights for a specific decision type
    pub fn set_network_weights(&mut self, decision_type: DecisionType, weights: &[LayerWeights]) {
        match decision_type {
            DecisionType::HandSize => self.hand_size.set_weights(weights),
            DecisionType::ZapZap => self.zapzap.set_weights(weights),
            DecisionType::PlayType => self.play_type.set_weights(weights),
            DecisionType::DrawSource => self.draw_source.set_weights(weights),
        }
    }
}

impl Default for LightweightDQN {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decision_types() {
        assert_eq!(DecisionType::HandSize.action_dim(), 7);
        assert_eq!(DecisionType::ZapZap.action_dim(), 2);
        assert_eq!(DecisionType::PlayType.action_dim(), 5);
        assert_eq!(DecisionType::DrawSource.action_dim(), 2);
    }

    #[test]
    fn test_dense_layer() {
        let layer = DenseLayer::new_random(10, 5);
        let input = vec![1.0; 10];
        let output = layer.forward(&input);
        assert_eq!(output.len(), 5);
    }

    #[test]
    fn test_dense_layer_relu() {
        let layer = DenseLayer::new_random(10, 5);
        let input = vec![1.0; 10];
        let output = layer.forward_relu(&input);
        assert_eq!(output.len(), 5);
        // All outputs should be >= 0 due to ReLU
        for v in &output {
            assert!(*v >= 0.0);
        }
    }

    #[test]
    fn test_network_predict() {
        let network = DecisionNetwork::new_random(2);
        let input = vec![0.5; FEATURE_DIM];
        let output = network.predict(&input);
        assert_eq!(output.len(), 2);
    }

    #[test]
    fn test_lightweight_dqn() {
        let mut dqn = LightweightDQN::new();
        let input = vec![0.5; FEATURE_DIM];

        // Test all decision types
        for dt in DecisionType::all() {
            let q_values = dqn.predict(&input, *dt);
            assert_eq!(q_values.len(), dt.action_dim());

            let action = dqn.select_action(&input, *dt, 0.0);
            assert!(action < dt.action_dim());
        }
    }

    #[test]
    fn test_greedy_action() {
        let dqn = LightweightDQN::new();
        let input = vec![0.5; FEATURE_DIM];

        // Greedy should be deterministic with same input
        let action1 = dqn.greedy_action(&input, DecisionType::ZapZap);
        let action2 = dqn.greedy_action(&input, DecisionType::ZapZap);
        assert_eq!(action1, action2);
    }

    #[test]
    fn test_epsilon_exploration() {
        let mut dqn = LightweightDQN::with_seed(42);
        let input = vec![0.5; FEATURE_DIM];

        // With epsilon=1.0, should always explore (random)
        let mut actions = std::collections::HashSet::new();
        for _ in 0..100 {
            let action = dqn.select_action(&input, DecisionType::PlayType, 1.0);
            actions.insert(action);
        }
        // Should have multiple different actions
        assert!(actions.len() > 1);
    }
}
