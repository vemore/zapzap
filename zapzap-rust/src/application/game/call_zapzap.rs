use std::sync::Arc;

use crate::domain::entities::PartyStatus;
use crate::domain::repositories::{PartyRepository, PlayerGameResult, RepositoryError, RoundScoreEntry};
use crate::domain::services::{check_eliminations, execute_zapzap, is_game_over};
use crate::domain::value_objects::GameAction;
use crate::infrastructure::bot::card_analyzer;

/// Call zapzap input
pub struct CallZapZapInput {
    pub party_id: String,
    pub user_id: String,
}

/// Call zapzap output
pub struct CallZapZapOutput {
    pub success: bool,
    pub counteracted: bool,
    pub counteracted_by: Option<String>,
    pub scores: Vec<(u8, u16)>,
    pub caller_hand_points: u16,
    pub eliminated_players: Vec<u8>,
    pub game_finished: bool,
    pub winner: Option<u8>,
}

/// Call zapzap use case
pub struct CallZapZap<P: PartyRepository> {
    party_repo: Arc<P>,
}

impl<P: PartyRepository> CallZapZap<P> {
    pub fn new(party_repo: Arc<P>) -> Self {
        Self { party_repo }
    }

    pub async fn execute(
        &self,
        input: CallZapZapInput,
    ) -> Result<CallZapZapOutput, CallZapZapError> {
        // Find party
        let party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(CallZapZapError::PartyNotFound)?;

        // Check party is playing
        if party.status != PartyStatus::Playing {
            return Err(CallZapZapError::PartyNotPlaying);
        }

        // Get player index
        let player_index = self
            .party_repo
            .get_player_index(&input.party_id, &input.user_id)
            .await?
            .ok_or(CallZapZapError::NotInParty)?;

        // Get game state
        let mut game_state = self
            .party_repo
            .get_game_state(&input.party_id)
            .await?
            .ok_or(CallZapZapError::NoGameState)?;

        // Check it's player's turn
        if game_state.current_turn != player_index {
            return Err(CallZapZapError::NotYourTurn);
        }

        // Check action is Play (can call zapzap during play phase)
        if game_state.current_action != GameAction::Play {
            return Err(CallZapZapError::WrongAction);
        }

        // Check if player can call zapzap
        let hand = game_state.get_hand(player_index);
        if !card_analyzer::can_call_zapzap(hand) {
            return Err(CallZapZapError::HandTooHigh);
        }

        // Execute zapzap
        let result = execute_zapzap(&mut game_state)
            .map_err(|e| CallZapZapError::GameError(e.to_string()))?;

        // Check eliminations
        let eliminated = check_eliminations(&mut game_state);

        // Check if game is over
        let winner = is_game_over(&game_state);

        // Save game state
        self.party_repo
            .save_game_state(&input.party_id, &game_state)
            .await?;

        // Update round as finished
        if let Some(mut round) = self.party_repo.get_current_round(&input.party_id).await? {
            round.finish();
            self.party_repo.save_round(&round).await?;
        }

        // Save round scores for history
        let players = self.party_repo.get_party_players(&input.party_id).await?;
        let round_scores: Vec<RoundScoreEntry> = players
            .iter()
            .map(|p| {
                let player_idx = p.player_index;
                let hand = game_state.get_hand(player_idx);
                let hand_value = card_analyzer::calculate_hand_value(hand);
                let round_score = result.scores.iter()
                    .find(|(idx, _)| *idx == player_idx)
                    .map(|(_, score)| *score)
                    .unwrap_or(0);

                RoundScoreEntry {
                    user_id: p.user_id.clone(),
                    player_index: player_idx,
                    score_this_round: round_score,
                    total_score_after: game_state.get_score(player_idx),
                    hand_points: hand_value,
                    is_zapzap_caller: game_state.zapzap_caller == Some(player_idx),
                    zapzap_success: game_state.zapzap_caller == Some(player_idx) && !result.counteracted,
                    was_counteracted: game_state.zapzap_caller == Some(player_idx) && result.counteracted,
                    hand_cards: hand.to_vec(),
                    is_lowest_hand: game_state.lowest_hand_player_index == Some(player_idx),
                    is_eliminated: game_state.is_eliminated(player_idx),
                }
            })
            .collect();

        self.party_repo
            .save_round_scores(&input.party_id, game_state.round_number as u32, round_scores)
            .await?;

        // If game is over, update party status and save game results
        if let Some(winner_idx) = winner {
            // Update party status to Finished
            let mut party = self
                .party_repo
                .find_by_id(&input.party_id)
                .await?
                .ok_or(CallZapZapError::PartyNotFound)?;
            party.finish();
            self.party_repo.save(&party).await?;

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
            let winner_idx_copy = winner_idx;
            player_results.sort_by(|a, b| {
                let (idx_a, score_a, _, elim_a) = a;
                let (idx_b, score_b, _, elim_b) = b;

                // Winner always first
                if *idx_a == winner_idx_copy {
                    return std::cmp::Ordering::Less;
                }
                if *idx_b == winner_idx_copy {
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
                .find(|p| p.player_index == winner_idx)
                .map(|p| p.user_id.clone())
                .unwrap_or_default();

            let winner_score = game_state.scores[winner_idx as usize];

            // Create PlayerGameResult entries
            let results: Vec<PlayerGameResult> = player_results
                .iter()
                .enumerate()
                .map(|(position, (player_index, final_score, user_id, _))| PlayerGameResult {
                    user_id: user_id.clone(),
                    final_score: *final_score,
                    finish_position: (position + 1) as u8,
                    rounds_played: game_state.round_number as u32,
                    is_winner: *player_index == winner_idx,
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
        }

        // Get counteracted by username
        let counteracted_by_id = result.counteracted_by.map(|idx| {
            // Would need to look up user, for now just return index as string
            format!("player_{}", idx)
        });

        Ok(CallZapZapOutput {
            success: !result.counteracted,
            counteracted: result.counteracted,
            counteracted_by: counteracted_by_id,
            scores: result.scores,
            caller_hand_points: result.caller_hand_value,
            eliminated_players: eliminated,
            game_finished: winner.is_some(),
            winner,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum CallZapZapError {
    #[error("Party not found")]
    PartyNotFound,
    #[error("Party is not playing")]
    PartyNotPlaying,
    #[error("Not in party")]
    NotInParty,
    #[error("No game state")]
    NoGameState,
    #[error("Not your turn")]
    NotYourTurn,
    #[error("Wrong action phase")]
    WrongAction,
    #[error("Hand value too high to call ZapZap")]
    HandTooHigh,
    #[error("Game error: {0}")]
    GameError(String),
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
