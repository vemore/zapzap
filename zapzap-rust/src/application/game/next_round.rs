use std::sync::Arc;

use uuid::Uuid;

use crate::domain::entities::{PartyStatus, Round};
use crate::domain::repositories::{PartyRepository, PlayerGameResult, RepositoryError};
use crate::domain::services::{initialize_round, is_game_over};
use crate::domain::value_objects::GameAction;

/// Next round input
pub struct NextRoundInput {
    pub party_id: String,
    pub user_id: String,
}

/// Next round output
pub struct NextRoundOutput {
    pub round: Option<Round>,
    pub game_finished: bool,
    pub winner: Option<u8>,
    pub eliminated_players: Vec<u8>,
    pub starting_player: u8,
    /// Current scores for all players
    pub scores: Vec<u16>,
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
        let game_state = self
            .party_repo
            .get_game_state(&input.party_id)
            .await?
            .ok_or(NextRoundError::NoGameState)?;

        // Check current round is finished
        if game_state.current_action != GameAction::Finished {
            return Err(NextRoundError::RoundNotFinished);
        }

        // Check if game is over
        if let Some(winner) = is_game_over(&game_state) {
            // Mark party as finished
            party.finish();
            self.party_repo.save(&party).await?;

            // Get eliminated players
            let eliminated: Vec<u8> = (0..game_state.player_count)
                .filter(|&i| game_state.is_eliminated(i))
                .collect();

            // Get final scores
            let scores: Vec<u16> = (0..game_state.player_count as usize)
                .map(|i| game_state.scores[i])
                .collect();

            // Get players for saving results
            let players = self.party_repo.get_party_players(&input.party_id).await?;

            // Get elimination order (user_id -> elimination_round)
            let elimination_order = self.party_repo.get_elimination_order(&input.party_id).await?;
            let elimination_map: std::collections::HashMap<String, Option<u32>> = elimination_order
                .into_iter()
                .collect();

            // Build player results with elimination info
            let mut player_results: Vec<(u8, u16, String, Option<u32>)> = players
                .iter()
                .map(|p| {
                    let elimination_round = elimination_map.get(&p.user_id).cloned().flatten();
                    (p.player_index, game_state.scores[p.player_index as usize], p.user_id.clone(), elimination_round)
                })
                .collect();

            // Sort by: winner first, then by elimination order (later = better), never eliminated by score
            let winner_copy = winner;
            player_results.sort_by(|a, b| {
                let (idx_a, score_a, _, elim_a) = a;
                let (idx_b, score_b, _, elim_b) = b;

                // Winner always first
                if *idx_a == winner_copy {
                    return std::cmp::Ordering::Less;
                }
                if *idx_b == winner_copy {
                    return std::cmp::Ordering::Greater;
                }

                // Non-eliminated before eliminated
                match (elim_a, elim_b) {
                    (None, Some(_)) => std::cmp::Ordering::Less,
                    (Some(_), None) => std::cmp::Ordering::Greater,
                    (None, None) => score_a.cmp(score_b), // Both not eliminated: lower score = better
                    (Some(r_a), Some(r_b)) => r_b.cmp(r_a), // Both eliminated: later round = better position
                }
            });

            let winner_user_id = players
                .iter()
                .find(|p| p.player_index == winner)
                .map(|p| p.user_id.clone())
                .unwrap_or_default();

            let winner_score = game_state.scores[winner as usize];

            // Create PlayerGameResult entries
            let results: Vec<PlayerGameResult> = player_results
                .iter()
                .enumerate()
                .map(|(position, (player_index, final_score, user_id, _))| PlayerGameResult {
                    user_id: user_id.clone(),
                    final_score: *final_score,
                    finish_position: (position + 1) as u8,
                    rounds_played: game_state.round_number as u32,
                    is_winner: *player_index == winner,
                })
                .collect();

            // Save game results
            self.party_repo
                .save_game_results(
                    &input.party_id,
                    &winner_user_id,
                    winner_score,
                    game_state.round_number as u32,
                    game_state.is_golden_score,
                    results,
                )
                .await?;

            return Ok(NextRoundOutput {
                round: None,
                game_finished: true,
                winner: Some(winner),
                eliminated_players: eliminated,
                starting_player: game_state.starting_player,
                scores,
            });
        }

        // Get players
        let players = self.party_repo.get_party_players(&input.party_id).await?;

        // Calculate next starting player (rotate)
        let next_starting_player = (game_state.starting_player + 1) % game_state.player_count;

        // Create scores array
        let mut scores = [0u16; 8];
        for i in 0..game_state.player_count as usize {
            scores[i] = game_state.scores[i];
        }

        // Initialize new round
        let new_round_number = game_state.round_number + 1;
        let new_game_state = initialize_round(
            players.len() as u8,
            party.settings.hand_size,
            &scores,
            game_state.eliminated_mask,
            new_round_number,
            next_starting_player,
            None,
        );

        // Create round record
        let round_id = Uuid::new_v4().to_string();
        let round = Round::new(
            round_id.clone(),
            input.party_id.clone(),
            new_round_number as u32,
            next_starting_player,
        );

        // Save round
        self.party_repo.save_round(&round).await?;

        // Save game state
        self.party_repo
            .save_game_state(&input.party_id, &new_game_state)
            .await?;

        // Update party current round
        party.current_round_id = Some(round_id);
        self.party_repo.save(&party).await?;

        // Get eliminated players
        let eliminated: Vec<u8> = (0..new_game_state.player_count)
            .filter(|&i| new_game_state.is_eliminated(i))
            .collect();

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
