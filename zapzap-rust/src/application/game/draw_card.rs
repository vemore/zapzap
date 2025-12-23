use std::sync::Arc;

use crate::domain::entities::PartyStatus;
use crate::domain::repositories::{PartyRepository, RepositoryError};
use crate::domain::services::execute_draw;
use crate::domain::value_objects::GameAction;

/// Draw card input
pub struct DrawCardInput {
    pub party_id: String,
    pub user_id: String,
    pub source: String, // "deck" or "played"
    pub card_id: Option<u8>,
}

/// Draw card output
pub struct DrawCardOutput {
    pub card_drawn: u8,
    pub source: String,
    pub hand_size: usize,
}

/// Draw card use case
pub struct DrawCard<P: PartyRepository> {
    party_repo: Arc<P>,
}

impl<P: PartyRepository> DrawCard<P> {
    pub fn new(party_repo: Arc<P>) -> Self {
        Self { party_repo }
    }

    pub async fn execute(&self, input: DrawCardInput) -> Result<DrawCardOutput, DrawCardError> {
        // Find party
        let party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(DrawCardError::PartyNotFound)?;

        // Check party is playing
        if party.status != PartyStatus::Playing {
            return Err(DrawCardError::PartyNotPlaying);
        }

        // Get player index
        let player_index = self
            .party_repo
            .get_player_index(&input.party_id, &input.user_id)
            .await?
            .ok_or(DrawCardError::NotInParty)?;

        // Get game state
        let mut game_state = self
            .party_repo
            .get_game_state(&input.party_id)
            .await?
            .ok_or(DrawCardError::NoGameState)?;

        // Check it's player's turn
        if game_state.current_turn != player_index {
            return Err(DrawCardError::NotYourTurn);
        }

        // Check action is Draw
        if game_state.current_action != GameAction::Draw {
            return Err(DrawCardError::WrongAction);
        }

        // Execute draw
        let from_discard = input.source == "played";
        let card_drawn = execute_draw(&mut game_state, from_discard, input.card_id)
            .map_err(|e| DrawCardError::GameError(e.to_string()))?;

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

        let hand_size = game_state.get_hand(player_index).len();

        Ok(DrawCardOutput {
            card_drawn,
            source: input.source,
            hand_size,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum DrawCardError {
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
    #[error("Game error: {0}")]
    GameError(String),
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
