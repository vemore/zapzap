//! ZapZap Native - High-performance game simulation for DRL training
//!
//! This module provides N-API bindings for the Rust game engine.

#![deny(clippy::all)]

pub mod card_analyzer;
pub mod feature_extractor;
pub mod game_state;
pub mod headless_engine;
pub mod lightweight_dqn;
pub mod strategies;
pub mod training;

use headless_engine::{HeadlessGameEngine, StrategyType};
use napi_derive::napi;

// ============================================================================
// Card Analyzer Exports
// ============================================================================

/// Get card points for zapzap calculation
/// Jokers (52-53) = 0 points
#[napi]
pub fn get_card_points(card_id: u8) -> u8 {
    card_analyzer::get_card_points(card_id)
}

/// Get card rank (0-12), returns 255 for jokers
#[napi]
pub fn get_rank(card_id: u8) -> u8 {
    card_analyzer::get_rank(card_id)
}

/// Get card suit (0-3), returns 255 for jokers
#[napi]
pub fn get_suit(card_id: u8) -> u8 {
    card_analyzer::get_suit(card_id)
}

/// Check if card is a joker
#[napi]
pub fn is_joker(card_id: u8) -> bool {
    card_analyzer::is_joker(card_id)
}

/// Calculate total hand value (for zapzap eligibility)
/// Jokers count as 0 points
#[napi]
pub fn calculate_hand_value(hand: Vec<u8>) -> u16 {
    card_analyzer::calculate_hand_value(&hand)
}

/// Calculate hand score for end of round
/// Jokers = 0 if lowest hand, 25 otherwise
#[napi]
pub fn calculate_hand_score(hand: Vec<u8>, is_lowest: bool) -> u16 {
    card_analyzer::calculate_hand_score(&hand, is_lowest)
}

/// Check if player can call ZapZap (hand value <= 5)
#[napi]
pub fn can_call_zapzap(hand: Vec<u8>) -> bool {
    card_analyzer::can_call_zapzap(&hand)
}

/// Check if cards form a valid same-rank combination
#[napi]
pub fn is_valid_same_rank(cards: Vec<u8>) -> bool {
    card_analyzer::is_valid_same_rank(&cards)
}

/// Check if cards form a valid sequence
#[napi]
pub fn is_valid_sequence(cards: Vec<u8>) -> bool {
    card_analyzer::is_valid_sequence(&cards)
}

/// Check if a play is valid
#[napi]
pub fn is_valid_play(cards: Vec<u8>) -> bool {
    card_analyzer::is_valid_play(&cards)
}

/// Find all valid same-rank plays in hand
#[napi]
pub fn find_same_rank_plays(hand: Vec<u8>) -> Vec<Vec<u8>> {
    card_analyzer::find_same_rank_plays(&hand)
        .into_iter()
        .map(|play| play.into_vec())
        .collect()
}

/// Find all valid sequence plays in hand
#[napi]
pub fn find_sequence_plays(hand: Vec<u8>) -> Vec<Vec<u8>> {
    card_analyzer::find_sequence_plays(&hand)
        .into_iter()
        .map(|play| play.into_vec())
        .collect()
}

/// Find all valid plays in hand
#[napi]
pub fn find_all_valid_plays(hand: Vec<u8>) -> Vec<Vec<u8>> {
    card_analyzer::find_all_valid_plays(&hand)
        .into_iter()
        .map(|play| play.into_vec())
        .collect()
}

/// Find the play that removes the most points from hand
#[napi]
pub fn find_max_point_play(hand: Vec<u8>) -> Option<Vec<u8>> {
    card_analyzer::find_max_point_play(&hand).map(|play| play.into_vec())
}

/// Run benchmark: find all valid plays N times
#[napi]
pub fn benchmark_find_all_valid_plays(hand: Vec<u8>, iterations: u32) -> u32 {
    let mut total_plays = 0u32;
    for _ in 0..iterations {
        let plays = card_analyzer::find_all_valid_plays(&hand);
        total_plays += plays.len() as u32;
    }
    total_plays
}

// ============================================================================
// Game Simulation Exports
// ============================================================================

/// Game result from simulation
#[napi(object)]
pub struct NativeGameResult {
    pub winner: u8,
    pub total_rounds: u16,
    pub final_scores: Vec<u16>,
    pub was_golden_score: bool,
    pub player_count: u8,
}

/// Run a single game with specified strategies
/// Strategy types: "random", "hard", "hard_vince", "drl"
#[napi]
pub fn run_game(strategy_types: Vec<String>, seed: Option<u32>) -> NativeGameResult {
    let strategies: Vec<StrategyType> = strategy_types
        .iter()
        .map(|s| match s.to_lowercase().as_str() {
            "hard" | "hard_vince" => StrategyType::Hard,
            "drl" => StrategyType::DRL,
            _ => StrategyType::Random,
        })
        .collect();

    let mut engine = match seed {
        Some(s) => HeadlessGameEngine::with_seed(strategies, s as u64),
        None => HeadlessGameEngine::new(strategies),
    };

    let result = engine.run_game();

    NativeGameResult {
        winner: result.winner,
        total_rounds: result.total_rounds,
        final_scores: result.final_scores[..result.player_count as usize].to_vec(),
        was_golden_score: result.was_golden_score,
        player_count: result.player_count,
    }
}

/// Run multiple games and return statistics
#[napi(object)]
pub struct BatchGameStats {
    pub games_played: u32,
    pub wins: Vec<u32>,
    pub avg_rounds: f64,
    pub total_time_ms: f64,
    pub games_per_second: f64,
}

/// Run multiple games in batch for performance testing
/// Strategy types: "random", "hard", "hard_vince", "drl"
#[napi]
pub fn run_games_batch(
    strategy_types: Vec<String>,
    game_count: u32,
    base_seed: Option<u32>,
) -> BatchGameStats {
    let strategies: Vec<StrategyType> = strategy_types
        .iter()
        .map(|s| match s.to_lowercase().as_str() {
            "hard" | "hard_vince" => StrategyType::Hard,
            "drl" => StrategyType::DRL,
            _ => StrategyType::Random,
        })
        .collect();

    let player_count = strategies.len();
    let mut wins = vec![0u32; player_count];
    let mut total_rounds = 0u64;

    let start = std::time::Instant::now();

    for i in 0..game_count {
        let seed = base_seed.map(|s| s as u64 + i as u64).unwrap_or(i as u64);
        let mut engine = HeadlessGameEngine::with_seed(strategies.clone(), seed);
        let result = engine.run_game();

        wins[result.winner as usize] += 1;
        total_rounds += result.total_rounds as u64;
    }

    let elapsed = start.elapsed();
    let total_ms = elapsed.as_secs_f64() * 1000.0;
    let games_per_second = if total_ms > 0.0 {
        (game_count as f64) / (total_ms / 1000.0)
    } else {
        0.0
    };

    BatchGameStats {
        games_played: game_count,
        wins,
        avg_rounds: total_rounds as f64 / game_count as f64,
        total_time_ms: total_ms,
        games_per_second,
    }
}

/// Benchmark game simulation performance
#[napi]
pub fn benchmark_simulation(player_count: u8, game_count: u32) -> f64 {
    let strategies: Vec<StrategyType> = (0..player_count).map(|_| StrategyType::Hard).collect();

    let start = std::time::Instant::now();

    for seed in 0..game_count {
        let mut engine = HeadlessGameEngine::with_seed(strategies.clone(), seed as u64);
        let _ = engine.run_game();
    }

    let elapsed = start.elapsed();
    let total_ms = elapsed.as_secs_f64() * 1000.0;

    if total_ms > 0.0 {
        (game_count as f64) / (total_ms / 1000.0)
    } else {
        0.0
    }
}

// ============================================================================
// Feature Extractor Exports
// ============================================================================

use feature_extractor::FeatureExtractor;

/// Get feature dimension (45)
#[napi]
pub fn get_feature_dimension() -> u32 {
    feature_extractor::FEATURE_DIM as u32
}

/// Extract features from a game state for ML
/// Returns 45-dimensional feature vector
#[napi]
pub fn extract_features(
    hand: Vec<u8>,
    player_index: u8,
    scores: Vec<u16>,
    opponent_hand_sizes: Vec<u8>,
    round_number: u16,
    deck_size: u8,
    last_cards_played: Vec<u8>,
    is_golden_score: bool,
    eliminated_players: Vec<u8>,
) -> Vec<f32> {
    // Build a minimal GameState for feature extraction
    let mut state = game_state::GameState::new(scores.len() as u8);

    // Set player hand
    state.hands[player_index as usize].clear();
    state.hands[player_index as usize].extend_from_slice(&hand);

    // Set opponent hand sizes (approximate with dummy cards)
    for (i, &size) in opponent_hand_sizes.iter().enumerate() {
        if i != player_index as usize {
            state.hands[i].clear();
            for j in 0..size {
                state.hands[i].push(j); // Dummy cards
            }
        }
    }

    // Set scores
    for (i, &score) in scores.iter().enumerate() {
        if i < state.scores.len() {
            state.scores[i] = score;
        }
    }

    // Set game context
    state.round_number = round_number;
    state.deck = vec![0; deck_size as usize];
    state.last_cards_played.clear();
    state.last_cards_played.extend_from_slice(&last_cards_played);
    state.is_golden_score = is_golden_score;

    // Set eliminated players
    for &p in &eliminated_players {
        state.eliminate_player(p);
    }

    let features = FeatureExtractor::extract(&state, player_index);
    features.to_vec()
}

/// Extract features for hand size decision (before cards are dealt)
#[napi]
pub fn extract_hand_size_features(
    active_player_count: u8,
    is_golden_score: bool,
    my_score: u16,
) -> Vec<f32> {
    let features = FeatureExtractor::extract_hand_size_features(
        active_player_count,
        is_golden_score,
        my_score,
    );
    features.to_vec()
}

/// Benchmark feature extraction
#[napi]
pub fn benchmark_feature_extraction(iterations: u32) -> f64 {
    let mut state = game_state::GameState::new(4);
    // Setup a realistic hand
    state.hands[0].clear();
    state.hands[0].extend_from_slice(&[0, 13, 5, 18, 52]); // Mixed hand with joker

    let start = std::time::Instant::now();

    for _ in 0..iterations {
        let _ = FeatureExtractor::extract(&state, 0);
    }

    let elapsed = start.elapsed();
    let total_us = elapsed.as_micros() as f64;

    if iterations > 0 {
        total_us / iterations as f64
    } else {
        0.0
    }
}

// ============================================================================
// Lightweight DQN Exports
// ============================================================================

use lightweight_dqn::{DecisionType, LightweightDQN};
use std::sync::Mutex;

// Thread-local DQN instance for inference
static DQN_INSTANCE: Mutex<Option<LightweightDQN>> = Mutex::new(None);

/// Initialize the DQN with random weights
#[napi]
pub fn dqn_init(seed: Option<u32>) -> bool {
    let mut dqn_guard = DQN_INSTANCE.lock().unwrap();
    *dqn_guard = Some(match seed {
        Some(s) => LightweightDQN::with_seed(s as u64),
        None => LightweightDQN::new(),
    });
    true
}

/// Get Q-values for a decision type
/// decision_type: "handSize", "zapzap", "playType", "drawSource"
#[napi]
pub fn dqn_predict(features: Vec<f64>, decision_type: String) -> Vec<f64> {
    let dqn_guard = DQN_INSTANCE.lock().unwrap();
    let dqn = dqn_guard.as_ref().expect("DQN not initialized. Call dqn_init first.");

    let dt = DecisionType::from_str(&decision_type)
        .unwrap_or(DecisionType::PlayType);

    // Convert f64 to f32 for internal processing
    let features_f32: Vec<f32> = features.iter().map(|&x| x as f32).collect();
    let result = dqn.predict(&features_f32, dt);
    // Convert back to f64 for JS
    result.into_iter().map(|x| x as f64).collect()
}

/// Select action using epsilon-greedy policy
#[napi]
pub fn dqn_select_action(features: Vec<f64>, decision_type: String, epsilon: f64) -> u32 {
    let mut dqn_guard = DQN_INSTANCE.lock().unwrap();
    let dqn = dqn_guard.as_mut().expect("DQN not initialized. Call dqn_init first.");

    let dt = DecisionType::from_str(&decision_type)
        .unwrap_or(DecisionType::PlayType);

    let features_f32: Vec<f32> = features.iter().map(|&x| x as f32).collect();
    dqn.select_action(&features_f32, dt, epsilon as f32) as u32
}

/// Get greedy action (best Q-value)
#[napi]
pub fn dqn_greedy_action(features: Vec<f64>, decision_type: String) -> u32 {
    let dqn_guard = DQN_INSTANCE.lock().unwrap();
    let dqn = dqn_guard.as_ref().expect("DQN not initialized. Call dqn_init first.");

    let dt = DecisionType::from_str(&decision_type)
        .unwrap_or(DecisionType::PlayType);

    let features_f32: Vec<f32> = features.iter().map(|&x| x as f32).collect();
    dqn.greedy_action(&features_f32, dt) as u32
}

/// Benchmark DQN inference
#[napi]
pub fn benchmark_dqn_inference(iterations: u32) -> f64 {
    let dqn = LightweightDQN::new();
    let features = vec![0.5f32; feature_extractor::FEATURE_DIM];

    let start = std::time::Instant::now();

    for _ in 0..iterations {
        let _ = dqn.predict(&features, DecisionType::PlayType);
    }

    let elapsed = start.elapsed();
    let total_us = elapsed.as_micros() as f64;

    if iterations > 0 {
        total_us / iterations as f64
    } else {
        0.0
    }
}

// ============================================================================
// Training Module Exports
// ============================================================================

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use training::{Trainer, TrainingConfig, TrainingState as InternalTrainingState};

/// Training configuration exposed to JS
#[napi(object)]
pub struct NativeTrainingConfig {
    /// Total number of games to train on
    pub total_games: u32,
    /// Number of games per batch
    pub games_per_batch: u32,
    /// Batch size for training
    pub batch_size: u32,
    /// Learning rate
    pub learning_rate: f64,
    /// Starting epsilon for exploration
    pub epsilon_start: f64,
    /// Ending epsilon for exploration
    pub epsilon_end: f64,
    /// Number of games over which to decay epsilon
    pub epsilon_decay: u32,
    /// Discount factor (gamma)
    pub gamma: f64,
    /// Soft update rate (tau)
    pub tau: f64,
    /// Replay buffer capacity
    pub buffer_capacity: u32,
    /// Target network update frequency
    pub target_update_freq: u32,
}

impl Default for NativeTrainingConfig {
    fn default() -> Self {
        Self {
            total_games: 100000,
            games_per_batch: 100,
            batch_size: 64,
            learning_rate: 0.0005,
            epsilon_start: 1.0,
            epsilon_end: 0.01,
            epsilon_decay: 50000,
            gamma: 0.99,
            tau: 0.005,
            buffer_capacity: 100000,
            target_update_freq: 1000,
        }
    }
}

/// Training state exposed to JS
#[napi(object)]
pub struct NativeTrainingState {
    /// Number of games played
    pub games_played: u32,
    /// Number of training steps
    pub steps: u32,
    /// Current epsilon value
    pub epsilon: f64,
    /// Average loss (recent)
    pub avg_loss: f64,
    /// Average reward (recent)
    pub avg_reward: f64,
    /// Win rate (recent)
    pub win_rate: f64,
    /// Games per second
    pub games_per_second: f64,
    /// Whether training is currently running
    pub is_training: bool,
}

impl From<InternalTrainingState> for NativeTrainingState {
    fn from(state: InternalTrainingState) -> Self {
        Self {
            games_played: state.games_played as u32,
            steps: state.steps as u32,
            epsilon: state.epsilon as f64,
            avg_loss: state.avg_loss as f64,
            avg_reward: state.avg_reward as f64,
            win_rate: state.win_rate as f64,
            games_per_second: state.games_per_second as f64,
            is_training: state.is_training,
        }
    }
}

// Global trainer instance
static TRAINER: Mutex<Option<Trainer>> = Mutex::new(None);
static TRAINING_STOP_FLAG: Mutex<Option<Arc<AtomicBool>>> = Mutex::new(None);

/// Create a new trainer with the given configuration
#[napi]
pub fn trainer_create(config: NativeTrainingConfig) -> bool {
    let training_config = TrainingConfig {
        input_dim: 45,
        hidden_dim: 128,
        value_hidden: 64,
        advantage_hidden: 32,
        learning_rate: config.learning_rate,
        batch_size: config.batch_size as usize,
        buffer_capacity: config.buffer_capacity as usize,
        gamma: config.gamma as f32,
        tau: config.tau as f32,
        gradient_clip: 1.0,
        epsilon_start: config.epsilon_start as f32,
        epsilon_end: config.epsilon_end as f32,
        epsilon_decay_steps: config.epsilon_decay as usize,
        per_alpha: 0.6,
        per_beta_start: 0.4,
        per_beta_end: 1.0,
        per_epsilon: 0.01,
        target_update_freq: config.target_update_freq as usize,
        games_per_batch: config.games_per_batch as usize,
        train_interval: 10,
        save_interval: 10000,
        num_workers: num_cpus::get(),
    };

    let trainer = Trainer::new(training_config);
    let stop_flag = trainer.stop_flag();

    *TRAINER.lock().unwrap() = Some(trainer);
    *TRAINING_STOP_FLAG.lock().unwrap() = Some(stop_flag);

    true
}

/// Get current training state
#[napi]
pub fn trainer_get_state() -> Option<NativeTrainingState> {
    TRAINER
        .lock()
        .unwrap()
        .as_ref()
        .map(|t| t.get_state().into())
}

/// Add a transition to the replay buffer
#[napi]
pub fn trainer_add_transition(
    state: Vec<f64>,
    action: u8,
    reward: f64,
    next_state: Vec<f64>,
    done: bool,
    decision_type: u8,
) -> bool {
    let mut trainer_guard = TRAINER.lock().unwrap();
    let trainer = match trainer_guard.as_mut() {
        Some(t) => t,
        None => return false,
    };

    // Convert to fixed-size arrays
    let mut state_arr = [0.0f32; 45];
    let mut next_state_arr = [0.0f32; 45];

    for (i, &v) in state.iter().take(45).enumerate() {
        state_arr[i] = v as f32;
    }
    for (i, &v) in next_state.iter().take(45).enumerate() {
        next_state_arr[i] = v as f32;
    }

    let transition = training::Transition::new(
        state_arr,
        action,
        reward as f32,
        next_state_arr,
        done,
        decision_type,
    );

    trainer.add_transition(transition);
    true
}

/// Get current replay buffer size
#[napi]
pub fn trainer_buffer_size() -> u32 {
    TRAINER
        .lock()
        .unwrap()
        .as_ref()
        .map(|t| t.buffer_size() as u32)
        .unwrap_or(0)
}

/// Request training to stop
#[napi]
pub fn trainer_request_stop() -> bool {
    if let Some(flag) = TRAINING_STOP_FLAG.lock().unwrap().as_ref() {
        flag.store(true, Ordering::SeqCst);
        true
    } else {
        false
    }
}

/// Check if training should stop
#[napi]
pub fn trainer_should_stop() -> bool {
    TRAINING_STOP_FLAG
        .lock()
        .unwrap()
        .as_ref()
        .map(|f| f.load(Ordering::SeqCst))
        .unwrap_or(false)
}

/// Get weights as flat vector
#[napi]
pub fn trainer_get_weights() -> Vec<f64> {
    TRAINER
        .lock()
        .unwrap()
        .as_ref()
        .map(|t| t.get_weights_flat().into_iter().map(|x| x as f64).collect())
        .unwrap_or_default()
}

/// Set weights from flat vector
#[napi]
pub fn trainer_set_weights(weights: Vec<f64>) -> bool {
    let mut trainer_guard = TRAINER.lock().unwrap();
    let trainer = match trainer_guard.as_mut() {
        Some(t) => t,
        None => return false,
    };

    let weights_f32: Vec<f32> = weights.iter().map(|&x| x as f32).collect();
    trainer.set_weights_flat(&weights_f32);
    true
}

// ============================================================================
// DRL Strategy Exports
// ============================================================================

use strategies::DRLStrategy;

static DRL_STRATEGY: Mutex<Option<DRLStrategy>> = Mutex::new(None);

/// Initialize DRL strategy for a player
#[napi]
pub fn drl_strategy_init(player_index: u8, epsilon: f64, seed: Option<u32>) -> bool {
    let mut strategy = match seed {
        Some(s) => DRLStrategy::with_seed(player_index, s as u64),
        None => DRLStrategy::new(player_index),
    };
    strategy.set_epsilon(epsilon as f32);

    *DRL_STRATEGY.lock().unwrap() = Some(strategy);
    true
}

/// Set epsilon for DRL strategy
#[napi]
pub fn drl_strategy_set_epsilon(epsilon: f64) -> bool {
    if let Some(strategy) = DRL_STRATEGY.lock().unwrap().as_mut() {
        strategy.set_epsilon(epsilon as f32);
        true
    } else {
        false
    }
}

/// Get action from DRL strategy given features
#[napi]
pub fn drl_strategy_get_action(features: Vec<f64>, decision_type: String) -> u32 {
    let mut strategy_guard = DRL_STRATEGY.lock().unwrap();
    let strategy = match strategy_guard.as_mut() {
        Some(s) => s,
        None => return 0,
    };

    let dt = match decision_type.to_lowercase().as_str() {
        "handsize" | "hand_size" => training::DecisionType::HandSize,
        "zapzap" | "zap_zap" => training::DecisionType::ZapZap,
        "playtype" | "play_type" => training::DecisionType::PlayType,
        "drawsource" | "draw_source" => training::DecisionType::DrawSource,
        _ => training::DecisionType::PlayType,
    };

    let features_f32: Vec<f32> = features.iter().map(|&x| x as f32).collect();
    let mut features_arr = [0.0f32; 45];
    for (i, &v) in features_f32.iter().take(45).enumerate() {
        features_arr[i] = v;
    }

    // Use the correct decision type from lightweight_dqn
    let lw_dt = match dt {
        training::DecisionType::HandSize => lightweight_dqn::DecisionType::HandSize,
        training::DecisionType::ZapZap => lightweight_dqn::DecisionType::ZapZap,
        training::DecisionType::PlayType => lightweight_dqn::DecisionType::PlayType,
        training::DecisionType::DrawSource => lightweight_dqn::DecisionType::DrawSource,
    };

    strategy.get_action(&features_arr, lw_dt) as u32
}

// ============================================================================
// Model I/O Exports
// ============================================================================

use training::{ModelIO, ModelMetadata};

/// Model metadata exposed to JS
#[napi(object)]
pub struct NativeModelMetadata {
    /// Model version
    pub version: String,
    /// Input dimension
    pub input_dim: u32,
    /// Hidden layer dimension
    pub hidden_dim: u32,
    /// Value stream hidden dimension
    pub value_hidden: u32,
    /// Advantage stream hidden dimension
    pub advantage_hidden: u32,
    /// Number of training steps
    pub training_steps: u32,
    /// Number of games played
    pub games_played: u32,
    /// Final epsilon value
    pub final_epsilon: f64,
    /// Average loss at save time
    pub avg_loss: f64,
    /// Win rate at save time
    pub win_rate: f64,
    /// Timestamp of save
    pub timestamp: String,
}

impl From<ModelMetadata> for NativeModelMetadata {
    fn from(meta: ModelMetadata) -> Self {
        Self {
            version: meta.version,
            input_dim: meta.input_dim as u32,
            hidden_dim: meta.hidden_dim as u32,
            value_hidden: meta.value_hidden as u32,
            advantage_hidden: meta.advantage_hidden as u32,
            training_steps: meta.training_steps as u32,
            games_played: meta.games_played as u32,
            final_epsilon: meta.final_epsilon as f64,
            avg_loss: meta.avg_loss as f64,
            win_rate: meta.win_rate as f64,
            timestamp: meta.timestamp,
        }
    }
}

/// Result of loading model weights with metadata (NAPI-compatible)
#[napi(object)]
pub struct NativeModelLoadResult {
    /// Model weights as f64 array
    pub weights: Vec<f64>,
    /// Optional metadata if available
    pub metadata: Option<NativeModelMetadata>,
}

/// Save model weights to file
#[napi]
pub fn model_save(path: String, weights: Vec<f64>) -> bool {
    let weights_f32: Vec<f32> = weights.iter().map(|&x| x as f32).collect();
    ModelIO::save_weights(&path, &weights_f32, None).is_ok()
}

/// Save model checkpoint with metadata
#[napi]
pub fn model_save_checkpoint(
    path: String,
    weights: Vec<f64>,
    training_steps: u32,
    games_played: u32,
    epsilon: f64,
    avg_loss: f64,
    win_rate: f64,
) -> bool {
    let weights_f32: Vec<f32> = weights.iter().map(|&x| x as f32).collect();
    let config = TrainingConfig::default();

    ModelIO::save_checkpoint(
        &path,
        &weights_f32,
        &config,
        training_steps as u64,
        games_played as u64,
        epsilon as f32,
        avg_loss as f32,
        win_rate as f32,
    ).is_ok()
}

/// Load model weights from file
#[napi]
pub fn model_load(path: String) -> Option<Vec<f64>> {
    ModelIO::load_weights(&path)
        .ok()
        .map(|(weights, _)| weights.into_iter().map(|x| x as f64).collect())
}

/// Load model weights and metadata from file
#[napi]
pub fn model_load_with_metadata(path: String) -> Option<NativeModelLoadResult> {
    ModelIO::load_weights(&path)
        .ok()
        .map(|(weights, meta)| NativeModelLoadResult {
            weights: weights.into_iter().map(|x| x as f64).collect(),
            metadata: meta.map(|m| m.into()),
        })
}

/// Check if model file exists
#[napi]
pub fn model_exists(path: String) -> bool {
    ModelIO::model_exists(&path)
}

/// Get model metadata without loading weights
#[napi]
pub fn model_get_metadata(path: String) -> Option<NativeModelMetadata> {
    ModelIO::get_metadata(&path)
        .ok()
        .flatten()
        .map(|m| m.into())
}
