//! Training configuration

use serde::{Deserialize, Serialize};

/// Training hyperparameters
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TrainingConfig {
    // Network architecture
    pub input_dim: usize,
    pub hidden_dim: usize,
    pub value_hidden: usize,
    pub advantage_hidden: usize,

    // Training hyperparameters
    pub learning_rate: f64,
    pub gamma: f32,
    pub tau: f32,
    pub batch_size: usize,
    pub gradient_clip: f32,

    // Replay buffer
    pub buffer_capacity: usize,
    pub per_alpha: f32,
    pub per_beta_start: f32,
    pub per_beta_end: f32,
    pub per_epsilon: f32,

    // Exploration
    pub epsilon_start: f32,
    pub epsilon_end: f32,
    pub epsilon_decay_steps: usize,

    // Training loop
    pub games_per_batch: usize,
    pub train_interval: usize,
    pub target_update_freq: usize,
    pub save_interval: usize,

    // Parallelization
    pub num_workers: usize,
}

impl Default for TrainingConfig {
    fn default() -> Self {
        Self {
            // Network architecture (matches JS DuelingDQN)
            input_dim: 45,
            hidden_dim: 128,
            value_hidden: 64,
            advantage_hidden: 32,

            // Training hyperparameters
            learning_rate: 0.0005,
            gamma: 0.99,
            tau: 0.005,
            batch_size: 64,
            gradient_clip: 1.0,

            // Replay buffer
            buffer_capacity: 1_000_000,
            per_alpha: 0.6,
            per_beta_start: 0.4,
            per_beta_end: 1.0,
            per_epsilon: 0.01,

            // Exploration
            epsilon_start: 1.0,
            epsilon_end: 0.01,
            epsilon_decay_steps: 100_000,

            // Training loop
            games_per_batch: 100,
            train_interval: 10,
            target_update_freq: 1000,
            save_interval: 10_000,

            // Parallelization
            num_workers: num_cpus::get(),
        }
    }
}

impl TrainingConfig {
    /// Create config optimized for fast iteration
    pub fn fast() -> Self {
        Self {
            buffer_capacity: 100_000,
            games_per_batch: 50,
            train_interval: 5,
            epsilon_decay_steps: 50_000,
            save_interval: 5_000,
            ..Default::default()
        }
    }

    /// Create config for production training
    pub fn production() -> Self {
        Self {
            buffer_capacity: 2_000_000,
            games_per_batch: 200,
            train_interval: 20,
            epsilon_decay_steps: 200_000,
            save_interval: 25_000,
            ..Default::default()
        }
    }

    /// Calculate epsilon for given step
    pub fn get_epsilon(&self, step: usize) -> f32 {
        let ratio = (step as f32 / self.epsilon_decay_steps as f32).min(1.0);
        self.epsilon_start + (self.epsilon_end - self.epsilon_start) * ratio
    }

    /// Calculate beta for given step (PER annealing)
    pub fn get_beta(&self, step: usize) -> f32 {
        let ratio = (step as f32 / self.epsilon_decay_steps as f32).min(1.0);
        self.per_beta_start + (self.per_beta_end - self.per_beta_start) * ratio
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = TrainingConfig::default();
        assert_eq!(config.input_dim, 45);
        assert_eq!(config.batch_size, 64);
        assert!(config.num_workers > 0);
    }

    #[test]
    fn test_epsilon_decay() {
        let config = TrainingConfig::default();

        // Start
        assert!((config.get_epsilon(0) - 1.0).abs() < 0.001);

        // End
        assert!((config.get_epsilon(100_000) - 0.01).abs() < 0.001);

        // Middle
        let mid = config.get_epsilon(50_000);
        assert!(mid > 0.01 && mid < 1.0);
    }

    #[test]
    fn test_beta_annealing() {
        let config = TrainingConfig::default();

        assert!((config.get_beta(0) - 0.4).abs() < 0.001);
        assert!((config.get_beta(100_000) - 1.0).abs() < 0.001);
    }
}
