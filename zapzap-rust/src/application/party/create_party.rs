use std::sync::Arc;

use uuid::Uuid;

use crate::domain::entities::{generate_invite_code, Party, PartyVisibility};
use crate::domain::repositories::{PartyRepository, RepositoryError, UserRepository};
use crate::domain::value_objects::PartySettings;

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
            return Err(CreatePartyError::Validation("Bots cannot create parties".into()));
        }

        // Validate name
        if input.name.trim().is_empty() {
            return Err(CreatePartyError::Validation("Party name is required".into()));
        }

        // Parse visibility
        let visibility = PartyVisibility::from_str(&input.visibility)
            .unwrap_or(PartyVisibility::Public);

        // Create party
        let party_id = Uuid::new_v4().to_string();
        let invite_code = generate_invite_code();

        let party = Party::new(
            party_id.clone(),
            input.name,
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

        // Add bots if specified
        for (index, bot_id) in input.bot_ids.iter().enumerate() {
            // Verify bot exists
            if let Some(bot) = self.user_repo.find_by_id(bot_id).await? {
                if bot.is_bot() {
                    self.party_repo
                        .add_party_player(&party_id, bot_id, (index + 1) as u8)
                        .await?;
                    bots_joined += 1;
                }
            }
        }

        Ok(CreatePartyOutput {
            party,
            bots_joined,
        })
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
