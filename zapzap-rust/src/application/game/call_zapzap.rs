use std::sync::Arc;

use crate::domain::entities::PartyStatus;
use crate::domain::repositories::{
    PartyRepository, RepositoryError, RoundScoreEntry, VersionedGameState,
};
use crate::domain::services::{
    build_game_results, check_eliminations, execute_zapzap, is_game_over,
};
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
    /// Player index of the counteracting player
    pub counteracted_by: Option<u8>,
    /// Running totals after this round, one per seat (Node's `scores`)
    pub total_scores: Vec<(u8, u16)>,
    /// Points this round, active players only
    pub round_scores: Vec<(u8, u16)>,
    /// Hand value with Joker = 25, active players only (Node's `handPoints`)
    pub hand_points: Vec<(u8, u16)>,
    /// Caller's hand value with Joker = 0 (Node's `callerPoints`)
    pub caller_hand_points: u16,
    pub eliminated_players: Vec<u8>,
    pub game_finished: bool,
    pub winner: Option<u8>,
    /// Winner's user id, when the game is finished
    pub winner_user_id: Option<String>,
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
        let VersionedGameState {
            state: mut game_state,
            version,
        } = self
            .party_repo
            .get_versioned_game_state(&input.party_id)
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

        // Save game state, unless another write came in since the read (a forfeit, a
        // second request), or the seat is no longer this player's (an ejection by the turn
        // timer after the seat was read): `Conflict`, and nothing below runs
        self.party_repo
            .update_game_state_for_player(
                &input.party_id,
                &game_state,
                version,
                player_index,
                &input.user_id,
            )
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
                let round_score = result
                    .scores
                    .iter()
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
                    zapzap_success: game_state.zapzap_caller == Some(player_idx)
                        && !result.counteracted,
                    was_counteracted: game_state.zapzap_caller == Some(player_idx)
                        && result.counteracted,
                    hand_cards: hand.to_vec(),
                    is_lowest_hand: game_state.lowest_hand_player_index == Some(player_idx),
                    is_eliminated: game_state.is_eliminated(player_idx),
                }
            })
            .collect();

        self.party_repo
            .save_round_scores(
                &input.party_id,
                game_state.round_number as u32,
                round_scores,
            )
            .await?;

        let winner_user_id = winner.and_then(|w| {
            players
                .iter()
                .find(|p| p.player_index == w)
                .map(|p| p.user_id.clone())
        });

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

            let elimination_order = self
                .party_repo
                .get_elimination_order(&input.party_id)
                .await?;
            let results = build_game_results(
                &game_state,
                players.iter().map(|p| (p.player_index, p.user_id.clone())),
                &elimination_order,
                winner_idx,
            );
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
        }

        let total_scores = (0..game_state.player_count)
            .map(|i| (i, game_state.get_score(i)))
            .collect();
        let hand_points = result
            .scores
            .iter()
            .map(|&(i, _)| {
                (
                    i,
                    card_analyzer::calculate_hand_score(game_state.get_hand(i), false),
                )
            })
            .collect();

        Ok(CallZapZapOutput {
            success: !result.counteracted,
            counteracted: result.counteracted,
            counteracted_by: result.counteracted_by,
            total_scores,
            round_scores: result.scores,
            hand_points,
            caller_hand_points: result.caller_hand_value,
            eliminated_players: eliminated,
            game_finished: winner.is_some(),
            winner,
            winner_user_id,
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
