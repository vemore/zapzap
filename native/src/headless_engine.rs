//! HeadlessGameEngine - Fast synchronous game simulation
//!
//! Runs complete games without I/O overhead for training.

use crate::card_analyzer;
use crate::feature_extractor::FeatureExtractor;
use crate::game_state::{GameAction, GameState, LastAction, MAX_PLAYERS};
use crate::strategies::{BotStrategy, DRLStrategy, HardBotStrategy, RandomBotStrategy, ThibotStrategy};
use crate::training::{TransitionCollector, Transition};
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
    Thibot,
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

    /// Set weights for all DRL strategies (sync from training network)
    pub fn set_drl_weights(&mut self, weights: &[f32]) {
        for (_, drl) in &mut self.drl_strategies {
            drl.set_weights_flat(weights);
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

    /// Run a complete game with transition collection for DRL training
    /// Returns (game_result, collected_transitions)
    pub fn run_game_with_collection(&mut self, drl_player_index: u8) -> (GameResult, Vec<Transition>) {
        let mut state = GameState::new(self.player_count);
        let mut collector = TransitionCollector::new(drl_player_index);

        let mut round_number = 1u16;
        let max_rounds = 100;

        while !self.is_game_finished(&state) && round_number < max_rounds {
            state = self.run_round_with_collection(state, round_number, drl_player_index, &mut collector);
            round_number += 1;
            state = self.process_round_end(state);
        }

        let winner = self.determine_winner(&state);

        // Finalize transitions with sparse rewards (only terminal reward)
        // Asymmetric: win=+1.0, lose=-0.25 to reduce negative bias
        let game_reward = if winner == drl_player_index { 1.0 } else { -0.25 };
        collector.finalize_simple(&state, game_reward);

        let result = GameResult {
            winner,
            total_rounds: round_number - 1,
            final_scores: state.scores,
            was_golden_score: state.is_golden_score,
            player_count: self.player_count,
        };

        (result, collector.take_transitions())
    }

    /// Run a single round with transition collection
    fn run_round_with_collection(
        &mut self,
        mut state: GameState,
        round_number: u16,
        drl_player_index: u8,
        collector: &mut TransitionCollector,
    ) -> GameState {
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

        // Record hand size decision for DRL player
        if current_player == drl_player_index && self.strategies[current_player as usize] == StrategyType::DRL {
            let features = FeatureExtractor::extract_hand_size_features(
                active_players.len() as u8,
                state.is_golden_score,
                my_score,
            );
            let action = hand_size.saturating_sub(4).min(6); // Map 4-10 to 0-6
            collector.record_action_with_features(features, action, 0); // 0 = HandSize decision
        }

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
            let is_drl_player = current_player == drl_player_index
                && self.strategies[current_player as usize] == StrategyType::DRL;

            // Check for ZapZap
            if card_analyzer::can_call_zapzap(&hand)
                && self.should_strategy_zapzap(current_player, &hand, &state)
            {
                // Record ZapZap decision for DRL player
                if is_drl_player {
                    collector.record_action(&state, 1, 1); // action=1 (zapzap), decision_type=1 (ZapZap)
                }
                state = self.execute_zapzap(state, current_player, &active_players);
                break;
            }

            // Play phase - different handling for DRL vs other strategies
            if is_drl_player {
                // For DRL, get both the play and the action chosen to record correctly
                let (maybe_cards, play_action) = self.get_drl_play_with_action(current_player, &hand, &state);
                if let Some(cards_to_play) = maybe_cards {
                    // Record the ACTUAL action chosen by the DRL, not a classification
                    collector.record_action(&state, play_action, 2); // decision_type=2 (PlayType)
                    state = self.execute_play(state, current_player, &cards_to_play);
                } else {
                    // Fallback: play first card
                    if !hand.is_empty() {
                        collector.record_action(&state, 0, 2); // action=0 (optimal fallback)
                        let fallback: SmallVec<[u8; 8]> = SmallVec::from_slice(&[hand[0]]);
                        state = self.execute_play(state, current_player, &fallback);
                    }
                }
            } else {
                // For non-DRL strategies, just get the play
                if let Some(cards_to_play) = self.get_strategy_play(current_player, &hand, &state) {
                    state = self.execute_play(state, current_player, &cards_to_play);
                } else if !hand.is_empty() {
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

            // Record draw decision for DRL player
            if is_drl_player {
                let draw_action = if draw_from_deck { 0 } else { 1 }; // 0=deck, 1=discard
                collector.record_action(&state, draw_action, 3); // decision_type=3 (DrawSource)
            }

            state = self.execute_draw(state, current_player, draw_from_deck);

            turn_count += 1;
        }

        state
    }

    /// Classify the play action type for transition recording
    /// Returns the action index that would have produced this play via action_to_play()
    /// Action mapping (must match DRLStrategy::action_to_play):
    /// 0: optimal - minimizes remaining hand value
    /// 1: single_high - plays highest single card
    /// 2: multi_high - plays multi-card combo with most value
    /// 3: avoid_joker - avoids playing jokers if possible
    /// 4: use_joker_combo - uses joker in combos if possible
    fn classify_play_action(&self, play: &[u8], hand: &[u8]) -> u8 {
        use smallvec::SmallVec;

        let valid_plays = card_analyzer::find_all_valid_plays(hand);
        if valid_plays.is_empty() {
            return 0;
        }

        let play_set: SmallVec<[u8; 8]> = play.iter().copied().collect();

        // Check each action to see which one would produce this play
        // Action 0: optimal - minimizes remaining hand value
        let optimal_play = valid_plays
            .iter()
            .min_by_key(|p| {
                let remaining: SmallVec<[u8; 10]> = hand
                    .iter()
                    .filter(|id| !p.contains(id))
                    .copied()
                    .collect();
                card_analyzer::calculate_hand_value(&remaining)
            });
        if optimal_play.map(|p| self.plays_match(p, &play_set)).unwrap_or(false) {
            return 0;
        }

        // Action 1: single_high - plays highest single card
        let single_plays: Vec<_> = valid_plays.iter().filter(|p| p.len() == 1).collect();
        let single_high_play = if !single_plays.is_empty() {
            single_plays.into_iter().max_by_key(|p| card_analyzer::get_card_points(p[0]))
        } else {
            valid_plays.iter().max_by_key(|p| p.iter().map(|&c| card_analyzer::get_card_points(c) as u32).sum::<u32>())
        };
        if single_high_play.map(|p| self.plays_match(p, &play_set)).unwrap_or(false) {
            return 1;
        }

        // Action 2: multi_high - plays multi-card combo with most value
        let multi_plays: Vec<_> = valid_plays.iter().filter(|p| p.len() > 1).collect();
        let multi_high_play = if !multi_plays.is_empty() {
            multi_plays.into_iter().max_by_key(|p| p.iter().map(|&c| card_analyzer::get_card_points(c) as u32).sum::<u32>())
        } else {
            valid_plays.iter().max_by_key(|p| p.iter().map(|&c| card_analyzer::get_card_points(c) as u32).sum::<u32>())
        };
        if multi_high_play.map(|p| self.plays_match(p, &play_set)).unwrap_or(false) {
            return 2;
        }

        // Action 3: avoid_joker - avoids playing jokers
        let non_joker_plays: Vec<_> = valid_plays.iter().filter(|p| !p.iter().any(|&c| card_analyzer::is_joker(c))).collect();
        let avoid_joker_play = if !non_joker_plays.is_empty() {
            non_joker_plays.into_iter().min_by_key(|p| {
                let remaining: SmallVec<[u8; 10]> = hand.iter().filter(|id| !p.contains(id)).copied().collect();
                card_analyzer::calculate_hand_value(&remaining)
            })
        } else {
            optimal_play
        };
        if avoid_joker_play.map(|p| self.plays_match(p, &play_set)).unwrap_or(false) {
            return 3;
        }

        // Action 4: use_joker_combo - uses joker in combos
        let joker_combos: Vec<_> = valid_plays.iter().filter(|p| p.len() > 1 && p.iter().any(|&c| card_analyzer::is_joker(c))).collect();
        let joker_combo_play = if !joker_combos.is_empty() {
            joker_combos.into_iter().max_by_key(|p| p.len())
        } else {
            optimal_play
        };
        if joker_combo_play.map(|p| self.plays_match(p, &play_set)).unwrap_or(false) {
            return 4;
        }

        // Default to optimal if no match found
        0
    }

    /// Check if two plays contain the same cards (order-independent)
    fn plays_match(&self, a: &SmallVec<[u8; 8]>, b: &SmallVec<[u8; 8]>) -> bool {
        if a.len() != b.len() {
            return false;
        }
        let mut a_sorted = a.clone();
        let mut b_sorted = b.clone();
        a_sorted.sort();
        b_sorted.sort();
        a_sorted == b_sorted
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
        // Track cards played (removes from opponent hand prediction)
        state.track_cards_played(player_index, card_ids);

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
        let drew_from_played;

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
            drew_from_played = false;
        } else {
            // Draw from played cards
            drawn_card = state.last_cards_played.pop().unwrap();
            drew_from_played = true;
        }

        // Track card taken from played pile (for opponent hand prediction)
        if drew_from_played {
            state.track_card_taken(player_index, drawn_card);
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

        // Golden Score: ends when the round finishes (hands differ or caller loses on tie)
        // The winner is determined by lowest hand, not by scores
        if state.is_golden_score
            && active_players.len() == 2
            && state.current_action == GameAction::Finished
        {
            // Golden Score round finished - game is over
            // Winner will be determined by determine_winner based on hands
            return true;
        }

        false
    }

    /// Determine winner
    fn determine_winner(&self, state: &GameState) -> u8 {
        let active = state.active_players();

        if active.len() == 1 {
            return active[0];
        }

        // Golden Score: winner is determined by lowest hand this round
        // If hands are tied, the ZapZap caller loses (was counteracted)
        if state.is_golden_score && active.len() == 2 {
            let p1 = active[0];
            let p2 = active[1];
            let hand1 = card_analyzer::calculate_hand_value(&state.hands[p1 as usize]);
            let hand2 = card_analyzer::calculate_hand_value(&state.hands[p2 as usize]);

            if hand1 != hand2 {
                // Lower hand wins
                return if hand1 < hand2 { p1 } else { p2 };
            } else {
                // Hands are equal - ZapZap caller was counteracted and loses
                // The last_action contains who called ZapZap
                let caller = state.last_action.player_index;
                // The non-caller wins
                return if caller == p1 { p2 } else { p1 };
            }
        }

        // Normal game: lowest score wins
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

    fn get_strategy_hand_size(&mut self, player: u8, active_count: u8, is_golden_score: bool, _my_score: u16) -> u8 {
        match self.strategies[player as usize] {
            StrategyType::Random => 5,
            StrategyType::Hard => {
                let mut s = HardBotStrategy::with_seed(self.rng.gen());
                s.select_hand_size_mut(active_count, is_golden_score)
            }
            StrategyType::DRL => {
                if let Some(drl) = self.get_drl_strategy_mut(player) {
                    drl.select_hand_size_mut(active_count, is_golden_score, _my_score)
                } else {
                    5
                }
            }
            StrategyType::Thibot => {
                let mut s = ThibotStrategy::with_seed(self.rng.gen());
                s.select_hand_size_mut(active_count, is_golden_score)
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
                // TEST: Re-enable DRL for PlayType only
                if let Some(drl) = self.get_drl_strategy_mut(player) {
                    drl.select_play_mut(hand, state)
                } else {
                    HardBotStrategy::new().select_play(hand, state)
                }
            }
            StrategyType::Thibot => ThibotStrategy::new().select_play(hand, state),
        }
    }

    /// Get strategy play for DRL player, returning both the play and the action chosen
    /// This is used during training to record the correct action
    fn get_drl_play_with_action(
        &mut self,
        player: u8,
        hand: &[u8],
        state: &GameState,
    ) -> (Option<SmallVec<[u8; 8]>>, u8) {
        if let Some(drl) = self.get_drl_strategy_mut(player) {
            drl.select_play_with_action(hand, state)
        } else {
            (RandomBotStrategy.select_play(hand, state), 0)
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
                    false
                }
            }
            StrategyType::Thibot => ThibotStrategy::new().should_zapzap(hand, state),
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
                    true
                }
            }
            StrategyType::Thibot => ThibotStrategy::new().select_draw_source(hand, last_played, state),
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

    #[test]
    fn test_golden_score_winner_by_lowest_hand() {
        // Test that in Golden Score, the winner is determined by lowest hand, not total score
        let mut state = GameState::new(2);
        state.is_golden_score = true;
        state.current_action = GameAction::Finished;
        state.eliminated_mask = 0; // No one eliminated

        // Player 0: Ace = 1 point hand, but higher total score (98)
        // Player 1: 2, 3 = 5 points hand, but lower total score (85)
        state.hands[0].clear();
        state.hands[0].push(0); // Ace of spades = 1 point
        state.hands[1].clear();
        state.hands[1].push(1); // 2 of spades
        state.hands[1].push(2); // 3 of spades

        state.scores[0] = 98;
        state.scores[1] = 85;

        // Player 0 called ZapZap
        state.last_action.player_index = 0;
        state.last_action.action_type = 3; // zapzap

        let strategies = vec![StrategyType::Hard, StrategyType::Hard];
        let engine = HeadlessGameEngine::with_seed(strategies, 42);

        let winner = engine.determine_winner(&state);

        // Player 0 should win because lowest hand (1 point), even though player 1 has lower score
        assert_eq!(winner, 0, "Player with lowest hand should win in Golden Score");
    }

    #[test]
    fn test_golden_score_caller_loses_on_tie() {
        // Test that in Golden Score, when hands are tied, ZapZap caller loses
        let mut state = GameState::new(2);
        state.is_golden_score = true;
        state.current_action = GameAction::Finished;
        state.eliminated_mask = 0; // No one eliminated

        // Both players have same hand value (3 points)
        // Player 0: Ace + 2 = 3 points
        // Player 1: Ace + 2 = 3 points
        state.hands[0].clear();
        state.hands[0].push(0);  // Ace of spades
        state.hands[0].push(1);  // 2 of spades
        state.hands[1].clear();
        state.hands[1].push(13); // Ace of hearts
        state.hands[1].push(14); // 2 of hearts

        state.scores[0] = 90;
        state.scores[1] = 92;

        // Player 0 called ZapZap
        state.last_action.player_index = 0;
        state.last_action.action_type = 3; // zapzap

        let strategies = vec![StrategyType::Hard, StrategyType::Hard];
        let engine = HeadlessGameEngine::with_seed(strategies, 42);

        let winner = engine.determine_winner(&state);

        // Player 1 should win because Player 0 called ZapZap and was counteracted (tied)
        assert_eq!(winner, 1, "ZapZap caller should lose when hands are tied in Golden Score");
    }
}
