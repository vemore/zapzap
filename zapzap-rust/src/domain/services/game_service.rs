//! Game service - Core game logic for ZapZap
//!
//! This module contains the core game simulation logic.

use rand::seq::SliceRandom;
use rand::SeedableRng;
use rand_chacha::ChaCha8Rng;

use crate::domain::value_objects::{GameAction, GameState};
use crate::infrastructure::bot::card_analyzer;

/// Initialize a new round with shuffled deck and dealt hands
pub fn initialize_round(
    player_count: u8,
    hand_size: u8,
    scores: &[u16],
    eliminated_mask: u8,
    round_number: u16,
    starting_player: u8,
    seed: Option<u64>,
) -> GameState {
    let mut state = GameState::new(player_count);
    state.round_number = round_number;
    state.eliminated_mask = eliminated_mask;
    state.starting_player = starting_player;
    state.current_turn = starting_player;
    state.current_action = GameAction::SelectHandSize;

    // Copy scores
    for (i, &score) in scores.iter().enumerate() {
        if i < state.scores.len() {
            state.scores[i] = score;
        }
    }

    // Create and shuffle deck
    let mut deck: Vec<u8> = (0..54).collect();
    let mut rng = match seed {
        Some(s) => ChaCha8Rng::seed_from_u64(s),
        None => ChaCha8Rng::from_entropy(),
    };
    deck.shuffle(&mut rng);

    // Deal hands to active players
    for player in 0..player_count {
        if !state.is_eliminated(player) {
            for _ in 0..hand_size {
                if let Some(card) = deck.pop() {
                    state.hands[player as usize].push(card);
                }
            }
        }
    }

    state.deck = deck;

    // Check if golden score (only 2 active players)
    state.is_golden_score = state.active_player_count() == 2;

    state
}

/// Execute a play action
pub fn execute_play(state: &mut GameState, cards: &[u8]) -> Result<(), &'static str> {
    if state.current_action != GameAction::Play {
        return Err("Not in play phase");
    }

    if !card_analyzer::is_valid_play(cards) {
        return Err("Invalid card combination");
    }

    let player = state.current_turn as usize;
    let hand = &mut state.hands[player];

    // Verify all cards are in hand
    for &card in cards {
        if !hand.contains(&card) {
            return Err("Card not in hand");
        }
    }

    // Remove cards from hand
    for &card in cards {
        if let Some(pos) = hand.iter().position(|&c| c == card) {
            hand.remove(pos);
        }
    }

    // Track cards played (for card counting)
    state.track_cards_played(state.current_turn, cards);

    // Determine if this is the first play of the round
    // (cards_played is empty means no one has played yet this round)
    let is_first_play_of_round = state.cards_played.is_empty();

    if is_first_play_of_round {
        // First play of round: keep last_cards_played as is (the flipped card)
        // Only update cards_played with the new cards
        state.cards_played.clear();
        state.cards_played.extend(cards.iter().copied());
    } else {
        // Subsequent plays:
        // 1. Move current last_cards_played to discard pile
        state.discard_pile.extend(state.last_cards_played.drain(..));
        // 2. Move current cards_played to last_cards_played (these become the discard)
        state.last_cards_played = state.cards_played.clone();
        // 3. Set new cards_played
        state.cards_played.clear();
        state.cards_played.extend(cards.iter().copied());
    }

    // Update action to draw
    state.current_action = GameAction::Draw;

    Ok(())
}

/// Execute a draw action
pub fn execute_draw(state: &mut GameState, from_discard: bool, card_id: Option<u8>) -> Result<u8, &'static str> {
    if state.current_action != GameAction::Draw {
        return Err("Not in draw phase");
    }

    let card = if from_discard {
        // Draw from last played cards
        let card = card_id.ok_or("Must specify card to draw from discard")?;
        if !state.last_cards_played.contains(&card) {
            return Err("Card not in last played");
        }
        if let Some(pos) = state.last_cards_played.iter().position(|&c| c == card) {
            state.last_cards_played.remove(pos);
        }
        // Track that this player took this card
        state.track_card_taken(state.current_turn, card);
        card
    } else {
        // Draw from deck
        if state.deck.is_empty() {
            // Reshuffle discard pile into deck
            if state.discard_pile.is_empty() {
                return Err("No cards to draw");
            }
            state.deck.append(&mut state.discard_pile);
            let mut rng = rand::thread_rng();
            state.deck.shuffle(&mut rng);
        }
        state.deck.pop().ok_or("Deck is empty")?
    };

    // Add to player's hand
    state.hands[state.current_turn as usize].push(card);

    // Update state
    state.last_action.action_type = 1; // draw
    state.last_action.player_index = state.current_turn;

    // Advance to next player
    state.advance_turn();
    state.current_action = GameAction::Play;

    Ok(card)
}

/// Execute a ZapZap call
pub fn execute_zapzap(state: &mut GameState) -> Result<ZapZapResult, &'static str> {
    let caller = state.current_turn;
    let hand = state.get_hand(caller);

    if !card_analyzer::can_call_zapzap(hand) {
        return Err("Hand value too high to call ZapZap");
    }

    let caller_value = card_analyzer::calculate_hand_value(hand);

    // Check for counteraction
    // A player counteracts the caller if their hand value is <= caller's value
    // (equal hand values mean the caller loses the counter)
    let mut counteracted_by: Option<u8> = None;
    let mut lowest_value = caller_value;

    for player in 0..state.player_count {
        if player != caller && !state.is_eliminated(player) {
            let hand_value = card_analyzer::calculate_hand_value(state.get_hand(player));
            if hand_value <= lowest_value {
                lowest_value = hand_value;
                counteracted_by = Some(player);
            }
        }
    }

    // Calculate scores
    let mut result = ZapZapResult {
        caller,
        caller_hand_value: caller_value,
        counteracted: counteracted_by.is_some(),
        counteracted_by,
        scores: Vec::new(),
    };

    // Determine who has lowest hand
    let winner = counteracted_by.unwrap_or(caller);

    for player in 0..state.player_count {
        if state.is_eliminated(player) {
            continue;
        }

        let hand = state.get_hand(player);
        let is_lowest = player == winner;
        let hand_score = card_analyzer::calculate_hand_score(hand, is_lowest);

        let round_score = if player == caller && counteracted_by.is_some() {
            // Caller was counteracted: gets hand value + penalty
            let penalty = (state.active_player_count() - 1) as u16 * 5;
            hand_score + penalty
        } else if is_lowest {
            0 // Lowest hand gets 0
        } else {
            hand_score
        };

        state.add_score(player, round_score);
        result.scores.push((player, round_score));
    }

    // Update last action
    state.last_action.action_type = 3; // zapzap
    state.last_action.player_index = caller;
    state.last_action.was_counteracted = counteracted_by.is_some();
    state.last_action.caller_hand_points = caller_value as u8;

    // Store round end data in game state
    let mut round_scores_array = [0u16; crate::domain::value_objects::MAX_PLAYERS];
    for (player_idx, score) in &result.scores {
        round_scores_array[*player_idx as usize] = *score;
    }
    state.round_scores = Some(round_scores_array);
    state.zapzap_caller = Some(caller);
    state.lowest_hand_player_index = Some(winner);
    state.was_counter_acted = Some(counteracted_by.is_some());
    state.counter_acted_by_player_index = counteracted_by;

    // Mark round as finished
    state.current_action = GameAction::Finished;

    Ok(result)
}

/// Result of a ZapZap call
#[derive(Debug, Clone)]
pub struct ZapZapResult {
    pub caller: u8,
    pub caller_hand_value: u16,
    pub counteracted: bool,
    pub counteracted_by: Option<u8>,
    pub scores: Vec<(u8, u16)>, // (player_index, round_score)
}

/// Check and update eliminations after a round
pub fn check_eliminations(state: &mut GameState) -> Vec<u8> {
    let mut newly_eliminated = Vec::new();

    for player in 0..state.player_count {
        if !state.is_eliminated(player) && state.get_score(player) > 100 {
            state.eliminate_player(player);
            newly_eliminated.push(player);
        }
    }

    newly_eliminated
}

/// Check if game is over
/// Returns the winner player index if game is finished
/// Game ends when:
/// 1. Only 1 player remains (all others eliminated with >100 points)
/// 2. Golden Score mode: game ends immediately after ZapZap call
///    - Winner is determined by lowest hand value
///    - If caller was counteracted (including ties), the counter-actor wins
pub fn is_game_over(state: &GameState) -> Option<u8> {
    let active = state.active_players();

    // Standard end: only 1 player remaining
    if active.len() == 1 {
        return Some(active[0]);
    }

    // Golden Score end: 2 players remaining and round just finished
    if state.is_golden_score && state.current_action == GameAction::Finished {
        // In Golden Score, winner is determined by the ZapZap result
        // lowest_hand_player_index is the player with lowest hand (winner of the ZapZap)
        if let Some(winner) = state.lowest_hand_player_index {
            return Some(winner);
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_initialize_round() {
        let scores = [0u16; 8];
        let state = initialize_round(4, 5, &scores, 0, 1, 0, Some(42));

        assert_eq!(state.player_count, 4);
        assert_eq!(state.round_number, 1);
        assert!(!state.is_golden_score);

        // Each player should have 5 cards
        for i in 0..4 {
            assert_eq!(state.hands[i].len(), 5);
        }

        // Deck should have 54 - 20 = 34 cards
        assert_eq!(state.deck.len(), 34);
    }

    #[test]
    fn test_golden_score_detection() {
        let scores = [0u16; 8];
        let eliminated_mask = 0b00001100; // Players 2 and 3 eliminated
        let state = initialize_round(4, 5, &scores, eliminated_mask, 5, 0, Some(42));

        assert!(state.is_golden_score);
        assert_eq!(state.active_player_count(), 2);
    }

    #[test]
    fn test_golden_score_game_end_caller_wins() {
        let scores = [0u16; 8];
        let eliminated_mask = 0b00001100; // Players 2 and 3 eliminated (only 0 and 1 active)
        let mut state = initialize_round(4, 5, &scores, eliminated_mask, 5, 0, Some(42));

        // Set up state as if round just finished with player 0 winning (lowest hand)
        state.is_golden_score = true;
        state.current_action = GameAction::Finished;
        state.lowest_hand_player_index = Some(0);

        // Game should be over with player 0 as winner
        let winner = is_game_over(&state);
        assert_eq!(winner, Some(0));
    }

    #[test]
    fn test_golden_score_game_end_caller_counteracted() {
        let scores = [0u16; 8];
        let eliminated_mask = 0b00001100; // Players 2 and 3 eliminated
        let mut state = initialize_round(4, 5, &scores, eliminated_mask, 5, 0, Some(42));

        // Set up state as if round just finished with player 1 winning (counteracted player 0)
        state.is_golden_score = true;
        state.current_action = GameAction::Finished;
        state.lowest_hand_player_index = Some(1); // Player 1 had lower/equal hand

        // Game should be over with player 1 as winner
        let winner = is_game_over(&state);
        assert_eq!(winner, Some(1));
    }

    #[test]
    fn test_golden_score_not_finished_no_winner() {
        let scores = [0u16; 8];
        let eliminated_mask = 0b00001100;
        let mut state = initialize_round(4, 5, &scores, eliminated_mask, 5, 0, Some(42));

        // Round still in progress
        state.is_golden_score = true;
        state.current_action = GameAction::Play;

        // Game should NOT be over yet
        let winner = is_game_over(&state);
        assert_eq!(winner, None);
    }

    #[test]
    fn test_zapzap_counteract_on_equal_hands() {
        // Test that equal hand values result in counteraction
        // According to rules: "Tie handling: equal hand values = caller loses"
        let scores = [0u16; 8];
        let eliminated_mask = 0b00001100; // Players 0 and 1 active
        let mut state = initialize_round(4, 5, &scores, eliminated_mask, 5, 0, Some(42));
        state.is_golden_score = true;

        // Give player 0 (caller) a hand with value 3: Ace + 2 (cards 0 and 1)
        state.hands[0].clear();
        state.hands[0].push(0); // Ace of spades (1)
        state.hands[0].push(1); // 2 of spades (2) = total 3 points
        // Give player 1 same value: Ace + 2 (cards 13 and 14 = hearts)
        state.hands[1].clear();
        state.hands[1].push(13); // Ace of hearts (1)
        state.hands[1].push(14); // 2 of hearts (2) = total 3 points

        state.current_turn = 0; // Player 0 calls ZapZap

        let result = execute_zapzap(&mut state).unwrap();

        // Player 0 should be counteracted because player 1 has equal hand value
        assert!(result.counteracted, "Equal hands should result in counteraction");
        assert_eq!(result.counteracted_by, Some(1), "Player 1 should be the counter-actor");

        // The winner should be player 1 (the counter-actor)
        assert_eq!(state.lowest_hand_player_index, Some(1));

        // In Golden Score mode, game should now be over with player 1 winning
        let winner = is_game_over(&state);
        assert_eq!(winner, Some(1), "In Golden Score tie, caller (player 0) should lose");
    }
}
