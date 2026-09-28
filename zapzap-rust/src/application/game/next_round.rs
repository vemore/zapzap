use std::sync::Arc;

use uuid::Uuid;

use crate::domain::entities::{PartyPlayer, PartyStatus, Round};
use crate::domain::repositories::{
    GameWrite, PartyRepository, RepositoryError, RoundWrite, VersionedGameState,
};
use crate::domain::services::{initialize_round, is_game_over};
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
        let party = self
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

        // Check if game is over. Unreachable since a zapzap writes the end of the game in
        // one transaction (`call_zapzap.rs`): the party is finished with the state, and a
        // finished party is refused above. It recovers a game an earlier version left
        // half-written (the state over, the party still playing): the party is finished
        // and the results written, under the compare-and-swap, so a second call is
        // refused. (The results are upserts on `party_id` besides.)
        if let Some(winner) = is_game_over(&game_state) {
            // Get final scores
            let scores: Vec<u16> = (0..game_state.player_count as usize)
                .map(|i| game_state.scores[i])
                .collect();

            let players = self.party_repo.get_party_players(&input.party_id).await?;

            let results = self
                .party_repo
                .write_game(&GameWrite {
                    party_id: &input.party_id,
                    state: &game_state,
                    expected_version: version,
                    seat_holder: None,
                    round: RoundWrite::Unchanged,
                    winner: Some(winner),
                })
                .await?
                .ok_or_else(|| {
                    RepositoryError::Database("a finished game wrote no results".to_string())
                })?;
            let winner_user_id = results.winner_user_id;
            let winner_score = results.winner_score;

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
        let round = Round::new(
            Uuid::new_v4().to_string(),
            input.party_id.clone(),
            new_round_number as u32,
            next_starting_player,
        );

        // Save the new round's state, its row and the party's current round, in one
        // transaction, unless another write came in since the read (a second nextRound, a
        // forfeit, an admin stop): `Conflict`, and nothing is written. Only the party's
        // current round is written, so a forfeit that passed the party on since it was
        // read stands.
        self.party_repo
            .write_game(&GameWrite {
                party_id: &input.party_id,
                state: &new_game_state,
                expected_version: version,
                seat_holder: None,
                round: RoundWrite::Start(&round),
                winner: None,
            })
            .await?;

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
