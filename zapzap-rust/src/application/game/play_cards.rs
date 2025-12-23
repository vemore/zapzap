use std::sync::Arc;

use crate::domain::entities::PartyStatus;
use crate::domain::repositories::{PartyRepository, RepositoryError};
use crate::domain::services::execute_play;
use crate::domain::value_objects::GameAction;
use crate::infrastructure::bot::card_analyzer;

/// Play cards input
pub struct PlayCardsInput {
    pub party_id: String,
    pub user_id: String,
    pub card_ids: Vec<u8>,
}

/// Play cards output
pub struct PlayCardsOutput {
    pub cards_played: Vec<u8>,
    pub remaining_cards: usize,
}

/// Play cards use case
pub struct PlayCards<P: PartyRepository> {
    party_repo: Arc<P>,
}

impl<P: PartyRepository> PlayCards<P> {
    pub fn new(party_repo: Arc<P>) -> Self {
        Self { party_repo }
    }

    pub async fn execute(&self, input: PlayCardsInput) -> Result<PlayCardsOutput, PlayCardsError> {
        // Find party
        let party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(PlayCardsError::PartyNotFound)?;

        // Check party is playing
        if party.status != PartyStatus::Playing {
            return Err(PlayCardsError::PartyNotPlaying);
        }

        // Get player index
        let player_index = self
            .party_repo
            .get_player_index(&input.party_id, &input.user_id)
            .await?
            .ok_or(PlayCardsError::NotInParty)?;

        // Get game state
        let mut game_state = self
            .party_repo
            .get_game_state(&input.party_id)
            .await?
            .ok_or(PlayCardsError::NoGameState)?;

        // Check it's player's turn
        if game_state.current_turn != player_index {
            return Err(PlayCardsError::NotYourTurn);
        }

        // Check action is Play
        if game_state.current_action != GameAction::Play {
            return Err(PlayCardsError::WrongAction);
        }

        // Validate cards
        if input.card_ids.is_empty() {
            return Err(PlayCardsError::NoCardsSelected);
        }

        if !card_analyzer::is_valid_play(&input.card_ids) {
            return Err(PlayCardsError::InvalidCombination);
        }

        // Execute play
        execute_play(&mut game_state, &input.card_ids)
            .map_err(|e| PlayCardsError::GameError(e.to_string()))?;

        // Save game state
        self.party_repo
            .save_game_state(&input.party_id, &game_state)
            .await?;

        // Update round
        if let Some(mut round) = self.party_repo.get_current_round(&input.party_id).await? {
            round.current_turn = game_state.current_turn;
            round.current_action = game_state.current_action.as_str().to_string();
            self.party_repo.save_round(&round).await?;
        }

        let remaining_cards = game_state.get_hand(player_index).len();

        Ok(PlayCardsOutput {
            cards_played: input.card_ids,
            remaining_cards,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum PlayCardsError {
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
    #[error("No cards selected")]
    NoCardsSelected,
    #[error("Invalid card combination")]
    InvalidCombination,
    #[error("Game error: {0}")]
    GameError(String),
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
