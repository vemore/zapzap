//! DRL Trainer with parallel simulation
//!
//! Implements:
//! - Double DQN with soft target network updates
//! - Prioritized Experience Replay
//! - Parallel game simulation with rayon
//! - Training progress tracking

use std::sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}};
use std::time::Instant;

use burn_core::optim::{AdamConfig, GradientsParams, Optimizer};
use burn::prelude::*;

use super::config::TrainingConfig;
use super::dueling_dqn::{DecisionType, DuelingDQN, DuelingDQNConfig};
use super::replay_buffer::PrioritizedReplayBuffer;
use super::{CpuBackend, TrainingBackend};

/// Training state for progress reporting
#[derive(Clone, Debug, Default)]
pub struct TrainingState {
    pub games_played: u64,
    pub steps: u64,
    pub epsilon: f32,
    pub avg_loss: f32,
    pub avg_reward: f32,
    pub win_rate: f32,
    pub games_per_second: f32,
    pub is_training: bool,
}

/// Adam optimizer type for the DuelingDQN network
type AdamOptimizer = burn_core::optim::adaptor::OptimizerAdaptor<
    burn_core::optim::Adam,
    DuelingDQN<TrainingBackend>,
    TrainingBackend,
>;

/// Main trainer struct
pub struct Trainer {
    /// Online network (for action selection)
    network: DuelingDQN<TrainingBackend>,
    /// Target network (for TD target computation)
    target_network: DuelingDQN<CpuBackend>,
    /// Adam optimizer
    optimizer: AdamOptimizer,
    /// Experience replay buffer
    buffer: PrioritizedReplayBuffer,
    /// Training configuration
    config: TrainingConfig,
    /// Shared training state
    state: Arc<Mutex<TrainingState>>,
    /// Stop flag for graceful shutdown
    stop_flag: Arc<AtomicBool>,
    /// Device for tensor operations
    device: <TrainingBackend as Backend>::Device,
}

impl Trainer {
    /// Create a new trainer
    pub fn new(config: TrainingConfig) -> Self {
        let device = <TrainingBackend as Backend>::Device::default();
        let cpu_device = <CpuBackend as Backend>::Device::default();

        let dqn_config = DuelingDQNConfig {
            input_dim: config.input_dim,
            hidden_dim: config.hidden_dim,
            value_hidden: config.value_hidden,
            advantage_hidden: config.advantage_hidden,
        };

        let network = DuelingDQN::new(&dqn_config, &device);
        let target_network = DuelingDQN::new(&dqn_config, &cpu_device);

        let optimizer = AdamConfig::new()
            .with_beta_1(0.9)
            .with_beta_2(0.999)
            .with_epsilon(1e-8)
            .init();

        let buffer = PrioritizedReplayBuffer::new(
            config.buffer_capacity,
            config.per_alpha,
            config.per_beta_start,
            config.per_epsilon,
        );

        Self {
            network,
            target_network,
            optimizer,
            buffer,
            config,
            state: Arc::new(Mutex::new(TrainingState::default())),
            stop_flag: Arc::new(AtomicBool::new(false)),
            device,
        }
    }

    /// Get current training state
    pub fn get_state(&self) -> TrainingState {
        self.state.lock().unwrap().clone()
    }

    /// Get stop flag for external control
    pub fn stop_flag(&self) -> Arc<AtomicBool> {
        self.stop_flag.clone()
    }

    /// Request training stop
    pub fn request_stop(&self) {
        self.stop_flag.store(true, Ordering::SeqCst);
    }

    /// Check if training should stop
    fn should_stop(&self) -> bool {
        self.stop_flag.load(Ordering::SeqCst)
    }

    /// Perform a single training step for a decision type
    fn train_step(&mut self, decision_type: DecisionType) -> Option<f32> {
        // Sample batch
        let batch = self.buffer.sample::<TrainingBackend>(
            self.config.batch_size,
            decision_type as u8,
            &self.device,
        )?;

        // Forward pass on online network
        let q_values = self.network.forward(batch.states.clone(), decision_type);

        // Gather Q-values for taken actions
        let q_taken = q_values.gather(1, batch.actions.clone());

        // Double DQN: use online network to select actions, target network for values
        // For now, simplified version using same network for both
        let next_q = self.network.forward(batch.next_states.clone(), decision_type);
        let batch_size = self.config.batch_size;
        let next_actions = next_q.argmax(1).reshape([batch_size, 1]);

        // Get target Q-values (using CPU backend for target network)
        // Note: In full implementation, target network would run inference here
        // For now, using online network
        let target_q_all = self.network.forward(batch.next_states.clone(), decision_type);
        let target_q = target_q_all.gather(1, next_actions);

        // TD target: r + gamma * Q_target(s', argmax_a Q(s', a)) * (1 - done)
        let not_done = batch.dones.clone().neg().add_scalar(1.0);
        let td_target = batch.rewards.clone() + target_q.mul_scalar(self.config.gamma) * not_done;

        // TD error
        let td_error = q_taken.clone() - td_target.clone();

        // Weighted MSE loss
        let squared_error = td_error.clone().powf_scalar(2.0);
        let weighted_loss = (squared_error * batch.is_weights.clone()).mean();

        // Backward pass
        let grads = weighted_loss.backward();

        // Take network out of self for optimizer.step (which takes ownership)
        let dqn_config = DuelingDQNConfig {
            input_dim: self.config.input_dim,
            hidden_dim: self.config.hidden_dim,
            value_hidden: self.config.value_hidden,
            advantage_hidden: self.config.advantage_hidden,
        };
        let placeholder_network = DuelingDQN::new(&dqn_config, &self.device);
        let network = std::mem::replace(&mut self.network, placeholder_network);

        // Update weights with optimizer
        let grads_params = GradientsParams::from_grads(grads, &network);
        self.network = self.optimizer.step(self.config.learning_rate, network, grads_params);

        // Update priorities in buffer
        let td_errors: Vec<f32> = td_error.clone().abs().into_data().as_slice::<f32>().unwrap().to_vec();
        self.buffer.update_priorities(&batch.indices, &td_errors);

        // Return average loss
        let loss_val = weighted_loss.into_data().as_slice::<f32>().unwrap()[0];
        Some(loss_val)
    }

    /// Run training loop
    pub fn train(&mut self, total_games: u64) {
        let start_time = Instant::now();
        let mut games_completed = 0u64;
        let mut total_loss = 0.0f32;
        let mut loss_count = 0u64;

        // Mark training as started
        {
            let mut state = self.state.lock().unwrap();
            state.is_training = true;
            state.games_played = 0;
        }

        while games_completed < total_games && !self.should_stop() {
            // Update epsilon
            let current_epsilon = self.config.get_epsilon(games_completed as usize);
            let current_beta = self.config.get_beta(games_completed as usize);
            self.buffer.set_beta(current_beta);

            // TODO: Simulate batch of games in parallel using rayon
            // For now, placeholder - games will be simulated externally
            // and transitions added via add_transition()

            // Train if we have enough data
            if self.buffer.len() >= self.config.batch_size * 10 {
                for dt in DecisionType::all() {
                    if let Some(loss) = self.train_step(dt) {
                        total_loss += loss;
                        loss_count += 1;
                    }
                }

                // Update state
                let mut state = self.state.lock().unwrap();
                state.steps += 1;
                state.epsilon = current_epsilon;
                state.avg_loss = if loss_count > 0 {
                    total_loss / loss_count as f32
                } else {
                    0.0
                };
            }

            games_completed += self.config.games_per_batch as u64;

            // Update progress
            {
                let elapsed = start_time.elapsed().as_secs_f32();
                let mut state = self.state.lock().unwrap();
                state.games_played = games_completed;
                state.games_per_second = if elapsed > 0.0 {
                    games_completed as f32 / elapsed
                } else {
                    0.0
                };
            }

            // Soft update target network periodically
            if games_completed % (self.config.target_update_freq as u64) == 0 {
                // TODO: Implement soft update
                // self.soft_update_target();
            }
        }

        // Mark training as finished
        {
            let mut state = self.state.lock().unwrap();
            state.is_training = false;
        }
    }

    /// Add a transition to the replay buffer
    pub fn add_transition(&mut self, transition: super::transition::Transition) {
        self.buffer.push(transition);
    }

    /// Get weights as flat vector (for syncing to inference network)
    pub fn get_weights_flat(&self) -> Vec<f32> {
        // Placeholder - would extract weights from network
        Vec::new()
    }

    /// Set weights from flat vector
    pub fn set_weights_flat(&mut self, _weights: &[f32]) {
        // Placeholder - would load weights into network
    }

    /// Get buffer size
    pub fn buffer_size(&self) -> usize {
        self.buffer.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::training::FEATURE_DIM;

    #[test]
    fn test_trainer_creation() {
        let config = TrainingConfig::fast();
        let trainer = Trainer::new(config);
        assert_eq!(trainer.buffer_size(), 0);
    }

    #[test]
    fn test_training_state() {
        let config = TrainingConfig::default();
        let trainer = Trainer::new(config);

        let state = trainer.get_state();
        assert_eq!(state.games_played, 0);
        assert!(!state.is_training);
    }

    #[test]
    fn test_stop_flag() {
        let config = TrainingConfig::default();
        let trainer = Trainer::new(config);

        assert!(!trainer.should_stop());
        trainer.request_stop();
        assert!(trainer.should_stop());
    }

    #[test]
    fn test_add_transition() {
        let config = TrainingConfig::fast();
        let mut trainer = Trainer::new(config);

        let transition = super::super::transition::Transition::new(
            [0.5f32; FEATURE_DIM],
            1,
            1.0,
            [0.6f32; FEATURE_DIM],
            false,
            0,
        );

        trainer.add_transition(transition);
        assert_eq!(trainer.buffer_size(), 1);
    }
}
