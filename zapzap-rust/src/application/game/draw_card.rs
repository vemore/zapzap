use std::sync::Arc;

use crate::domain::entities::PartyStatus;
use crate::domain::repositories::{
    GameWrite, PartyRepository, RepositoryError, RoundWrite, VersionedGameState,
};
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
        let VersionedGameState {
            state: mut game_state,
            version,
        } = self
            .party_repo
            .get_versioned_game_state(&input.party_id)
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

        // Client errors of the draw itself, typed before the domain call
        let from_discard = input.source == "played";
        let card_id = if from_discard {
            // No cardId: the top played card, as Node's DrawCard does
            let top = *game_state
                .last_cards_played
                .last()
                .ok_or(DrawCardError::NoCardsAvailable)?;
            let card = input.card_id.unwrap_or(top);
            if !game_state.last_cards_played.contains(&card) {
                return Err(DrawCardError::CardNotAvailable);
            }
            Some(card)
        } else {
            if game_state.deck.is_empty() && game_state.discard_pile.is_empty() {
                return Err(DrawCardError::DeckEmpty);
            }
            input.card_id
        };

        // Execute draw
        let card_drawn = execute_draw(&mut game_state, from_discard, card_id)
            .map_err(|e| DrawCardError::GameError(e.to_string()))?;

        // Save the game state and the round's turn and action, in one transaction, unless
        // another write came in since the read (a forfeit, a second request, an admin
        // stop), or the seat is no longer this player's (an ejection by the turn timer
        // after the seat was read): `Conflict`, and nothing is written
        self.party_repo
            .write_game(&GameWrite {
                party_id: &input.party_id,
                state: &game_state,
                expected_version: version,
                seat_holder: Some((player_index, &input.user_id)),
                round: RoundWrite::Progress,
                winner: None,
            })
            .await?;

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
    #[error("Deck is empty and no cards to reshuffle")]
    DeckEmpty,
    #[error("No cards available to draw from played cards")]
    NoCardsAvailable,
    #[error("Card not available in played cards")]
    CardNotAvailable,
    #[error("Game error: {0}")]
    GameError(String),
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
