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
