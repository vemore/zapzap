use std::sync::Arc;

use super::seat::{seat_player, Seating};
use crate::domain::entities::{Party, PartyStatus, PartyVisibility};
use crate::domain::repositories::{PartyRepository, RepositoryError, UserRepository};

/// Join party input
pub struct JoinPartyInput {
    pub user_id: String,
    pub party_id: String,
    pub invite_code: Option<String>,
}

/// Join party output
pub struct JoinPartyOutput {
    pub party: Party,
    pub player_index: u8,
}

/// Join party use case
pub struct JoinParty<U: UserRepository, P: PartyRepository> {
    user_repo: Arc<U>,
    party_repo: Arc<P>,
}

impl<U: UserRepository, P: PartyRepository> JoinParty<U, P> {
    pub fn new(user_repo: Arc<U>, party_repo: Arc<P>) -> Self {
        Self {
            user_repo,
            party_repo,
        }
    }

    pub async fn execute(&self, input: JoinPartyInput) -> Result<JoinPartyOutput, JoinPartyError> {
        // Validate user exists
        let user = self
            .user_repo
            .find_by_id(&input.user_id)
            .await?
            .ok_or(JoinPartyError::UserNotFound)?;

        if user.is_bot() {
            return Err(JoinPartyError::Validation(
                "Bots cannot join parties directly".into(),
            ));
        }

        // Find party
        let party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(JoinPartyError::PartyNotFound)?;

        // A private party is joined with its invite code only (Node: JoinParty.js)
        if party.visibility == PartyVisibility::Private {
            match input.invite_code.as_deref() {
                Some(code) if code == party.invite_code => {}
                Some(_) => return Err(JoinPartyError::InvalidInviteCode),
                None => return Err(JoinPartyError::PrivateParty),
            }
        }

        // Check party status. Node checks a full party first (JoinParty.js), so a full
        // started party answers PARTY_FULL; Node lets anyone join a started party with
        // a free seat, which Rust refuses.
        if party.status != PartyStatus::Waiting {
            let players = self.party_repo.get_party_players(&party.id).await?;
            if party.is_full(players.len()) {
                return Err(JoinPartyError::PartyFull);
            }
            return Err(JoinPartyError::PartyNotWaiting);
        }

        // Check if already in party
        if self
            .party_repo
            .is_player_in_party(&input.party_id, &input.user_id)
            .await?
        {
            return Err(JoinPartyError::AlreadyInParty);
        }

        let player_index = match seat_player(&*self.party_repo, &party, &input.user_id).await? {
            Seating::Seated(seat) => seat,
            Seating::Full => return Err(JoinPartyError::PartyFull),
            Seating::AlreadyIn => return Err(JoinPartyError::AlreadyInParty),
        };

        Ok(JoinPartyOutput {
            party,
            player_index,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum JoinPartyError {
    #[error("Validation error: {0}")]
    Validation(String),
    #[error("User not found")]
    UserNotFound,
    #[error("Party not found")]
    PartyNotFound,
    #[error("Party is private. Use invite code to join.")]
    PrivateParty,
    #[error("Invalid invite code")]
    InvalidInviteCode,
    #[error("Party is not in waiting state")]
    PartyNotWaiting,
    #[error("Already in party")]
    AlreadyInParty,
    #[error("Party is full")]
    PartyFull,
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
