//! Shared by the integration tests that need it (`mod common;`): a party repository that
//! runs another write in the middle of a use case, to put a race in a set order.

#![allow(dead_code)]

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use zapzap_backend::domain::entities::{Party, PartyPlayer, PartyStatus, Round};
use zapzap_backend::domain::repositories::{
    GameAction, GameWrite, PartyRepository, PartyWithPlayerCount, RepositoryError, SeatReplacement,
    VersionedGameState,
};
use zapzap_backend::domain::services::GameResults;
use zapzap_backend::domain::value_objects::GameState;
use zapzap_backend::infrastructure::database::repositories::SqlitePartyRepository;

/// Where in a use case `Interleaved` runs its step: right after the first call of
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum After {
    /// `find_by_id`: the use case has read the party (its status, its owner)
    PartyRead,
    /// `get_player_index`: a move has checked its seat
    SeatCheck,
    /// `get_versioned_game_state`: the use case has read the state it will write
    StateRead,
}

type Step = Pin<Box<dyn Future<Output = ()> + Send>>;

/// The party repository of the game, with one step (another request's write) run once,
/// right after the use case's first call of the method `after` names
pub struct Interleaved {
    inner: Arc<SqlitePartyRepository>,
    after: After,
    step: tokio::sync::Mutex<Option<Step>>,
}

impl Interleaved {
    pub fn new(
        inner: Arc<SqlitePartyRepository>,
        after: After,
        step: impl Future<Output = ()> + Send + 'static,
    ) -> Arc<Self> {
        Arc::new(Self {
            inner,
            after,
            step: tokio::sync::Mutex::new(Some(Box::pin(step))),
        })
    }

    async fn run_step(&self, at: After) {
        if at != self.after {
            return;
        }
        let step = self.step.lock().await.take();
        if let Some(step) = step {
            step.await;
        }
    }

    /// Whether the step ran
    pub async fn stepped(&self) -> bool {
        self.step.lock().await.is_none()
    }
}

#[async_trait::async_trait]
impl PartyRepository for Interleaved {
    async fn find_by_id(&self, id: &str) -> Result<Option<Party>, RepositoryError> {
        let party = self.inner.find_by_id(id).await;
        self.run_step(After::PartyRead).await;
        party
    }
    async fn find_by_invite_code(&self, code: &str) -> Result<Option<Party>, RepositoryError> {
        self.inner.find_by_invite_code(code).await
    }
    async fn find_public_parties(
        &self,
        status: Option<PartyStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Party>, RepositoryError> {
        self.inner.find_public_parties(status, limit, offset).await
    }
    async fn find_public_parties_with_counts(
        &self,
        status: Option<PartyStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<PartyWithPlayerCount>, RepositoryError> {
        self.inner
            .find_public_parties_with_counts(status, limit, offset)
            .await
    }
    async fn find_by_owner(
        &self,
        owner_id: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Party>, RepositoryError> {
        self.inner.find_by_owner(owner_id, limit, offset).await
    }
    async fn find_all_parties(
        &self,
        status: Option<PartyStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Party>, RepositoryError> {
        self.inner.find_all_parties(status, limit, offset).await
    }
    async fn save(&self, party: &Party) -> Result<(), RepositoryError> {
        self.inner.save(party).await
    }
    async fn delete(&self, id: &str) -> Result<(), RepositoryError> {
        self.inner.delete(id).await
    }
    async fn update_status(&self, id: &str, status: PartyStatus) -> Result<(), RepositoryError> {
        self.inner.update_status(id, status).await
    }
    async fn get_party_players(&self, party_id: &str) -> Result<Vec<PartyPlayer>, RepositoryError> {
        self.inner.get_party_players(party_id).await
    }
    async fn add_party_player(
        &self,
        party_id: &str,
        user_id: &str,
        player_index: u8,
    ) -> Result<(), RepositoryError> {
        self.inner
            .add_party_player(party_id, user_id, player_index)
            .await
    }
    async fn set_player_index(
        &self,
        party_id: &str,
        user_id: &str,
        player_index: u8,
    ) -> Result<(), RepositoryError> {
        self.inner
            .set_player_index(party_id, user_id, player_index)
            .await
    }
    async fn remove_party_player(
        &self,
        party_id: &str,
        user_id: &str,
    ) -> Result<(), RepositoryError> {
        self.inner.remove_party_player(party_id, user_id).await
    }
    async fn is_player_in_party(
        &self,
        party_id: &str,
        user_id: &str,
    ) -> Result<bool, RepositoryError> {
        self.inner.is_player_in_party(party_id, user_id).await
    }
    async fn get_player_index(
        &self,
        party_id: &str,
        user_id: &str,
    ) -> Result<Option<u8>, RepositoryError> {
        let seat = self.inner.get_player_index(party_id, user_id).await;
        self.run_step(After::SeatCheck).await;
        seat
    }
    async fn human_seats(&self, party_id: &str) -> Result<Vec<u8>, RepositoryError> {
        self.inner.human_seats(party_id).await
    }
    async fn replace_player(
        &self,
        replacement: &SeatReplacement<'_>,
    ) -> Result<(), RepositoryError> {
        self.inner.replace_player(replacement).await
    }
    async fn get_round_by_id(&self, id: &str) -> Result<Option<Round>, RepositoryError> {
        self.inner.get_round_by_id(id).await
    }
    async fn save_round(&self, round: &Round) -> Result<(), RepositoryError> {
        self.inner.save_round(round).await
    }
    async fn get_current_round(&self, party_id: &str) -> Result<Option<Round>, RepositoryError> {
        self.inner.get_current_round(party_id).await
    }
    async fn get_versioned_game_state(
        &self,
        party_id: &str,
    ) -> Result<Option<VersionedGameState>, RepositoryError> {
        let read = self.inner.get_versioned_game_state(party_id).await;
        self.run_step(After::StateRead).await;
        read
    }
    async fn save_game_state(
        &self,
        party_id: &str,
        state: &GameState,
    ) -> Result<(), RepositoryError> {
        self.inner.save_game_state(party_id, state).await
    }
    async fn update_game_state(
        &self,
        party_id: &str,
        state: &GameState,
        expected_version: i64,
    ) -> Result<(), RepositoryError> {
        self.inner
            .update_game_state(party_id, state, expected_version)
            .await
    }
    async fn write_game(
        &self,
        write: &GameWrite<'_>,
    ) -> Result<Option<GameResults>, RepositoryError> {
        self.inner.write_game(write).await
    }
    async fn parties_past_turn_deadline(&self, now: u64) -> Result<Vec<String>, RepositoryError> {
        self.inner.parties_past_turn_deadline(now).await
    }
    async fn save_game_action(&self, action: &GameAction) -> Result<(), RepositoryError> {
        self.inner.save_game_action(action).await
    }
    async fn get_game_actions(
        &self,
        party_id: &str,
        round_number: u32,
    ) -> Result<Vec<GameAction>, RepositoryError> {
        self.inner.get_game_actions(party_id, round_number).await
    }
}
