use std::sync::Arc;

use crate::domain::entities::PartyStatus;
use crate::domain::repositories::{PartyRepository, RepositoryError};
use crate::domain::services::hand_size_bounds;
use crate::domain::value_objects::{GameAction, LastAction, LAST_ACTION_SELECT_HAND_SIZE};

/// Select hand size input
pub struct SelectHandSizeInput {
    pub party_id: String,
    pub user_id: String,
    pub hand_size: u8,
}

/// Select hand size output
pub struct SelectHandSizeOutput {
    pub hand_size: u8,
}

/// Select hand size use case
pub struct SelectHandSize<P: PartyRepository> {
    party_repo: Arc<P>,
}

impl<P: PartyRepository> SelectHandSize<P> {
    pub fn new(party_repo: Arc<P>) -> Self {
        Self { party_repo }
    }

    pub async fn execute(
        &self,
        input: SelectHandSizeInput,
    ) -> Result<SelectHandSizeOutput, SelectHandSizeError> {
        // Find party
        let party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(SelectHandSizeError::PartyNotFound)?;

        // Check party is playing
        if party.status != PartyStatus::Playing {
            return Err(SelectHandSizeError::PartyNotPlaying);
        }

        // Get player index
        let player_index = self
            .party_repo
            .get_player_index(&input.party_id, &input.user_id)
            .await?
            .ok_or(SelectHandSizeError::NotInParty)?;

        // Get game state
        let mut game_state = self
            .party_repo
            .get_game_state(&input.party_id)
            .await?
            .ok_or(SelectHandSizeError::NoGameState)?;

        // Phase, then turn, then size: the order of Node's SelectHandSize
        if game_state.current_action != GameAction::SelectHandSize {
            return Err(SelectHandSizeError::WrongAction);
        }

        if game_state.current_turn != player_index {
            return Err(SelectHandSizeError::NotYourTurn);
        }

        // 4-7 cards, 4-10 in Golden Score, and no more than the deck can deal
        let (min, max) = hand_size_bounds(&game_state);
        if input.hand_size < min || input.hand_size > max {
            return Err(SelectHandSizeError::InvalidHandSize { min, max });
        }

        // Re-deal cards with the selected hand size
        // First, collect all cards back into deck
        let mut all_cards: Vec<u8> = game_state.deck.clone();
        for i in 0..game_state.player_count as usize {
            all_cards.extend(game_state.hands[i].iter().copied());
            game_state.hands[i].clear();
        }
        all_cards.extend(game_state.last_cards_played.iter().copied());
        game_state.last_cards_played.clear();
        all_cards.extend(game_state.cards_played.iter().copied());
        game_state.cards_played.clear();
        all_cards.extend(game_state.discard_pile.iter().copied());
        game_state.discard_pile.clear();

        // Shuffle the deck
        {
            use rand::seq::SliceRandom;
            let mut rng = rand::rng();
            all_cards.shuffle(&mut rng);
        }

        // Deal cards to active players with the selected hand size
        for player in 0..game_state.player_count {
            if !game_state.is_eliminated(player) {
                for _ in 0..input.hand_size {
                    if let Some(card) = all_cards.pop() {
                        game_state.hands[player as usize].push(card);
                    }
                }
            }
        }

        // Put remaining cards back in deck
        game_state.deck = all_cards;

        // Flip first card from deck to played pile (so first player has a choice)
        if let Some(first_card) = game_state.deck.pop() {
            game_state.last_cards_played.push(first_card);
        }

        // Update action to Play
        game_state.current_action = GameAction::Play;
        game_state.last_action = LastAction {
            action_type: LAST_ACTION_SELECT_HAND_SIZE,
            player_index,
            hand_size: input.hand_size,
            ..LastAction::default()
        };

        // Save game state
        self.party_repo
            .save_game_state(&input.party_id, &game_state)
            .await?;

        // Update round
        if let Some(mut round) = self.party_repo.get_current_round(&input.party_id).await? {
            round.current_action = "play".to_string();
            self.party_repo.save_round(&round).await?;
        }

        Ok(SelectHandSizeOutput {
            hand_size: input.hand_size,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum SelectHandSizeError {
    #[error("Hand size must be between {min} and {max}")]
    InvalidHandSize { min: u8, max: u8 },
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
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
