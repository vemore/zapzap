use std::sync::Arc;

use uuid::Uuid;

use crate::domain::entities::{PartyPlayer, PartyStatus, Round};
use crate::domain::repositories::{PartyRepository, RepositoryError, VersionedGameState};
use crate::domain::services::{build_game_results, initialize_round, is_game_over};
use crate::domain::value_objects::{GameAction, GameState};

/// Next round input
pub struct NextRoundInput {
    pub party_id: String,
    pub user_id: String,
}

/// A seat and its running total: Node's `{userId, playerIndex, score}`
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SeatScore {
    pub user_id: String,
    pub player_index: u8,
    pub score: u16,
}

/// Next round output
pub struct NextRoundOutput {
    pub round: Option<Round>,
    pub game_finished: bool,
    pub winner: Option<SeatScore>,
    /// Every player out of the game (score > 100), by seat
    pub eliminated_players: Vec<SeatScore>,
    pub starting_player: u8,
    /// Running totals, one per seat
    pub scores: Vec<u16>,
}

/// The eliminated seats of `game_state` among `players`, by seat
fn eliminated_seats(game_state: &GameState, players: &[PartyPlayer]) -> Vec<SeatScore> {
    let mut out: Vec<SeatScore> = players
        .iter()
        .filter(|p| game_state.is_eliminated(p.player_index))
        .map(|p| SeatScore {
            user_id: p.user_id.clone(),
            player_index: p.player_index,
            score: game_state.get_score(p.player_index),
        })
        .collect();
    out.sort_by_key(|s| s.player_index);
    out
}

/// Next round use case
pub struct NextRound<P: PartyRepository> {
    party_repo: Arc<P>,
}

impl<P: PartyRepository> NextRound<P> {
    pub fn new(party_repo: Arc<P>) -> Self {
        Self { party_repo }
    }

    pub async fn execute(&self, input: NextRoundInput) -> Result<NextRoundOutput, NextRoundError> {
        // Find party
        let mut party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(NextRoundError::PartyNotFound)?;

        // Check party is playing
        if party.status != PartyStatus::Playing {
            return Err(NextRoundError::PartyNotPlaying);
        }

        // Get game state
        let VersionedGameState {
            state: game_state,
            version,
        } = self
            .party_repo
            .get_versioned_game_state(&input.party_id)
            .await?
            .ok_or(NextRoundError::NoGameState)?;

        // Check current round is finished
        if game_state.current_action != GameAction::Finished {
            return Err(NextRoundError::RoundNotFinished);
        }

        // Check if game is over. Unreachable in normal play: the zapzap that ends the game
        // finishes the party (`call_zapzap.rs`), and a finished party is refused above.
        // It recovers a zapzap stopped between saving the round and finishing the party;
        // that zapzap finishes the party before it saves the game results, so they are
        // not saved yet, and this branch finishes the party first too: a second call is
        // refused. (Both writes are upserts on `party_id` besides.)
        if let Some(winner) = is_game_over(&game_state) {
            // Mark party as finished
            party.finish();
            self.party_repo.save(&party).await?;

            // Get final scores
            let scores: Vec<u16> = (0..game_state.player_count as usize)
                .map(|i| game_state.scores[i])
                .collect();

            // Get players for saving results
            let players = self.party_repo.get_party_players(&input.party_id).await?;

            let elimination_order = self
                .party_repo
                .get_elimination_order(&input.party_id)
                .await?;
            let ejected = self.party_repo.get_ejected_players(&input.party_id).await?;
            let results = build_game_results(
                &game_state,
                players.iter().map(|p| (p.player_index, p.user_id.clone())),
                &elimination_order,
                &ejected,
                winner,
            );
            let winner_user_id = results.winner_user_id.clone();
            let winner_score = results.winner_score;
            self.party_repo
                .save_game_results(
                    &input.party_id,
                    &results.winner_user_id,
                    results.winner_score,
                    results.total_rounds,
                    results.was_golden_score,
                    results.players,
                )
                .await?;

            // Once the game is over every other seat is out, as on Node, where the golden
            // score's loser joins the players past 100
            let mut eliminated: Vec<SeatScore> = players
                .iter()
                .filter(|p| p.player_index != winner)
                .map(|p| SeatScore {
                    user_id: p.user_id.clone(),
                    player_index: p.player_index,
                    score: game_state.get_score(p.player_index),
                })
                .collect();
            eliminated.sort_by_key(|s| s.player_index);

            return Ok(NextRoundOutput {
                round: None,
                game_finished: true,
                winner: Some(SeatScore {
                    user_id: winner_user_id,
                    player_index: winner,
                    score: winner_score,
                }),
                eliminated_players: eliminated,
                starting_player: game_state.starting_player,
                scores,
            });
        }

        // Get players
        let players = self.party_repo.get_party_players(&input.party_id).await?;

        let next_starting_player = next_starting_player(&game_state);

        // Create scores array
        let mut scores = [0u16; 8];
        let n = game_state.player_count as usize;
        scores[..n].copy_from_slice(&game_state.scores[..n]);

        // Initialize new round
        let new_round_number = game_state.round_number + 1;
        let mut new_game_state = initialize_round(
            players.len() as u8,
            crate::domain::value_objects::PROVISIONAL_HAND_SIZE,
            &scores,
            game_state.eliminated_mask,
            new_round_number,
            next_starting_player,
            None,
        );
        // The turn clock runs on, for the same seats; the starter's turn begins now
        new_game_state.turn_clock = game_state.turn_clock.clone();

        // Create round record
        let round_id = Uuid::new_v4().to_string();
        let round = Round::new(
            round_id.clone(),
            input.party_id.clone(),
            new_round_number as u32,
            next_starting_player,
        );

        // Save game state first, unless another write came in since the read (a second
        // nextRound, a forfeit): `Conflict`, and no round row is written
        self.party_repo
            .update_game_state(&input.party_id, &new_game_state, version)
            .await?;

        // Save round
        self.party_repo.save_round(&round).await?;

        // Update party current round
        party.current_round_id = Some(round_id);
        self.party_repo.save(&party).await?;

        // Get eliminated players
        let eliminated = eliminated_seats(&new_game_state, &players);

        // Get current scores from new game state
        let scores: Vec<u16> = (0..new_game_state.player_count as usize)
            .map(|i| new_game_state.scores[i])
            .collect();

        Ok(NextRoundOutput {
            round: Some(round),
            game_finished: false,
            winner: None,
            eliminated_players: eliminated,
            starting_player: next_starting_player,
            scores,
        })
    }
}

/// The next round's starter: the seat after this round's starter, clockwise, skipping
/// eliminated players (GAME_RULES.md "Subsequent Rounds")
pub fn next_starting_player(game_state: &GameState) -> u8 {
    let n = game_state.player_count.max(1);
    (1..=n)
        .map(|step| (game_state.starting_player + step) % n)
        .find(|&seat| !game_state.is_eliminated(seat))
        .unwrap_or(game_state.starting_player)
}

#[derive(Debug, thiserror::Error)]
pub enum NextRoundError {
    #[error("Party not found")]
    PartyNotFound,
    #[error("Party is not playing")]
    PartyNotPlaying,
    #[error("No game state")]
    NoGameState,
    #[error("Current round is not finished")]
    RoundNotFinished,
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state(player_count: u8, starting_player: u8, eliminated: &[u8]) -> GameState {
        let mut gs = GameState::new(player_count);
        gs.starting_player = starting_player;
        for &p in eliminated {
            gs.eliminate_player(p);
        }
        gs
    }

    #[test]
    fn test_next_starter_rotates() {
        assert_eq!(next_starting_player(&state(4, 0, &[])), 1);
        assert_eq!(next_starting_player(&state(4, 3, &[])), 0);
    }

    #[test]
    fn test_next_starter_skips_an_eliminated_seat() {
        // Seat 1 is next in line but out of the game: seat 2 starts
        assert_eq!(next_starting_player(&state(4, 0, &[1])), 2);
        assert_eq!(next_starting_player(&state(5, 0, &[1, 2, 3])), 4);
    }

    #[test]
    fn test_next_starter_wraps_past_the_last_seat() {
        // From the last seat the rotation wraps to seat 0, skipping it when eliminated
        assert_eq!(next_starting_player(&state(4, 2, &[3])), 0);
        assert_eq!(next_starting_player(&state(4, 2, &[3, 0])), 1);
    }
}
