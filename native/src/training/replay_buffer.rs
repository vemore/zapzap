//! Prioritized Experience Replay (PER) Buffer

use super::sum_tree::SumTree;
use super::transition::{Transition, TransitionBatch};
use burn::prelude::*;
use rand::Rng;

/// Prioritized Experience Replay Buffer
///
/// Uses a SumTree for O(log n) sampling based on TD-error priorities.
/// Implements importance sampling weights to correct for non-uniform sampling.
pub struct PrioritizedReplayBuffer {
    /// SumTree for priority-based sampling
    tree: SumTree,
    /// Stored transitions
    data: Vec<Option<Transition>>,
    /// Buffer capacity
    capacity: usize,
    /// Current number of stored transitions
    size: usize,

    // PER hyperparameters
    /// Priority exponent (how much prioritization, 0 = uniform)
    alpha: f32,
    /// Importance sampling exponent (annealed from beta_start to 1.0)
    beta: f32,
    /// Small constant to ensure non-zero priority
    epsilon: f32,
    /// Maximum priority seen (for new transitions)
    max_priority: f32,
}

impl PrioritizedReplayBuffer {
    /// Create a new PER buffer
    pub fn new(capacity: usize, alpha: f32, beta: f32, epsilon: f32) -> Self {
        Self {
            tree: SumTree::new(capacity),
            data: vec![None; capacity],
            capacity,
            size: 0,
            alpha,
            beta,
            epsilon,
            max_priority: 1.0,
        }
    }

    /// Create with default hyperparameters
    pub fn with_capacity(capacity: usize) -> Self {
        Self::new(capacity, 0.6, 0.4, 0.01)
    }

    /// Get current size
    #[inline]
    pub fn len(&self) -> usize {
        self.size
    }

    /// Check if empty
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.size == 0
    }

    /// Update beta for importance sampling annealing
    pub fn set_beta(&mut self, beta: f32) {
        self.beta = beta.clamp(0.0, 1.0);
    }

    /// Add a transition with maximum priority
    pub fn push(&mut self, transition: Transition) {
        let priority = self.max_priority.powf(self.alpha);
        let idx = self.tree.add(priority);
        self.data[idx] = Some(transition);
        self.size = (self.size + 1).min(self.capacity);
    }

    /// Sample a batch of transitions
    ///
    /// Returns None if not enough transitions in buffer
    pub fn sample<B: Backend>(
        &self,
        batch_size: usize,
        decision_type: u8,
        device: &B::Device,
    ) -> Option<TransitionBatch<B>> {
        if self.size < batch_size {
            return None;
        }

        let total = self.tree.total();
        if total <= 0.0 {
            return None;
        }

        let segment = total / batch_size as f32;
        let mut rng = rand::thread_rng();

        let mut indices = Vec::with_capacity(batch_size);
        let mut priorities = Vec::with_capacity(batch_size);
        let mut transitions = Vec::with_capacity(batch_size);

        // Stratified sampling for better coverage
        for i in 0..batch_size {
            let low = segment * i as f32;
            let high = segment * (i + 1) as f32;
            let value = low + rng.gen::<f32>() * (high - low);

            let (idx, priority) = self.tree.get(value.min(total - 0.0001));

            // Skip if no data at this index (shouldn't happen but safety check)
            if let Some(ref t) = self.data[idx] {
                indices.push(idx);
                priorities.push(priority);
                transitions.push(t.clone());
            }
        }

        if transitions.len() < batch_size {
            return None;
        }

        // Calculate importance sampling weights
        let is_weights = self.compute_is_weights(&priorities, total);

        Some(TransitionBatch::from_transitions(
            &transitions,
            &is_weights,
            indices,
            decision_type,
            device,
        ))
    }

    /// Compute importance sampling weights for given priorities
    fn compute_is_weights(&self, priorities: &[f32], total: f32) -> Vec<f32> {
        // min_prob for normalizing weights
        let min_prob = self.tree.min_priority() / total;
        let max_weight = (self.size as f32 * min_prob).powf(-self.beta);

        priorities
            .iter()
            .map(|&p| {
                let prob = p / total;
                let weight = (self.size as f32 * prob).powf(-self.beta);
                (weight / max_weight).min(1.0) // Normalize and clamp
            })
            .collect()
    }

    /// Update priorities based on TD errors
    pub fn update_priorities(&mut self, indices: &[usize], td_errors: &[f32]) {
        for (&idx, &td_error) in indices.iter().zip(td_errors.iter()) {
            let priority = (td_error.abs() + self.epsilon).powf(self.alpha);
            self.tree.update(idx, priority);
            self.max_priority = self.max_priority.max(priority);
        }
    }

    /// Clear the buffer
    pub fn clear(&mut self) {
        self.tree = SumTree::new(self.capacity);
        self.data = vec![None; self.capacity];
        self.size = 0;
        self.max_priority = 1.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::training::FEATURE_DIM;

    fn make_transition(reward: f32, decision_type: u8) -> Transition {
        Transition::new(
            [0.5f32; FEATURE_DIM],
            1,
            reward,
            [0.6f32; FEATURE_DIM],
            false,
            decision_type,
        )
    }

    #[test]
    fn test_new() {
        let buffer = PrioritizedReplayBuffer::with_capacity(1000);
        assert_eq!(buffer.capacity, 1000);
        assert!(buffer.is_empty());
    }

    #[test]
    fn test_push() {
        let mut buffer = PrioritizedReplayBuffer::with_capacity(100);

        buffer.push(make_transition(1.0, 0));
        assert_eq!(buffer.len(), 1);

        buffer.push(make_transition(-0.5, 1));
        assert_eq!(buffer.len(), 2);
    }

    #[test]
    fn test_sample_not_enough() {
        let buffer = PrioritizedReplayBuffer::with_capacity(100);
        let device = <super::super::CpuBackend as Backend>::Device::default();

        let batch = buffer.sample::<super::super::CpuBackend>(10, 0, &device);
        assert!(batch.is_none());
    }

    #[test]
    fn test_sample_enough() {
        let mut buffer = PrioritizedReplayBuffer::with_capacity(100);

        // Add enough transitions
        for i in 0..50 {
            buffer.push(make_transition(i as f32 * 0.1, 0));
        }

        let device = <super::super::CpuBackend as Backend>::Device::default();
        let batch = buffer.sample::<super::super::CpuBackend>(10, 0, &device);

        assert!(batch.is_some());
        let batch = batch.unwrap();
        assert_eq!(batch.len(), 10);
    }

    #[test]
    fn test_update_priorities() {
        let mut buffer = PrioritizedReplayBuffer::with_capacity(100);

        for _ in 0..10 {
            buffer.push(make_transition(1.0, 0));
        }

        // Update priorities with large TD errors to ensure priority > 1.0
        // priority = (abs(td_error) + epsilon)^alpha = (5.0 + 0.01)^0.6 ≈ 2.78
        buffer.update_priorities(&[0, 1, 2], &[1.5, 5.0, 2.0]);

        // Max priority should have changed
        assert!(buffer.max_priority > 1.0);
    }

    #[test]
    fn test_circular_buffer() {
        let mut buffer = PrioritizedReplayBuffer::with_capacity(5);

        // Fill buffer
        for i in 0..5 {
            buffer.push(make_transition(i as f32, 0));
        }
        assert_eq!(buffer.len(), 5);

        // Add more - should wrap around
        for i in 5..10 {
            buffer.push(make_transition(i as f32, 0));
        }
        assert_eq!(buffer.len(), 5); // Still at capacity
    }

    #[test]
    fn test_beta_annealing() {
        let mut buffer = PrioritizedReplayBuffer::with_capacity(100);

        buffer.set_beta(0.4);
        assert_eq!(buffer.beta, 0.4);

        buffer.set_beta(1.0);
        assert_eq!(buffer.beta, 1.0);

        // Clamp to valid range
        buffer.set_beta(1.5);
        assert_eq!(buffer.beta, 1.0);
    }
}
