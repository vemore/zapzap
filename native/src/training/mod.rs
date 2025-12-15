//! Training module for DRL bot using burn framework
//!
//! This module implements:
//! - DuelingDQN neural network with 4 decision heads
//! - Prioritized Experience Replay (PER) buffer
//! - Parallel game simulation with rayon
//! - Training loop with Double DQN
//! - TransitionCollector for recording gameplay
//! - Model I/O with safetensors format

pub mod collector;
pub mod config;
pub mod dueling_dqn;
pub mod model_io;
pub mod replay_buffer;
pub mod sum_tree;
pub mod trainer;
pub mod transition;

pub use collector::TransitionCollector;
pub use config::TrainingConfig;
pub use dueling_dqn::{DecisionType, DuelingDQN, DuelingDQNConfig, ACTION_DIMS};
pub use model_io::{ModelIO, ModelMetadata};
pub use replay_buffer::PrioritizedReplayBuffer;
pub use sum_tree::SumTree;
pub use trainer::{Trainer, TrainingState};
pub use transition::{Transition, TransitionBatch};

// Backend type aliases for convenience
use burn_autodiff::Autodiff;
use burn_ndarray::NdArray;

/// CPU backend type for inference
pub type CpuBackend = NdArray<f32>;

/// Autodiff backend type for training
pub type TrainingBackend = Autodiff<NdArray<f32>>;

/// Feature dimension (must match FeatureExtractor)
pub const FEATURE_DIM: usize = 45;

#[cfg(test)]
mod tests {
    use super::*;
    use burn::prelude::*;

    #[test]
    fn test_backend_compiles() {
        // Simple test to verify burn compiles correctly
        let device = <CpuBackend as burn::tensor::backend::Backend>::Device::default();
        let tensor: burn::tensor::Tensor<CpuBackend, 2> =
            burn::tensor::Tensor::zeros([1, FEATURE_DIM], &device);
        assert_eq!(tensor.dims(), [1, FEATURE_DIM]);
    }
}
