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
/// Strategy types: "random", "hard"
#[napi]
pub fn run_game(strategy_types: Vec<String>, seed: Option<u32>) -> NativeGameResult {
    let strategies: Vec<StrategyType> = strategy_types
        .iter()
        .map(|s| match s.to_lowercase().as_str() {
            "hard" => StrategyType::Hard,
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
#[napi]
pub fn run_games_batch(
    strategy_types: Vec<String>,
    game_count: u32,
    base_seed: Option<u32>,
) -> BatchGameStats {
    let strategies: Vec<StrategyType> = strategy_types
        .iter()
        .map(|s| match s.to_lowercase().as_str() {
            "hard" => StrategyType::Hard,
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
