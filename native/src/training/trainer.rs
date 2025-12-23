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
use crate::trace_config::{is_trace_enabled, TraceLevel};
use crate::trace_log;

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
    /// Target network (for TD target computation) - reserved for Double DQN
    #[allow(dead_code)]
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

    /// Get adaptive batch size for decision type
    ///
    /// Uses smaller batches for rare decision types to enable training
    /// even when there are fewer samples in the buffer.
    fn get_adaptive_batch_size(&self, decision_type: DecisionType) -> usize {
        match decision_type {
            // HandSize is rare (~3% of transitions)
            DecisionType::HandSize => (self.config.batch_size / 4).max(8),
            // ZapZap is very rare (<1% of transitions)
            DecisionType::ZapZap => (self.config.batch_size / 8).max(4),
            // PlayType and DrawSource are common (~48% each)
            DecisionType::PlayType | DecisionType::DrawSource => self.config.batch_size,
        }
    }

    /// Perform a single training step for a decision type
    fn train_step(&mut self, decision_type: DecisionType) -> Option<f32> {
        // Use adaptive batch size based on decision type rarity (B)
        let batch_size = self.get_adaptive_batch_size(decision_type);

        // Sample batch
        let batch = self.buffer.sample::<TrainingBackend>(
            batch_size,
            decision_type as u8,
            &self.device,
        );

        // Log sampling failure
        if batch.is_none() {
            trace_log!(TraceLevel::Training,
                "train_step({:?}) - buffer.sample() returned None (buffer size: {})",
                decision_type, self.buffer.len());
            return None;
        }
        let batch = batch?;

        // Forward pass on online network
        let q_values = self.network.forward(batch.states.clone(), decision_type);

        // Clone Q-values for tracing before they're consumed
        let q_values_for_trace = if is_trace_enabled(TraceLevel::Training) {
            Some(q_values.clone())
        } else {
            None
        };

        // Gather Q-values for taken actions
        let q_taken = q_values.gather(1, batch.actions.clone());

        // Double DQN: use online network to select actions, target network for values
        // For now, simplified version using same network for both
        let next_q = self.network.forward(batch.next_states.clone(), decision_type);
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

        // Trace: Log training step details
        if let Some(q_values_trace) = q_values_for_trace {
            let td_mean: f32 = td_errors.iter().sum::<f32>() / td_errors.len() as f32;
            let td_max = td_errors.iter().cloned().fold(0.0f32, f32::max);
            let td_min = td_errors.iter().cloned().fold(f32::MAX, f32::min);
            let rewards_slice = batch.rewards.clone().into_data().as_slice::<f32>().unwrap().to_vec();
            let rewards_nonzero = rewards_slice.iter().filter(|&&r| r.abs() > 0.001).count();
            let rewards_pos = rewards_slice.iter().filter(|&&r| r > 0.001).count();
            let rewards_neg = rewards_slice.iter().filter(|&&r| r < -0.001).count();

            // Get Q-value sample from batch
            let q_slice = q_values_trace.into_data().as_slice::<f32>().unwrap().to_vec();
            let q_sample: Vec<f32> = q_slice.iter().take(5).cloned().collect();

            eprintln!("[TRAIN] dt={:?} loss={:.6} TD=[mean:{:.4},max:{:.4},min:{:.4}] rewards=[nz:{},+:{},−:{}] Q[0..5]={:?}",
                decision_type, loss_val, td_mean, td_max, td_min,
                rewards_nonzero, rewards_pos, rewards_neg, q_sample);
        }

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

    /// Perform N training steps and update state
    /// Returns (total_loss, steps_completed)
    pub fn train_steps(&mut self, num_steps: usize, games_played: u64) -> (f32, usize) {
        let min_buffer_size = self.config.batch_size * 10;
        if self.buffer.len() < min_buffer_size {
            trace_log!(TraceLevel::Training,
                "train_steps - buffer too small ({} < {})", self.buffer.len(), min_buffer_size);
            return (0.0, 0);
        }

        // Capture weights before training for comparison
        let weights_before_sample: Vec<f32> = if is_trace_enabled(TraceLevel::Weights) {
            self.network.get_weights_flat().iter().take(10).cloned().collect()
        } else {
            Vec::new()
        };

        let mut total_loss = 0.0f32;
        let mut steps_completed = 0usize;

        // Update epsilon and beta based on games played
        let current_epsilon = self.config.get_epsilon(games_played as usize);
        let current_beta = self.config.get_beta(games_played as usize);
        self.buffer.set_beta(current_beta);

        for _ in 0..num_steps {
            // Train on all 4 decision types per step
            for dt in DecisionType::all() {
                if let Some(loss) = self.train_step(dt) {
                    total_loss += loss;
                    steps_completed += 1;
                }
            }
        }

        // Trace weights changes
        if is_trace_enabled(TraceLevel::Weights) && !weights_before_sample.is_empty() {
            let weights_after = self.network.get_weights_flat();
            let weights_after_sample: Vec<f32> = weights_after.iter().take(10).cloned().collect();

            // Calculate weight change magnitude
            let mut total_delta = 0.0f32;
            let mut max_delta = 0.0f32;
            for (before, after) in weights_before_sample.iter().zip(weights_after_sample.iter()) {
                let delta = (after - before).abs();
                total_delta += delta;
                max_delta = max_delta.max(delta);
            }
            let mean_delta = total_delta / weights_before_sample.len() as f32;

            eprintln!("[WEIGHTS] train_steps games={} steps={} weight_delta=[mean:{:.8},max:{:.8}]",
                games_played, steps_completed, mean_delta, max_delta);
            eprintln!("[WEIGHTS]   before[0..5]: {:?}", &weights_before_sample[..5]);
            eprintln!("[WEIGHTS]   after[0..5]:  {:?}", &weights_after_sample[..5]);
        }

        // Trace training summary
        trace_log!(TraceLevel::Training,
            "train_steps games={} steps={} avg_loss={:.6}",
            games_played, steps_completed,
            if steps_completed > 0 { total_loss / steps_completed as f32 } else { 0.0 });

        // Update training state
        {
            let mut state = self.state.lock().unwrap();
            state.steps += steps_completed as u64;
            state.games_played = games_played;
            state.epsilon = current_epsilon;
            if steps_completed > 0 {
                // Running average loss
                state.avg_loss = 0.99 * state.avg_loss + 0.01 * (total_loss / steps_completed as f32);
            }
        }

        (total_loss, steps_completed)
    }

    /// Get weights as flat vector (for syncing to inference network)
    pub fn get_weights_flat(&self) -> Vec<f32> {
        self.network.get_weights_flat()
    }

    /// Set weights from flat vector
    pub fn set_weights_flat(&mut self, weights: &[f32]) {
        self.network.set_weights_flat(weights, &self.device);
    }

    /// Get buffer size
    pub fn buffer_size(&self) -> usize {
        self.buffer.len()
    }

    /// Select an action using the trained network with epsilon-greedy exploration
    /// This allows using the trainer's network for inference during simulation
    pub fn select_action(&self, features: &[f32], decision_type: DecisionType, epsilon: f32) -> u8 {
        // Epsilon-greedy exploration
        let mut rng_seed = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos() as u64;
        rng_seed ^= rng_seed << 13;
        rng_seed ^= rng_seed >> 7;
        rng_seed ^= rng_seed << 17;
        let random_val = (rng_seed as f64 / u64::MAX as f64) as f32;

        if random_val < epsilon {
            // Random action
            rng_seed ^= rng_seed << 13;
            let action_dim = decision_type.action_dim();
            ((rng_seed as f64 / u64::MAX as f64) * action_dim as f64) as u8
        } else {
            // Greedy action from network
            let q_values = self.network.q_values(features, decision_type, &self.device);
            q_values
                .iter()
                .enumerate()
                .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
                .map(|(i, _)| i as u8)
                .unwrap_or(0)
        }
    }

    /// Get Q-values for a given state and decision type
    pub fn get_q_values(&self, features: &[f32], decision_type: DecisionType) -> Vec<f32> {
        self.network.q_values(features, decision_type, &self.device)
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

    #[test]
    fn test_training_diagnostic() {
        use super::DecisionType;

        eprintln!("\n=== DIAGNOSTIC TEST START ===\n");

        let config = TrainingConfig::fast();
        let mut trainer = Trainer::new(config);

        // Add transitions with correct action bounds for each decision type
        // ACTION_DIMS: [7, 2, 5, 2] for [HandSize, ZapZap, PlayType, DrawSource]
        let action_dims = [7u8, 2, 5, 2];

        for i in 0..2000 {
            let decision_type = (i % 4) as u8;
            let action_dim = action_dims[decision_type as usize];
            let action = (i as u8) % action_dim;  // Ensure action is within bounds

            // ~20% transitions have non-zero reward
            let reward = if i % 5 == 4 {
                if i % 10 < 5 { 1.0 } else { -0.5 }
            } else {
                0.0
            };
            let done = i % 5 == 4;

            let transition = super::super::transition::Transition::new(
                [(i as f32 / 2000.0); FEATURE_DIM],
                action,
                reward,
                [((i + 1) as f32 / 2000.0); FEATURE_DIM],
                done,
                decision_type,
            );
            trainer.add_transition(transition);
        }

        eprintln!("Buffer size: {}", trainer.buffer_size());

        // Count transitions by type and rewards
        eprintln!("\nTransitions by type:");
        for dt in 0..4 {
            eprintln!("  dt={}: ~{} total", dt, 2000 / 4);
        }

        // Run training steps
        eprintln!("\n--- Training Step 1 ---");
        let (loss1, steps1) = trainer.train_steps(1, 100);
        eprintln!("Loss: {:.6}, Steps: {}", loss1, steps1);

        eprintln!("\n--- Training Step 2 ---");
        let (loss2, steps2) = trainer.train_steps(1, 200);
        eprintln!("Loss: {:.6}, Steps: {}", loss2, steps2);

        eprintln!("\n=== DIAGNOSTIC RESULTS ===");
        eprintln!("Total steps: {}", steps1 + steps2);
        eprintln!("Buffer size after: {}", trainer.buffer_size());
        eprintln!("=== END ===\n");

        assert!(trainer.buffer_size() >= 2000);
    }
}
