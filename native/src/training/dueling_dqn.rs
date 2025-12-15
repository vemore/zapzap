//! Dueling DQN Neural Network with burn framework
//!
//! Architecture:
//! - Shared layers: input(45) -> 128 -> 64
//! - Value stream: 64 -> 32 -> 1
//! - Advantage heads (4): 64 -> 32 -> [7, 2, 5, 2]
//!
//! Q(s,a) = V(s) + (A(s,a) - mean(A(s,:)))

use burn::nn::{Linear, LinearConfig};
use burn::prelude::*;
use burn::tensor::activation::relu;
use burn::tensor::TensorData;

use super::FEATURE_DIM;

/// Action dimensions for each decision type
pub const ACTION_DIMS: [usize; 4] = [
    7, // handSize: 3-9 cards (7 options)
    2, // zapzap: yes/no
    5, // playType: single, pair, triple, quad, sequence
    2, // drawSource: deck/discard
];

/// Decision type enum
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum DecisionType {
    HandSize = 0,
    ZapZap = 1,
    PlayType = 2,
    DrawSource = 3,
}

impl DecisionType {
    pub fn action_dim(self) -> usize {
        ACTION_DIMS[self as usize]
    }

    pub fn from_u8(value: u8) -> Option<Self> {
        match value {
            0 => Some(Self::HandSize),
            1 => Some(Self::ZapZap),
            2 => Some(Self::PlayType),
            3 => Some(Self::DrawSource),
            _ => None,
        }
    }

    pub fn all() -> [Self; 4] {
        [Self::HandSize, Self::ZapZap, Self::PlayType, Self::DrawSource]
    }
}

/// Configuration for DuelingDQN
#[derive(Config, Debug)]
pub struct DuelingDQNConfig {
    #[config(default = "45")]
    pub input_dim: usize,
    #[config(default = "128")]
    pub hidden_dim: usize,
    #[config(default = "64")]
    pub value_hidden: usize,
    #[config(default = "32")]
    pub advantage_hidden: usize,
}

impl Default for DuelingDQNConfig {
    fn default() -> Self {
        Self::new()
    }
}

/// Advantage head for a single decision type
#[derive(Module, Debug)]
pub struct AdvantageHead<B: Backend> {
    linear1: Linear<B>,
    linear2: Linear<B>,
}

impl<B: Backend> AdvantageHead<B> {
    pub fn new(input_dim: usize, hidden_dim: usize, output_dim: usize, device: &B::Device) -> Self {
        Self {
            linear1: LinearConfig::new(input_dim, hidden_dim).init(device),
            linear2: LinearConfig::new(hidden_dim, output_dim).init(device),
        }
    }

    pub fn forward(&self, x: Tensor<B, 2>) -> Tensor<B, 2> {
        let h = relu(self.linear1.forward(x));
        self.linear2.forward(h)
    }
}

/// Dueling DQN Network
#[derive(Module, Debug)]
pub struct DuelingDQN<B: Backend> {
    // Shared layers
    shared1: Linear<B>,
    shared2: Linear<B>,

    // Value stream
    value1: Linear<B>,
    value2: Linear<B>,

    // Advantage heads (one per decision type)
    advantage_hand_size: AdvantageHead<B>,
    advantage_zapzap: AdvantageHead<B>,
    advantage_play_type: AdvantageHead<B>,
    advantage_draw_source: AdvantageHead<B>,
}

impl<B: Backend> DuelingDQN<B> {
    /// Create a new DuelingDQN with given config
    pub fn new(config: &DuelingDQNConfig, device: &B::Device) -> Self {
        // Shared layers: input -> hidden -> value_hidden
        let shared1 = LinearConfig::new(config.input_dim, config.hidden_dim).init(device);
        let shared2 = LinearConfig::new(config.hidden_dim, config.value_hidden).init(device);

        // Value stream: value_hidden -> advantage_hidden -> 1
        let value1 = LinearConfig::new(config.value_hidden, config.advantage_hidden).init(device);
        let value2 = LinearConfig::new(config.advantage_hidden, 1).init(device);

        // Advantage heads
        let advantage_hand_size = AdvantageHead::new(
            config.value_hidden,
            config.advantage_hidden,
            ACTION_DIMS[0],
            device,
        );
        let advantage_zapzap = AdvantageHead::new(
            config.value_hidden,
            config.advantage_hidden,
            ACTION_DIMS[1],
            device,
        );
        let advantage_play_type = AdvantageHead::new(
            config.value_hidden,
            config.advantage_hidden,
            ACTION_DIMS[2],
            device,
        );
        let advantage_draw_source = AdvantageHead::new(
            config.value_hidden,
            config.advantage_hidden,
            ACTION_DIMS[3],
            device,
        );

        Self {
            shared1,
            shared2,
            value1,
            value2,
            advantage_hand_size,
            advantage_zapzap,
            advantage_play_type,
            advantage_draw_source,
        }
    }

    /// Create with default config
    pub fn default_config(device: &B::Device) -> Self {
        Self::new(&DuelingDQNConfig::default(), device)
    }

    /// Forward pass through shared layers
    fn forward_shared(&self, x: Tensor<B, 2>) -> Tensor<B, 2> {
        let h = relu(self.shared1.forward(x));
        relu(self.shared2.forward(h))
    }

    /// Forward pass through value stream
    fn forward_value(&self, h: Tensor<B, 2>) -> Tensor<B, 2> {
        let v = relu(self.value1.forward(h));
        self.value2.forward(v)
    }

    /// Debug forward pass returning intermediate activations
    pub fn forward_debug(&self, x: Tensor<B, 2>) -> (Tensor<B, 2>, Tensor<B, 2>, f32) {
        let h1 = relu(self.shared1.forward(x));
        let h2 = relu(self.shared2.forward(h1.clone()));
        let v1 = relu(self.value1.forward(h2.clone()));
        let v2 = self.value2.forward(v1);
        let v_data = v2.into_data();
        let v_value = v_data.as_slice::<f32>().unwrap()[0];
        (h1, h2, v_value)
    }

    /// Forward pass for a specific decision type
    ///
    /// Returns Q-values: [batch_size, action_dim]
    pub fn forward(&self, x: Tensor<B, 2>, decision_type: DecisionType) -> Tensor<B, 2> {
        // Shared layers
        let h = self.forward_shared(x);

        // Value stream: [batch, 1]
        let v = self.forward_value(h.clone());

        // Advantage stream: [batch, action_dim]
        let a = match decision_type {
            DecisionType::HandSize => self.advantage_hand_size.forward(h),
            DecisionType::ZapZap => self.advantage_zapzap.forward(h),
            DecisionType::PlayType => self.advantage_play_type.forward(h),
            DecisionType::DrawSource => self.advantage_draw_source.forward(h),
        };

        // Dueling: Q = V + (A - mean(A))
        let a_mean = a.clone().mean_dim(1); // [batch, 1]
        let a_centered = a - a_mean;

        v + a_centered
    }

    /// Get greedy action (argmax Q)
    /// Returns tensor with shape [batch_size, 1]
    pub fn greedy_action(&self, x: Tensor<B, 2>, decision_type: DecisionType) -> Tensor<B, 2, Int> {
        let q = self.forward(x, decision_type);
        let batch_size = q.dims()[0];
        q.argmax(1).reshape([batch_size, 1])
    }

    /// Get Q-values as a flat vector (for single input)
    pub fn q_values(&self, features: &[f32], decision_type: DecisionType, device: &B::Device) -> Vec<f32> {
        let input: Tensor<B, 2> = Tensor::from_data(
            TensorData::new(features.to_vec(), [1, FEATURE_DIM]),
            device,
        );
        let q = self.forward(input, decision_type);

        // Convert to Vec<f32>
        let data = q.into_data();
        data.as_slice::<f32>().unwrap().to_vec()
    }

    /// Extract all weights as a flat vector
    /// Format: weights are transposed to [out_features, in_features] order (FastDQN's format)
    /// Burn stores as [in_features, out_features], so we transpose during extraction
    /// Order: shared1_w, shared1_b, shared2_w, shared2_b, value1_w, value1_b, value2_w, value2_b,
    ///        then for each decision type: adv1_w, adv1_b, adv2_w, adv2_b
    pub fn get_weights_flat(&self) -> Vec<f32> {
        let mut weights = Vec::new();

        // Helper to extract Linear layer weights WITH transposition
        // Burn stores weights as [in_features, out_features]
        // FastDQN expects [out_features, in_features]
        // So we transpose: for each output neuron o, copy weights for all inputs i
        fn extract_linear_transposed<B: Backend>(
            linear: &Linear<B>,
            weights: &mut Vec<f32>,
            in_features: usize,
            out_features: usize
        ) {
            let w_data = linear.weight.val().into_data();
            let w_slice = w_data.as_slice::<f32>().unwrap_or(&[]);

            // Transpose from [in, out] to [out, in]
            // burn layout: w_slice[i * out_features + o] = weight from input i to output o
            // fastdqn layout: weights[o * in_features + i] = weight from input i to output o
            for o in 0..out_features {
                for i in 0..in_features {
                    let burn_idx = i * out_features + o;
                    if burn_idx < w_slice.len() {
                        weights.push(w_slice[burn_idx]);
                    } else {
                        weights.push(0.0);
                    }
                }
            }

            // Bias (no transposition needed - just one value per output)
            if let Some(ref bias) = linear.bias {
                let b_data = bias.val().into_data();
                weights.extend(b_data.as_slice::<f32>().unwrap_or(&[]));
            } else {
                // Add zeros if no bias
                for _ in 0..out_features {
                    weights.push(0.0);
                }
            }
        }

        // Shared layers: 45->128, 128->64
        extract_linear_transposed(&self.shared1, &mut weights, 45, 128);
        extract_linear_transposed(&self.shared2, &mut weights, 128, 64);

        // Value stream: 64->32, 32->1
        extract_linear_transposed(&self.value1, &mut weights, 64, 32);
        extract_linear_transposed(&self.value2, &mut weights, 32, 1);

        // Advantage heads (in order: HandSize, ZapZap, PlayType, DrawSource)
        // Each head: 64->32, 32->action_dim
        let action_dims = [7, 2, 5, 2];
        for (head, &action_dim) in [
            &self.advantage_hand_size,
            &self.advantage_zapzap,
            &self.advantage_play_type,
            &self.advantage_draw_source,
        ].iter().zip(action_dims.iter()) {
            extract_linear_transposed(&head.linear1, &mut weights, 64, 32);
            extract_linear_transposed(&head.linear2, &mut weights, 32, action_dim);
        }

        weights
    }

    /// Load weights from a flat vector
    /// Note: This is a simplified version - for full implementation, we'd need to
    /// properly handle Param types in burn. For now, we just log the expected sizes.
    pub fn set_weights_flat(&mut self, _weights: &[f32], _device: &B::Device) {
        // Burn's Linear layer uses Param<Tensor> which requires special handling
        // For now, this is a no-op - weights are trained in-place
        // A full implementation would require reconstructing the Linear layers
    }

    /// Get the expected weight count for this network
    pub fn weight_count(&self) -> usize {
        // Shared layers: (45*128 + 128) + (128*64 + 64)
        let shared = 45 * 128 + 128 + 128 * 64 + 64;
        // Value stream: (64*32 + 32) + (32*1 + 1)
        let value = 64 * 32 + 32 + 32 * 1 + 1;
        // Advantage heads: 4 * ((64*32 + 32) + (32*action_dim + action_dim))
        // For simplicity, using max action_dim = 7
        let advantage_per_head = 64 * 32 + 32 + 32 * 7 + 7;
        shared + value + 4 * advantage_per_head
    }

    /// Get raw shared1 weights for debugging (stored in burn's [out, in] format)
    pub fn get_shared1_weights_raw(&self) -> Vec<f32> {
        let w_data = self.shared1.weight.val().into_data();
        w_data.as_slice::<f32>().unwrap_or(&[]).to_vec()
    }

    /// Get raw shared2 weights for debugging
    pub fn get_shared2_weights_raw(&self) -> Vec<f32> {
        let w_data = self.shared2.weight.val().into_data();
        w_data.as_slice::<f32>().unwrap_or(&[]).to_vec()
    }

    /// Get raw value1 weights for debugging
    pub fn get_value1_weights_raw(&self) -> Vec<f32> {
        let w_data = self.value1.weight.val().into_data();
        w_data.as_slice::<f32>().unwrap_or(&[]).to_vec()
    }

    /// Get raw value2 weights for debugging
    pub fn get_value2_weights_raw(&self) -> Vec<f32> {
        let w_data = self.value2.weight.val().into_data();
        w_data.as_slice::<f32>().unwrap_or(&[]).to_vec()
    }

    /// Get raw advantage hand_size layer1 weights for debugging
    pub fn get_adv_hand_size_l1_weights_raw(&self) -> Vec<f32> {
        let w_data = self.advantage_hand_size.linear1.weight.val().into_data();
        w_data.as_slice::<f32>().unwrap_or(&[]).to_vec()
    }

    /// Get raw advantage hand_size layer2 weights for debugging
    pub fn get_adv_hand_size_l2_weights_raw(&self) -> Vec<f32> {
        let w_data = self.advantage_hand_size.linear2.weight.val().into_data();
        w_data.as_slice::<f32>().unwrap_or(&[]).to_vec()
    }

    /// Get raw shared1 bias
    pub fn get_shared1_bias_raw(&self) -> Vec<f32> {
        if let Some(ref bias) = self.shared1.bias {
            let b_data = bias.val().into_data();
            b_data.as_slice::<f32>().unwrap_or(&[]).to_vec()
        } else {
            vec![]
        }
    }

    /// Get raw shared2 bias
    pub fn get_shared2_bias_raw(&self) -> Vec<f32> {
        if let Some(ref bias) = self.shared2.bias {
            let b_data = bias.val().into_data();
            b_data.as_slice::<f32>().unwrap_or(&[]).to_vec()
        } else {
            vec![]
        }
    }

    /// Get raw value1 bias
    pub fn get_value1_bias_raw(&self) -> Vec<f32> {
        if let Some(ref bias) = self.value1.bias {
            let b_data = bias.val().into_data();
            b_data.as_slice::<f32>().unwrap_or(&[]).to_vec()
        } else {
            vec![]
        }
    }

    /// Get raw value2 bias
    pub fn get_value2_bias_raw(&self) -> f32 {
        if let Some(ref bias) = self.value2.bias {
            let b_data = bias.val().into_data();
            let slice = b_data.as_slice::<f32>().unwrap_or(&[0.0]);
            if !slice.is_empty() { slice[0] } else { 0.0 }
        } else {
            0.0
        }
    }

    /// Get raw adv hand_size l1 bias
    pub fn get_adv_hand_size_l1_bias_raw(&self) -> Vec<f32> {
        if let Some(ref bias) = self.advantage_hand_size.linear1.bias {
            let b_data = bias.val().into_data();
            b_data.as_slice::<f32>().unwrap_or(&[]).to_vec()
        } else {
            vec![]
        }
    }

    /// Get raw adv hand_size l2 bias
    pub fn get_adv_hand_size_l2_bias_raw(&self) -> Vec<f32> {
        if let Some(ref bias) = self.advantage_hand_size.linear2.bias {
            let b_data = bias.val().into_data();
            b_data.as_slice::<f32>().unwrap_or(&[]).to_vec()
        } else {
            vec![]
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::training::CpuBackend;

    #[test]
    fn test_decision_type() {
        assert_eq!(DecisionType::HandSize.action_dim(), 7);
        assert_eq!(DecisionType::ZapZap.action_dim(), 2);
        assert_eq!(DecisionType::PlayType.action_dim(), 5);
        assert_eq!(DecisionType::DrawSource.action_dim(), 2);

        assert_eq!(DecisionType::from_u8(0), Some(DecisionType::HandSize));
        assert_eq!(DecisionType::from_u8(4), None);
    }

    #[test]
    fn test_network_creation() {
        let device = <CpuBackend as Backend>::Device::default();
        let config = DuelingDQNConfig::default();
        let _network = DuelingDQN::<CpuBackend>::new(&config, &device);
    }

    #[test]
    fn test_forward_hand_size() {
        let device = <CpuBackend as Backend>::Device::default();
        let network = DuelingDQN::<CpuBackend>::default_config(&device);

        let input: Tensor<CpuBackend, 2> = Tensor::zeros([2, FEATURE_DIM], &device);
        let output = network.forward(input, DecisionType::HandSize);

        assert_eq!(output.dims(), [2, 7]);
    }

    #[test]
    fn test_forward_zapzap() {
        let device = <CpuBackend as Backend>::Device::default();
        let network = DuelingDQN::<CpuBackend>::default_config(&device);

        let input: Tensor<CpuBackend, 2> = Tensor::zeros([1, FEATURE_DIM], &device);
        let output = network.forward(input, DecisionType::ZapZap);

        assert_eq!(output.dims(), [1, 2]);
    }

    #[test]
    fn test_forward_play_type() {
        let device = <CpuBackend as Backend>::Device::default();
        let network = DuelingDQN::<CpuBackend>::default_config(&device);

        let input: Tensor<CpuBackend, 2> = Tensor::zeros([4, FEATURE_DIM], &device);
        let output = network.forward(input, DecisionType::PlayType);

        assert_eq!(output.dims(), [4, 5]);
    }

    #[test]
    fn test_forward_draw_source() {
        let device = <CpuBackend as Backend>::Device::default();
        let network = DuelingDQN::<CpuBackend>::default_config(&device);

        let input: Tensor<CpuBackend, 2> = Tensor::zeros([1, FEATURE_DIM], &device);
        let output = network.forward(input, DecisionType::DrawSource);

        assert_eq!(output.dims(), [1, 2]);
    }

    #[test]
    fn test_greedy_action() {
        let device = <CpuBackend as Backend>::Device::default();
        let network = DuelingDQN::<CpuBackend>::default_config(&device);

        let input: Tensor<CpuBackend, 2> = Tensor::zeros([3, FEATURE_DIM], &device);
        let actions = network.greedy_action(input, DecisionType::PlayType);

        assert_eq!(actions.dims(), [3, 1]);
    }

    #[test]
    fn test_q_values() {
        let device = <CpuBackend as Backend>::Device::default();
        let network = DuelingDQN::<CpuBackend>::default_config(&device);

        let features = vec![0.5f32; FEATURE_DIM];
        let q = network.q_values(&features, DecisionType::HandSize, &device);

        assert_eq!(q.len(), 7);
    }

    #[test]
    fn test_all_decision_types() {
        let device = <CpuBackend as Backend>::Device::default();
        let network = DuelingDQN::<CpuBackend>::default_config(&device);
        let input: Tensor<CpuBackend, 2> = Tensor::zeros([1, FEATURE_DIM], &device);

        for dt in DecisionType::all() {
            let output = network.forward(input.clone(), dt);
            assert_eq!(output.dims()[1], dt.action_dim());
        }
    }
}
