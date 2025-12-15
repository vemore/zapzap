//! Transition storage for experience replay

use super::FEATURE_DIM;
use burn::prelude::*;
use burn::tensor::TensorData;

/// A single transition (s, a, r, s', done, decision_type)
#[derive(Clone, Debug)]
pub struct Transition {
    /// Current state features (45-dim)
    pub state: [f32; FEATURE_DIM],
    /// Action taken (index into action space)
    pub action: u8,
    /// Reward received
    pub reward: f32,
    /// Next state features (45-dim)
    pub next_state: [f32; FEATURE_DIM],
    /// Whether episode terminated
    pub done: bool,
    /// Decision type (0=handSize, 1=zapzap, 2=playType, 3=drawSource)
    pub decision_type: u8,
}

impl Transition {
    pub fn new(
        state: [f32; FEATURE_DIM],
        action: u8,
        reward: f32,
        next_state: [f32; FEATURE_DIM],
        done: bool,
        decision_type: u8,
    ) -> Self {
        Self {
            state,
            action,
            reward,
            next_state,
            done,
            decision_type,
        }
    }

    /// Create from vectors (for convenience)
    pub fn from_vecs(
        state: &[f32],
        action: u8,
        reward: f32,
        next_state: &[f32],
        done: bool,
        decision_type: u8,
    ) -> Self {
        let mut s = [0.0f32; FEATURE_DIM];
        let mut ns = [0.0f32; FEATURE_DIM];
        s.copy_from_slice(&state[..FEATURE_DIM.min(state.len())]);
        ns.copy_from_slice(&next_state[..FEATURE_DIM.min(next_state.len())]);
        Self::new(s, action, reward, ns, done, decision_type)
    }
}

/// A batch of transitions for training
pub struct TransitionBatch<B: Backend> {
    /// States tensor [batch, FEATURE_DIM]
    pub states: Tensor<B, 2>,
    /// Actions tensor [batch, 1]
    pub actions: Tensor<B, 2, Int>,
    /// Rewards tensor [batch, 1]
    pub rewards: Tensor<B, 2>,
    /// Next states tensor [batch, FEATURE_DIM]
    pub next_states: Tensor<B, 2>,
    /// Done flags tensor [batch, 1]
    pub dones: Tensor<B, 2>,
    /// Importance sampling weights [batch, 1]
    pub is_weights: Tensor<B, 2>,
    /// Indices in replay buffer (for priority updates)
    pub indices: Vec<usize>,
    /// Decision type for this batch
    pub decision_type: u8,
}

impl<B: Backend> TransitionBatch<B> {
    /// Create batch from transitions
    pub fn from_transitions(
        transitions: &[Transition],
        is_weights: &[f32],
        indices: Vec<usize>,
        decision_type: u8,
        device: &B::Device,
    ) -> Self {
        let batch_size = transitions.len();

        // Flatten states
        let states_data: Vec<f32> = transitions
            .iter()
            .flat_map(|t| t.state.iter().copied())
            .collect();
        let states: Tensor<B, 2> = Tensor::from_data(
            TensorData::new(states_data, [batch_size, FEATURE_DIM]),
            device,
        );

        // Actions as i32
        let actions_data: Vec<i32> = transitions.iter().map(|t| t.action as i32).collect();
        let actions: Tensor<B, 2, Int> = Tensor::from_data(
            TensorData::new(actions_data, [batch_size, 1]),
            device,
        );

        // Rewards
        let rewards_data: Vec<f32> = transitions.iter().map(|t| t.reward).collect();
        let rewards: Tensor<B, 2> = Tensor::from_data(
            TensorData::new(rewards_data, [batch_size, 1]),
            device,
        );

        // Next states
        let next_states_data: Vec<f32> = transitions
            .iter()
            .flat_map(|t| t.next_state.iter().copied())
            .collect();
        let next_states: Tensor<B, 2> = Tensor::from_data(
            TensorData::new(next_states_data, [batch_size, FEATURE_DIM]),
            device,
        );

        // Dones as f32 (0.0 or 1.0)
        let dones_data: Vec<f32> = transitions
            .iter()
            .map(|t| if t.done { 1.0 } else { 0.0 })
            .collect();
        let dones: Tensor<B, 2> = Tensor::from_data(
            TensorData::new(dones_data, [batch_size, 1]),
            device,
        );

        // IS weights
        let is_weights_tensor: Tensor<B, 2> = Tensor::from_data(
            TensorData::new(is_weights.to_vec(), [batch_size, 1]),
            device,
        );

        Self {
            states,
            actions,
            rewards,
            next_states,
            dones,
            is_weights: is_weights_tensor,
            indices,
            decision_type,
        }
    }

    /// Get batch size
    pub fn len(&self) -> usize {
        self.indices.len()
    }

    /// Check if batch is empty
    pub fn is_empty(&self) -> bool {
        self.indices.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_transition_new() {
        let state = [0.5f32; FEATURE_DIM];
        let next_state = [0.6f32; FEATURE_DIM];
        let t = Transition::new(state, 2, 1.0, next_state, false, 2);

        assert_eq!(t.action, 2);
        assert_eq!(t.reward, 1.0);
        assert!(!t.done);
        assert_eq!(t.decision_type, 2);
    }

    #[test]
    fn test_transition_from_vecs() {
        let state: Vec<f32> = (0..FEATURE_DIM).map(|i| i as f32 / 100.0).collect();
        let next_state: Vec<f32> = (0..FEATURE_DIM).map(|i| (i + 1) as f32 / 100.0).collect();

        let t = Transition::from_vecs(&state, 1, -0.5, &next_state, true, 0);

        assert_eq!(t.action, 1);
        assert_eq!(t.reward, -0.5);
        assert!(t.done);
        assert_eq!(t.decision_type, 0);
    }
}
