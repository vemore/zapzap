use std::sync::Arc;

use uuid::Uuid;

use crate::domain::entities::{Party, PartyStatus, Round};
use crate::domain::repositories::{PartyRepository, RepositoryError};
use crate::domain::services::initialize_round;

/// Start party input
pub struct StartPartyInput {
    pub user_id: String,
    pub party_id: String,
}

/// Start party output
pub struct StartPartyOutput {
    pub party: Party,
    pub round: Round,
}

/// Start party use case
pub struct StartParty<P: PartyRepository> {
    party_repo: Arc<P>,
}

impl<P: PartyRepository> StartParty<P> {
    pub fn new(party_repo: Arc<P>) -> Self {
        Self { party_repo }
    }

    pub async fn execute(
        &self,
        input: StartPartyInput,
    ) -> Result<StartPartyOutput, StartPartyError> {
        // Find party
        let mut party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(StartPartyError::PartyNotFound)?;

        // Check if user is owner
        if party.owner_id != input.user_id {
            return Err(StartPartyError::NotOwner);
        }

        // Check party status
        match party.status {
            PartyStatus::Waiting => {}
            PartyStatus::Playing => return Err(StartPartyError::PartyPlaying),
            PartyStatus::Finished => return Err(StartPartyError::PartyFinished),
        }

        // Get players
        let mut players = self.party_repo.get_party_players(&input.party_id).await?;

        // Check minimum players
        if !party.can_start(players.len()) {
            return Err(StartPartyError::NotEnoughPlayers);
        }

        // The game state indexes seats 0..n-1: close the gaps a leave left. In seat
        // order, each player moves down to a seat the ones before it have just vacated.
        players.sort_by_key(|p| p.player_index);
        for (seat, player) in players.iter().enumerate() {
            if player.player_index != seat as u8 {
                self.party_repo
                    .set_player_index(&input.party_id, &player.user_id, seat as u8)
                    .await?;
            }
        }

        // Create first round
        let round_id = Uuid::new_v4().to_string();
        let round = Round::new(round_id.clone(), input.party_id.clone(), 1, 0);

        // Initialize game state
        let scores = [0u16; 8];
        let game_state = initialize_round(
            players.len() as u8,
            party.settings.hand_size,
            &scores,
            0, // No eliminated players yet
            1, // Round 1
            0, // Player 0 starts
            None,
        );

        // Save round
        self.party_repo.save_round(&round).await?;

        // Save game state
        self.party_repo
            .save_game_state(&input.party_id, &game_state)
            .await?;

        // Update party status
        party.start();
        party.current_round_id = Some(round_id);
        self.party_repo.save(&party).await?;

        Ok(StartPartyOutput { party, round })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum StartPartyError {
    #[error("Party not found")]
    PartyNotFound,
    #[error("Not the party owner")]
    NotOwner,
    #[error("Party is already playing")]
    PartyPlaying,
    #[error("Party has finished")]
    PartyFinished,
    #[error("Not enough players (minimum 3)")]
    NotEnoughPlayers,
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
