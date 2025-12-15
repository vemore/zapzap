//! HeadlessGameEngine - Fast synchronous game simulation
//!
//! Runs complete games without I/O overhead for training.

use crate::card_analyzer;
use crate::game_state::{GameAction, GameState, LastAction, MAX_PLAYERS};
use crate::strategies::{BotStrategy, DRLStrategy, HardBotStrategy, RandomBotStrategy};
use rand::rngs::SmallRng;
use rand::{Rng, SeedableRng};
use rand::seq::SliceRandom;
use smallvec::SmallVec;

/// Strategy type enum for configuration
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StrategyType {
    Random,
    Hard,
    DRL,
}

/// Game result
#[derive(Debug, Clone)]
pub struct GameResult {
    pub winner: u8,
    pub total_rounds: u16,
    pub final_scores: [u16; MAX_PLAYERS],
    pub was_golden_score: bool,
    pub player_count: u8,
}

/// Headless game engine for fast simulation
pub struct HeadlessGameEngine {
    player_count: u8,
    strategies: Vec<StrategyType>,
    rng: SmallRng,
    /// DRL strategies for each DRL player (keyed by player index)
    drl_strategies: Vec<(u8, DRLStrategy)>,
}

impl HeadlessGameEngine {
    /// Create new engine with given strategies
    pub fn new(strategies: Vec<StrategyType>) -> Self {
        let player_count = strategies.len() as u8;
        // Create DRL strategies for DRL players
        let drl_strategies: Vec<(u8, DRLStrategy)> = strategies
            .iter()
            .enumerate()
            .filter(|(_, s)| **s == StrategyType::DRL)
            .map(|(i, _)| (i as u8, DRLStrategy::new(i as u8)))
            .collect();
        HeadlessGameEngine {
            player_count,
            strategies,
            rng: SmallRng::from_entropy(),
            drl_strategies,
        }
    }

    /// Create engine with seed for reproducibility
    pub fn with_seed(strategies: Vec<StrategyType>, seed: u64) -> Self {
        let player_count = strategies.len() as u8;
        // Create DRL strategies for DRL players
        let drl_strategies: Vec<(u8, DRLStrategy)> = strategies
            .iter()
            .enumerate()
            .filter(|(_, s)| **s == StrategyType::DRL)
            .map(|(i, _)| (i as u8, DRLStrategy::with_seed(i as u8, seed + i as u64)))
            .collect();
        HeadlessGameEngine {
            player_count,
            strategies,
            rng: SmallRng::seed_from_u64(seed),
            drl_strategies,
        }
    }

    /// Set epsilon for all DRL strategies
    pub fn set_drl_epsilon(&mut self, epsilon: f32) {
        for (_, drl) in &mut self.drl_strategies {
            drl.set_epsilon(epsilon);
        }
    }

    /// Get mutable DRL strategy for a player (if they're using DRL)
    fn get_drl_strategy_mut(&mut self, player: u8) -> Option<&mut DRLStrategy> {
        self.drl_strategies
            .iter_mut()
            .find(|(p, _)| *p == player)
            .map(|(_, s)| s)
    }

    /// Get DRL strategy for a player (if they're using DRL)
    fn get_drl_strategy(&self, player: u8) -> Option<&DRLStrategy> {
        self.drl_strategies
            .iter()
            .find(|(p, _)| *p == player)
            .map(|(_, s)| s)
    }

    /// Run a complete game
    pub fn run_game(&mut self) -> GameResult {
        let mut state = GameState::new(self.player_count);

        let mut round_number = 1u16;
        let max_rounds = 100;

        while !self.is_game_finished(&state) && round_number < max_rounds {
            state = self.run_round(state, round_number);
            round_number += 1;
            state = self.process_round_end(state);
        }

        let winner = self.determine_winner(&state);

        GameResult {
            winner,
            total_rounds: round_number - 1,
            final_scores: state.scores,
            was_golden_score: state.is_golden_score,
            player_count: self.player_count,
        }
    }

    /// Run a single round
    fn run_round(&mut self, mut state: GameState, round_number: u16) -> GameState {
        let active_players = state.active_players();
        let mut current_player = state.current_turn;

        // Skip to active player
        while state.is_eliminated(current_player) {
            current_player = (current_player + 1) % self.player_count;
        }

        // Select hand size
        let my_score = state.scores[current_player as usize];
        let hand_size = self.get_strategy_hand_size(
            current_player,
            active_players.len() as u8,
            state.is_golden_score,
            my_score,
        );
        let valid_hand_size = self.validate_hand_size(hand_size, state.is_golden_score);

        // Deal cards
        state = self.deal_cards(state, valid_hand_size, &active_players, round_number, current_player);

        // Play turns
        let max_turns = 1000;
        let mut turn_count = 0;

        while state.current_action != GameAction::Finished && turn_count < max_turns {
            current_player = state.current_turn;

            if state.is_eliminated(current_player) {
                state.advance_turn();
                turn_count += 1;
                continue;
            }

            let hand: SmallVec<[u8; 10]> = state.get_hand(current_player).clone();

            // Check for ZapZap
            if card_analyzer::can_call_zapzap(&hand)
                && self.should_strategy_zapzap(current_player, &hand, &state)
            {
                state = self.execute_zapzap(state, current_player, &active_players);
                break;
            }

            // Play phase
            if let Some(cards_to_play) = self.get_strategy_play(current_player, &hand, &state) {
                state = self.execute_play(state, current_player, &cards_to_play);
            } else {
                // Fallback: play first card
                if !hand.is_empty() {
                    let fallback: SmallVec<[u8; 8]> = SmallVec::from_slice(&[hand[0]]);
                    state = self.execute_play(state, current_player, &fallback);
                }
            }

            // Draw phase
            let draw_from_deck = self.get_strategy_draw_source(
                current_player,
                state.get_hand(current_player),
                &state.last_cards_played,
                &state,
            );
            state = self.execute_draw(state, current_player, draw_from_deck);

            turn_count += 1;
        }

        state
    }

    /// Deal cards to players
    fn deal_cards(
        &mut self,
        mut state: GameState,
        hand_size: u8,
        active_players: &[u8],
        round_number: u16,
        starting_player: u8,
    ) -> GameState {
        // Create deck (54 cards)
        let mut deck: Vec<u8> = (0..54).collect();

        // Shuffle
        deck.shuffle(&mut self.rng);

        // Deal hands
        for i in 0..self.player_count {
            state.hands[i as usize].clear();
            if active_players.contains(&i) {
                for _ in 0..hand_size {
                    if let Some(card) = deck.pop() {
                        state.hands[i as usize].push(card);
                    }
                }
            }
        }

        // Flip one card
        let flipped = deck.pop().unwrap_or(0);

        state.deck = deck;
        state.last_cards_played.clear();
        state.last_cards_played.push(flipped);
        state.cards_played.clear();
        state.discard_pile.clear();
        state.current_turn = starting_player;
        state.current_action = GameAction::Play;
        state.round_number = round_number;

        state
    }

    /// Execute play action
    fn execute_play(
        &mut self,
        mut state: GameState,
        player_index: u8,
        card_ids: &[u8],
    ) -> GameState {
        // Remove cards from hand
        let hand = state.get_hand_mut(player_index);
        hand.retain(|id| !card_ids.contains(id));

        // Update discard piles
        let is_first_play = state.cards_played.is_empty();

        if !is_first_play {
            // Move last_cards_played to discard_pile
            state.discard_pile.extend(state.last_cards_played.drain(..));
            // Move cards_played to last_cards_played
            state.last_cards_played.clear();
            state.last_cards_played.extend(state.cards_played.drain(..));
        }

        // Set current play
        state.cards_played.clear();
        state.cards_played.extend_from_slice(card_ids);

        state.current_action = GameAction::Draw;
        state
    }

    /// Execute draw action
    fn execute_draw(
        &mut self,
        mut state: GameState,
        player_index: u8,
        from_deck: bool,
    ) -> GameState {
        let drawn_card;

        if from_deck || state.last_cards_played.is_empty() {
            // Draw from deck
            if state.deck.is_empty() {
                // Reshuffle discard pile
                if state.discard_pile.is_empty() {
                    // No cards - advance turn
                    state.advance_turn();
                    state.current_action = GameAction::Play;
                    state.cards_played.clear();
                    return state;
                }
                state.deck.extend(state.discard_pile.drain(..));
                state.deck.shuffle(&mut self.rng);
            }
            drawn_card = state.deck.pop().unwrap();
        } else {
            // Draw from played cards
            drawn_card = state.last_cards_played.pop().unwrap();
        }

        // Add to hand
        state.get_hand_mut(player_index).push(drawn_card);

        // Advance turn
        state.advance_turn();
        state.current_action = GameAction::Play;
        state.cards_played.clear();

        state
    }

    /// Execute ZapZap
    fn execute_zapzap(
        &mut self,
        mut state: GameState,
        caller_index: u8,
        active_players: &[u8],
    ) -> GameState {
        let caller_hand = state.get_hand(caller_index);
        let caller_base_points = card_analyzer::calculate_hand_value(caller_hand);

        // Calculate base points for all
        let mut base_points: [u16; MAX_PLAYERS] = [0; MAX_PLAYERS];
        for &p in active_players {
            base_points[p as usize] = card_analyzer::calculate_hand_value(state.get_hand(p));
        }

        // Check counteract
        let mut counteracted = false;
        for &p in active_players {
            if p != caller_index && base_points[p as usize] <= caller_base_points {
                counteracted = true;
                break;
            }
        }

        // Find lowest
        let lowest_value = active_players
            .iter()
            .map(|&p| base_points[p as usize])
            .min()
            .unwrap_or(0);

        // Calculate hand scores (Joker = 25 for non-lowest)
        let mut hand_scores: [u16; MAX_PLAYERS] = [0; MAX_PLAYERS];
        for &p in active_players {
            hand_scores[p as usize] = card_analyzer::calculate_hand_score(state.get_hand(p), false);
        }

        // Apply scores
        if counteracted {
            // Caller penalty
            let penalty = hand_scores[caller_index as usize]
                + ((active_players.len() as u16 - 1) * 5);
            state.add_score(caller_index, penalty);

            // Others
            for &p in active_players {
                if p == caller_index {
                    continue;
                }
                let is_lowest = base_points[p as usize] == lowest_value;
                if !is_lowest {
                    state.add_score(p, hand_scores[p as usize]);
                }
            }
        } else {
            // Caller (lowest) gets 0, others get points
            for &p in active_players {
                if p != caller_index {
                    state.add_score(p, hand_scores[p as usize]);
                }
            }
        }

        state.current_action = GameAction::Finished;
        state.last_action = LastAction {
            action_type: 3, // zapzap
            player_index: caller_index,
            was_counteracted: counteracted,
            caller_hand_points: caller_base_points as u8,
        };

        state
    }

    /// Process round end
    fn process_round_end(&mut self, mut state: GameState) -> GameState {
        // Check eliminations
        for i in 0..self.player_count {
            if state.scores[i as usize] > 100 && !state.is_eliminated(i) {
                state.eliminate_player(i);
            }
        }

        // Check golden score
        let active_count = state.active_player_count();
        if !state.is_golden_score && active_count == 2 {
            state.is_golden_score = true;
        }

        // Rotate starting player
        state.advance_turn();
        state.current_action = GameAction::SelectHandSize;
        state.round_number += 1;

        state
    }

    /// Check if game is finished
    fn is_game_finished(&self, state: &GameState) -> bool {
        let active_players = state.active_players();

        if active_players.len() <= 1 {
            return true;
        }

        // Golden Score: ends when scores differ
        if state.is_golden_score
            && active_players.len() == 2
            && state.current_action == GameAction::Finished
        {
            let s1 = state.scores[active_players[0] as usize];
            let s2 = state.scores[active_players[1] as usize];
            if s1 != s2 {
                return true;
            }
        }

        false
    }

    /// Determine winner
    fn determine_winner(&self, state: &GameState) -> u8 {
        let active = state.active_players();

        if active.len() == 1 {
            return active[0];
        }

        // Lowest score wins
        let mut winner = 0u8;
        let mut lowest_score = u16::MAX;

        for i in 0..self.player_count {
            let score = state.scores[i as usize];
            if !state.is_eliminated(i) && score < lowest_score {
                lowest_score = score;
                winner = i;
            }
        }

        winner
    }

    /// Validate hand size
    fn validate_hand_size(&self, size: u8, is_golden_score: bool) -> u8 {
        let min = 4;
        let max = if is_golden_score { 10 } else { 7 };
        size.clamp(min, max)
    }

    // Strategy dispatch methods

    fn get_strategy_hand_size(&mut self, player: u8, active_count: u8, is_golden_score: bool, my_score: u16) -> u8 {
        match self.strategies[player as usize] {
            StrategyType::Random => 5,
            StrategyType::Hard => {
                let mut s = HardBotStrategy::with_seed(self.rng.gen());
                s.select_hand_size_mut(active_count, is_golden_score)
            }
            StrategyType::DRL => {
                if let Some(drl) = self.get_drl_strategy_mut(player) {
                    drl.select_hand_size_mut(active_count, is_golden_score, my_score)
                } else {
                    5 // Fallback
                }
            }
        }
    }

    fn get_strategy_play(
        &mut self,
        player: u8,
        hand: &[u8],
        state: &GameState,
    ) -> Option<SmallVec<[u8; 8]>> {
        match self.strategies[player as usize] {
            StrategyType::Random => RandomBotStrategy.select_play(hand, state),
            StrategyType::Hard => HardBotStrategy::new().select_play(hand, state),
            StrategyType::DRL => {
                if let Some(drl) = self.get_drl_strategy_mut(player) {
                    drl.select_play_mut(hand, state)
                } else {
                    RandomBotStrategy.select_play(hand, state)
                }
            }
        }
    }

    fn should_strategy_zapzap(&mut self, player: u8, hand: &[u8], state: &GameState) -> bool {
        match self.strategies[player as usize] {
            StrategyType::Random => RandomBotStrategy.should_zapzap(hand, state),
            StrategyType::Hard => HardBotStrategy::new().should_zapzap(hand, state),
            StrategyType::DRL => {
                if let Some(drl) = self.get_drl_strategy_mut(player) {
                    drl.should_zapzap_mut(hand, state)
                } else {
                    RandomBotStrategy.should_zapzap(hand, state)
                }
            }
        }
    }

    fn get_strategy_draw_source(
        &mut self,
        player: u8,
        hand: &SmallVec<[u8; 10]>,
        last_played: &SmallVec<[u8; 8]>,
        state: &GameState,
    ) -> bool {
        match self.strategies[player as usize] {
            StrategyType::Random => RandomBotStrategy.select_draw_source(hand, last_played, state),
            StrategyType::Hard => HardBotStrategy::new().select_draw_source(hand, last_played, state),
            StrategyType::DRL => {
                if let Some(drl) = self.get_drl_strategy_mut(player) {
                    drl.select_draw_source_mut(hand, last_played, state)
                } else {
                    RandomBotStrategy.select_draw_source(hand, last_played, state)
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_run_game() {
        let strategies = vec![
            StrategyType::Hard,
            StrategyType::Hard,
            StrategyType::Hard,
            StrategyType::Hard,
        ];
        let mut engine = HeadlessGameEngine::with_seed(strategies, 42);

        let result = engine.run_game();

        assert!(result.winner < 4);
        assert!(result.total_rounds >= 1);
    }

    #[test]
    fn test_multiple_games() {
        let strategies = vec![
            StrategyType::Hard,
            StrategyType::Hard,
            StrategyType::Hard,
            StrategyType::Hard,
        ];

        let mut wins = [0u32; 4];

        for seed in 0..100 {
            let mut engine = HeadlessGameEngine::with_seed(strategies.clone(), seed);
            let result = engine.run_game();
            wins[result.winner as usize] += 1;
        }

        // All players should win sometimes (roughly equal distribution)
        for &w in &wins {
            assert!(w > 0, "Every player should win at least once");
        }
    }
}
