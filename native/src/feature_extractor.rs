//! FeatureExtractor - Converts GameState to numerical features for ML
//!
//! Extracts 45 features from game state for neural network input.

use crate::card_analyzer;
use crate::game_state::GameState;

/// Feature dimension (must match JS FeatureExtractor)
pub const FEATURE_DIM: usize = 45;

/// Fixed-size feature array
pub type Features = [f32; FEATURE_DIM];

/// Feature extractor for ML input
pub struct FeatureExtractor;

impl FeatureExtractor {
    /// Extract features for a player's decision
    pub fn extract(state: &GameState, player_index: u8) -> Features {
        let hand = state.get_hand(player_index);
        let eliminated_mask = state.eliminated_mask;

        // Hand features
        let hand_value = card_analyzer::calculate_hand_value(hand) as f32;
        let hand_size = hand.len() as f32;
        let joker_count = hand.iter().filter(|&&c| c >= 52).count() as f32;
        let high_card_count = hand
            .iter()
            .filter(|&&c| c < 52 && (c % 13) >= 9)
            .count() as f32;
        let low_card_count = hand
            .iter()
            .filter(|&&c| c < 52 && (c % 13) < 4)
            .count() as f32;

        // Valid plays
        let valid_plays = card_analyzer::find_all_valid_plays(hand);
        let same_rank_plays = card_analyzer::find_same_rank_plays(hand);
        let sequence_plays = card_analyzer::find_sequence_plays(hand);

        let has_pairs = if same_rank_plays.is_empty() { 0.0 } else { 1.0 };
        let has_sequences = if sequence_plays.is_empty() { 0.0 } else { 1.0 };
        let multi_card_play_count = valid_plays.iter().filter(|p| p.len() > 1).count() as f32;
        let can_zapzap = if hand_value <= 5.0 { 1.0 } else { 0.0 };
        let best_play_size = valid_plays.iter().map(|p| p.len()).max().unwrap_or(1) as f32;

        // Score features
        let my_score = state.scores[player_index as usize] as f32;
        let opponent_scores = Self::get_opponent_scores(state, player_index, eliminated_mask);
        let min_opponent_score = opponent_scores
            .iter()
            .copied()
            .min()
            .unwrap_or(0) as f32;
        let max_opponent_score = opponent_scores
            .iter()
            .copied()
            .max()
            .unwrap_or(0) as f32;
        let avg_opponent_score = if !opponent_scores.is_empty() {
            opponent_scores.iter().map(|&s| s as f32).sum::<f32>() / opponent_scores.len() as f32
        } else {
            0.0
        };
        let score_gap = min_opponent_score - my_score;
        let score_risk = if my_score > 80.0 {
            1.0
        } else if my_score > 60.0 {
            0.5
        } else {
            0.0
        };

        // Opponent hand sizes
        let opponent_hand_sizes = Self::get_opponent_hand_sizes(state, player_index, eliminated_mask);
        let min_opponent_hand_size = opponent_hand_sizes
            .iter()
            .copied()
            .min()
            .unwrap_or(0) as f32;
        let avg_opponent_hand_size = if !opponent_hand_sizes.is_empty() {
            opponent_hand_sizes.iter().sum::<u8>() as f32 / opponent_hand_sizes.len() as f32
        } else {
            0.0
        };

        // Game context
        let round_number = state.round_number as f32;
        let deck_size = state.deck.len() as f32;
        let discard_size = state.last_cards_played.len() as f32;
        let active_player_count = state.active_player_count() as f32;
        let is_golden_score = if state.is_golden_score { 1.0 } else { 0.0 };

        // Game phase
        let early_game = if state.round_number <= 2 { 1.0 } else { 0.0 };
        let mid_game = if state.round_number > 2 && state.round_number <= 5 {
            1.0
        } else {
            0.0
        };
        let late_game = if state.round_number > 5 { 1.0 } else { 0.0 };

        // Discard analysis
        let discard_has_joker = if state.last_cards_played.iter().any(|&c| c >= 52) {
            1.0
        } else {
            0.0
        };
        let discard_has_low_card = if state
            .last_cards_played
            .iter()
            .any(|&c| c < 52 && (c % 13) < 4)
        {
            1.0
        } else {
            0.0
        };

        // Risk metrics
        let elimination_risk = if my_score > 90.0 {
            2.0
        } else if my_score > 75.0 {
            1.0
        } else {
            0.0
        };
        let elimination_proximity = ((100.0 - my_score) / 100.0).max(0.0);

        // Opponent modeling
        let opponent_close_to_zapzap = if min_opponent_hand_size <= 3.0 {
            1.0
        } else {
            0.0
        };
        let opponent_close_to_win = if min_opponent_hand_size <= 2.0 {
            1.0
        } else {
            0.0
        };
        let should_keep_jokers =
            if min_opponent_hand_size > 3.0 && !state.is_golden_score {
                1.0
            } else {
                0.0
            };

        // Threat counts
        let zapzap_threats = opponent_hand_sizes
            .iter()
            .filter(|&&s| s <= 3)
            .count()
            .min(3) as f32;
        let elimination_threats = opponent_scores
            .iter()
            .filter(|&&s| s > 85)
            .count()
            .min(3) as f32;

        // Dangerous opponent next
        let dangerous_opponent_next =
            Self::is_dangerous_opponent_next(state, player_index, eliminated_mask);

        // Score leader/trailer
        let is_score_leader = if opponent_scores.iter().all(|&s| s >= my_score as u16) {
            1.0
        } else {
            0.0
        };
        let is_score_trailer = if opponent_scores.iter().all(|&s| s <= my_score as u16) {
            1.0
        } else {
            0.0
        };

        // Position features
        let position = player_index as f32;
        let relative_position = if active_player_count > 1.0 {
            position / (active_player_count - 1.0)
        } else {
            0.0
        };
        let is_first_position = if player_index == 0 { 1.0 } else { 0.0 };
        let is_last_position = if player_index == state.player_count - 1 {
            1.0
        } else {
            0.0
        };
        let position_bucket = if player_index == 0 {
            0.0
        } else if player_index == state.player_count - 1 {
            2.0
        } else {
            1.0
        };

        // Advanced hand quality
        let suit_concentration = Self::calculate_suit_concentration(hand);
        let rank_spread = Self::calculate_rank_spread(hand);

        // Build 45-dimensional feature vector (normalized)
        [
            // Hand features (10)
            (hand_value / 100.0).min(1.0),
            (hand_size / 10.0).min(1.0),
            (joker_count / 2.0).min(1.0),
            has_pairs,
            has_sequences,
            can_zapzap,
            (multi_card_play_count / 10.0).min(1.0),
            (high_card_count / 5.0).min(1.0),
            (low_card_count / 5.0).min(1.0),
            (best_play_size / 5.0).min(1.0),
            // Game state (10)
            (round_number / 10.0).min(1.0),
            (deck_size / 54.0).min(1.0),
            (discard_size / 5.0).min(1.0),
            (active_player_count / 4.0).min(1.0),
            is_golden_score,
            early_game,
            mid_game,
            late_game,
            discard_has_joker,
            discard_has_low_card,
            // Scoring features (8)
            (my_score / 100.0).min(1.0),
            (min_opponent_score / 100.0).min(1.0),
            (max_opponent_score / 100.0).min(1.0),
            (avg_opponent_score / 100.0).min(1.0),
            (score_gap / 50.0).clamp(-1.0, 1.0),
            score_risk,
            elimination_risk,
            elimination_proximity,
            // Opponent features (10)
            (min_opponent_hand_size / 10.0).min(1.0),
            (avg_opponent_hand_size / 10.0).min(1.0),
            opponent_close_to_zapzap,
            opponent_close_to_win,
            should_keep_jokers,
            (zapzap_threats / 3.0).min(1.0),
            (elimination_threats / 3.0).min(1.0),
            if dangerous_opponent_next { 1.0 } else { 0.0 },
            is_score_leader,
            is_score_trailer,
            // Position features (5)
            (position / 3.0).min(1.0),
            relative_position,
            is_first_position,
            is_last_position,
            (position_bucket / 2.0_f32).min(1.0),
            // Advanced hand quality (2)
            suit_concentration,
            rank_spread,
        ]
    }

    /// Extract features for hand size decision (before cards are dealt)
    pub fn extract_hand_size_features(
        active_player_count: u8,
        is_golden_score: bool,
        my_score: u16,
    ) -> Features {
        let score_f = my_score as f32;
        let score_risk = if score_f > 80.0 {
            1.0
        } else if score_f > 60.0 {
            0.5
        } else {
            0.0
        };
        let elimination_risk = if score_f > 90.0 {
            2.0
        } else if score_f > 75.0 {
            1.0
        } else {
            0.0
        };
        let elimination_proximity = ((100.0 - score_f) / 100.0).max(0.0);
        let default_hand = if is_golden_score { 10.0 } else { 7.0 };

        [
            // Hand features (10) - unknown
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.2, // bestPlaySize=1
            // Game state (10)
            0.1,                                      // round 1
            1.0,                                      // full deck
            0.0, // no discard
            (active_player_count as f32 / 4.0).min(1.0),
            if is_golden_score { 1.0 } else { 0.0 },
            1.0, // early game
            0.0,
            0.0,
            0.0,
            0.0,
            // Scoring features (8)
            (score_f / 100.0).min(1.0),
            (score_f / 100.0).min(1.0), // assume similar
            (score_f / 100.0).min(1.0),
            (score_f / 100.0).min(1.0),
            0.0, // score gap
            score_risk,
            elimination_risk,
            elimination_proximity,
            // Opponent features (10)
            (default_hand / 10.0_f32).min(1.0),
            (default_hand / 10.0_f32).min(1.0),
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            // Position features (5)
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            // Advanced (2)
            0.0,
            0.0,
        ]
    }

    /// Get opponent scores (excluding eliminated)
    fn get_opponent_scores(state: &GameState, player_index: u8, eliminated_mask: u8) -> Vec<u16> {
        let mut scores = Vec::with_capacity(state.player_count as usize);
        for i in 0..state.player_count {
            if i != player_index && (eliminated_mask & (1 << i)) == 0 {
                scores.push(state.scores[i as usize]);
            }
        }
        scores
    }

    /// Get opponent hand sizes
    fn get_opponent_hand_sizes(state: &GameState, player_index: u8, eliminated_mask: u8) -> Vec<u8> {
        let mut sizes = Vec::with_capacity(state.player_count as usize);
        for i in 0..state.player_count {
            if i != player_index && (eliminated_mask & (1 << i)) == 0 {
                sizes.push(state.hands[i as usize].len() as u8);
            }
        }
        sizes
    }

    /// Check if dangerous opponent plays next
    fn is_dangerous_opponent_next(
        state: &GameState,
        player_index: u8,
        eliminated_mask: u8,
    ) -> bool {
        for offset in 1..state.player_count {
            let next = (player_index + offset) % state.player_count;
            if (eliminated_mask & (1 << next)) == 0 {
                return state.hands[next as usize].len() <= 3;
            }
        }
        false
    }

    /// Calculate suit concentration (max suit count / hand size)
    fn calculate_suit_concentration(hand: &[u8]) -> f32 {
        if hand.is_empty() {
            return 0.0;
        }
        let mut suit_counts = [0u8; 4];
        for &card in hand {
            if card < 52 {
                suit_counts[(card / 13) as usize] += 1;
            }
        }
        let max_suit = *suit_counts.iter().max().unwrap_or(&0);
        max_suit as f32 / hand.len() as f32
    }

    /// Calculate rank spread (normalized)
    fn calculate_rank_spread(hand: &[u8]) -> f32 {
        let ranks: Vec<u8> = hand
            .iter()
            .filter(|&&c| c < 52)
            .map(|&c| c % 13)
            .collect();
        if ranks.len() <= 1 {
            return 0.0;
        }
        let min_rank = *ranks.iter().min().unwrap();
        let max_rank = *ranks.iter().max().unwrap();
        (max_rank - min_rank) as f32 / 12.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_feature_dimension() {
        assert_eq!(FEATURE_DIM, 45);
    }

    #[test]
    fn test_extract_features() {
        let mut state = GameState::new(4);
        // Give player 0 some cards
        state.hands[0].push(0); // A♠
        state.hands[0].push(13); // A♥
        state.hands[0].push(5); // 6♠

        let features = FeatureExtractor::extract(&state, 0);

        // Check dimension
        assert_eq!(features.len(), FEATURE_DIM);

        // Check some expected values
        assert!(features[0] >= 0.0); // hand_value normalized
        assert!(features[1] > 0.0); // hand_size > 0
    }

    #[test]
    fn test_extract_hand_size_features() {
        let features = FeatureExtractor::extract_hand_size_features(4, false, 50);
        assert_eq!(features.len(), FEATURE_DIM);

        // Golden score should affect default hand size
        let gs_features = FeatureExtractor::extract_hand_size_features(2, true, 50);
        assert_eq!(gs_features.len(), FEATURE_DIM);
    }

    #[test]
    fn test_suit_concentration() {
        // All same suit
        let hand = vec![0, 1, 2, 3]; // All spades
        let conc = FeatureExtractor::calculate_suit_concentration(&hand);
        assert!((conc - 1.0).abs() < 0.01);

        // Mixed suits
        let mixed = vec![0, 13, 26, 39]; // One of each suit
        let mixed_conc = FeatureExtractor::calculate_suit_concentration(&mixed);
        assert!((mixed_conc - 0.25).abs() < 0.01);
    }
}
