use async_trait::async_trait;

use crate::domain::entities::{Party, PartyPlayer, PartyStatus, Round};
use crate::domain::repositories::RepositoryError;
use crate::domain::value_objects::GameState;

/// Party with player count (optimized for listing)
#[derive(Debug, Clone)]
pub struct PartyWithPlayerCount {
    pub party: Party,
    pub player_count: usize,
    pub player_user_ids: Vec<String>,
}

/// Party repository trait
#[async_trait]
pub trait PartyRepository: Send + Sync {
    // ========== Party operations ==========

    /// Find party by ID
    async fn find_by_id(&self, id: &str) -> Result<Option<Party>, RepositoryError>;

    /// Find party by invite code
    async fn find_by_invite_code(&self, code: &str) -> Result<Option<Party>, RepositoryError>;

    /// Find public parties with pagination
    async fn find_public_parties(
        &self,
        status: Option<PartyStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Party>, RepositoryError>;

    /// Find public parties with player counts (optimized - single query)
    async fn find_public_parties_with_counts(
        &self,
        status: Option<PartyStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<PartyWithPlayerCount>, RepositoryError>;

    /// Find parties by owner
    async fn find_by_owner(
        &self,
        owner_id: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Party>, RepositoryError>;

    /// Find all parties (admin)
    async fn find_all_parties(
        &self,
        status: Option<PartyStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Party>, RepositoryError>;

    /// Save party (create or update)
    async fn save(&self, party: &Party) -> Result<(), RepositoryError>;

    /// Delete party
    async fn delete(&self, id: &str) -> Result<(), RepositoryError>;

    /// Update party status
    async fn update_status(&self, id: &str, status: PartyStatus) -> Result<(), RepositoryError>;

    // ========== Party player operations ==========

    /// Get party players
    async fn get_party_players(&self, party_id: &str) -> Result<Vec<PartyPlayer>, RepositoryError>;

    /// Add player to party
    async fn add_party_player(
        &self,
        party_id: &str,
        user_id: &str,
        player_index: u8,
    ) -> Result<(), RepositoryError>;

    /// Remove player from party
    async fn remove_party_player(
        &self,
        party_id: &str,
        user_id: &str,
    ) -> Result<(), RepositoryError>;

    /// Check if user is in party
    async fn is_player_in_party(
        &self,
        party_id: &str,
        user_id: &str,
    ) -> Result<bool, RepositoryError>;

    /// Get player index in party
    async fn get_player_index(
        &self,
        party_id: &str,
        user_id: &str,
    ) -> Result<Option<u8>, RepositoryError>;

    // ========== Round operations ==========

    /// Get round by ID
    async fn get_round_by_id(&self, id: &str) -> Result<Option<Round>, RepositoryError>;

    /// Save round (create or update)
    async fn save_round(&self, round: &Round) -> Result<(), RepositoryError>;

    /// Get current round for party
    async fn get_current_round(&self, party_id: &str) -> Result<Option<Round>, RepositoryError>;

    // ========== Game state operations ==========

    /// Get game state for party
    async fn get_game_state(&self, party_id: &str) -> Result<Option<GameState>, RepositoryError>;

    /// Save game state (as JSON)
    async fn save_game_state(
        &self,
        party_id: &str,
        state: &GameState,
    ) -> Result<(), RepositoryError>;

    // ========== Game action logging ==========

    /// Save game action
    async fn save_game_action(&self, action: &GameAction) -> Result<(), RepositoryError>;

    /// Get game actions for round
    async fn get_game_actions(
        &self,
        party_id: &str,
        round_number: u32,
    ) -> Result<Vec<GameAction>, RepositoryError>;

    // ========== Round scores ==========

    /// Save round scores when a round finishes
    async fn save_round_scores(
        &self,
        party_id: &str,
        round_number: u32,
        scores: Vec<RoundScoreEntry>,
    ) -> Result<(), RepositoryError>;

    /// Get elimination order for players (returns Vec of (user_id, elimination_round))
    /// First eliminated = lowest round number, never eliminated = None
    async fn get_elimination_order(
        &self,
        party_id: &str,
    ) -> Result<Vec<(String, Option<u32>)>, RepositoryError>;

    // ========== Game results ==========

    /// Save game results when game finishes
    async fn save_game_results(
        &self,
        party_id: &str,
        winner_user_id: &str,
        winner_score: u16,
        total_rounds: u32,
        was_golden_score: bool,
        player_results: Vec<PlayerGameResult>,
    ) -> Result<(), RepositoryError>;
}

/// Round score entry for saving
#[derive(Debug, Clone)]
pub struct RoundScoreEntry {
    pub user_id: String,
    pub player_index: u8,
    pub score_this_round: u16,
    pub total_score_after: u16,
    pub hand_points: u16,
    pub is_zapzap_caller: bool,
    pub zapzap_success: bool,
    pub was_counteracted: bool,
    pub hand_cards: Vec<u8>,
    pub is_lowest_hand: bool,
    pub is_eliminated: bool,
}

/// Player game result for saving
#[derive(Debug, Clone)]
pub struct PlayerGameResult {
    pub user_id: String,
    pub final_score: u16,
    pub finish_position: u8,
    pub rounds_played: u32,
    pub is_winner: bool,
}

/// Game action log entry
#[derive(Debug, Clone)]
pub struct GameAction {
    pub party_id: String,
    pub round_number: u32,
    pub turn_number: u32,
    pub player_index: u8,
    pub user_id: String,
    pub is_human: bool,
    pub action_type: String,
    pub action_data: String,
    pub hand_before: String,
    pub hand_value_before: u16,
    pub scores_before: String,
    pub opponent_hand_sizes: String,
    pub deck_size: u32,
    pub last_cards_played: String,
    pub hand_after: String,
    pub hand_value_after: Option<u16>,
    pub created_at: i64,
}
