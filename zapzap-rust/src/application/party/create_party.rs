use std::sync::Arc;

use uuid::Uuid;

use crate::domain::entities::{generate_invite_code, Party, PartyVisibility};
use crate::domain::repositories::{PartyRepository, RepositoryError, UserRepository};
use crate::domain::value_objects::PartySettings;

/// Party name bounds once trimmed, in UTF-16 code units as JavaScript's `length`
/// (Node: CreateParty.js), so "🎲🎲" is 4 long
pub const MIN_NAME_LENGTH: usize = 3;
pub const MAX_NAME_LENGTH: usize = 50;

/// Create party input
pub struct CreatePartyInput {
    pub owner_id: String,
    pub name: String,
    pub visibility: String,
    pub settings: PartySettings,
    pub bot_ids: Vec<String>,
}

/// Create party output
pub struct CreatePartyOutput {
    pub party: Party,
    pub bots_joined: usize,
}

/// Create party use case
pub struct CreateParty<U: UserRepository, P: PartyRepository> {
    user_repo: Arc<U>,
    party_repo: Arc<P>,
}

impl<U: UserRepository, P: PartyRepository> CreateParty<U, P> {
    pub fn new(user_repo: Arc<U>, party_repo: Arc<P>) -> Self {
        Self {
            user_repo,
            party_repo,
        }
    }

    pub async fn execute(
        &self,
        input: CreatePartyInput,
    ) -> Result<CreatePartyOutput, CreatePartyError> {
        // Validate user exists
        let user = self
            .user_repo
            .find_by_id(&input.owner_id)
            .await?
            .ok_or(CreatePartyError::UserNotFound)?;

        if user.is_bot() {
            return Err(CreatePartyError::Validation(
                "Bots cannot create parties".into(),
            ));
        }

        // Validate name, trimmed, as Node's CreateParty.js
        let name = input.name.trim().to_string();
        let name_length = name.encode_utf16().count();
        if name_length < MIN_NAME_LENGTH {
            return Err(CreatePartyError::Validation(format!(
                "Party name must be at least {MIN_NAME_LENGTH} characters long"
            )));
        }
        if name_length > MAX_NAME_LENGTH {
            return Err(CreatePartyError::Validation(format!(
                "Party name must not exceed {MAX_NAME_LENGTH} characters"
            )));
        }

        input
            .settings
            .validate()
            .map_err(CreatePartyError::Validation)?;

        // Node: CreateParty.js
        let unique_bot_ids: std::collections::HashSet<&String> = input.bot_ids.iter().collect();
        if unique_bot_ids.len() != input.bot_ids.len() {
            return Err(CreatePartyError::Validation(
                "Duplicate bot IDs detected".into(),
            ));
        }

        // The owner and the bots must fit in the seats (Node: CreateParty.js)
        let total_players = input.bot_ids.len() + 1;
        if total_players > input.settings.player_count as usize {
            return Err(CreatePartyError::Validation(format!(
                "Total players ({total_players}) exceeds party player count ({})",
                input.settings.player_count
            )));
        }

        // Parse visibility
        let visibility =
            PartyVisibility::from_str(&input.visibility).unwrap_or(PartyVisibility::Public);

        // Create party
        let party_id = Uuid::new_v4().to_string();
        let invite_code = generate_invite_code();

        let party = Party::new(
            party_id.clone(),
            name,
            input.owner_id.clone(),
            invite_code,
            visibility,
            input.settings,
        );

        // Save party
        self.party_repo.save(&party).await?;

        // Add owner as first player
        self.party_repo
            .add_party_player(&party_id, &input.owner_id, 0)
            .await?;

        let mut bots_joined = 0;

        // Add bots if specified: contiguous seats after the owner, whatever ids are skipped
        for bot_id in &input.bot_ids {
            // Verify bot exists
            if let Some(bot) = self.user_repo.find_by_id(bot_id).await? {
                if bot.is_bot() {
                    self.party_repo
                        .add_party_player(&party_id, bot_id, (bots_joined + 1) as u8)
                        .await?;
                    bots_joined += 1;
                }
            }
        }

        Ok(CreatePartyOutput { party, bots_joined })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum CreatePartyError {
    #[error("Validation error: {0}")]
    Validation(String),
    #[error("User not found")]
    UserNotFound,
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
