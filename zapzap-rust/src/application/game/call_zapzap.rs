use std::sync::Arc;

use crate::domain::entities::PartyStatus;
use crate::domain::repositories::{
    GameWrite, PartyRepository, RepositoryError, RoundScoreEntry, RoundWrite, VersionedGameState,
};
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

        // Each seat's score for history. The seats are read before the write: a seat that
        // changed hands since the state was read (an ejection, an account deletion) wrote
        // a new version, and the write below is then refused
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

        // Save the game state, finish the round with its scores and, when the game is
        // over, finish the party with its results, all in one transaction, unless another
        // write came in since the read (a forfeit, a second request, an admin stop), or the
        // seat is no longer this player's (an ejection by the turn timer after the seat was
        // read): `Conflict`, and nothing is written
        let results = self
            .party_repo
            .write_game(&GameWrite {
                party_id: &input.party_id,
                state: &game_state,
                expected_version: version,
                seat_holder: Some((player_index, &input.user_id)),
                round: RoundWrite::Finish(&round_scores),
                winner,
            })
            .await?;
        let winner_user_id = results.map(|results| results.winner_user_id);

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
