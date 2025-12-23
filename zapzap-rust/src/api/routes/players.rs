use std::sync::Arc;

use axum::{extract::State, response::Json};
use serde::Serialize;

use crate::api::AppState;

// ============================================================================
// Response DTOs
// ============================================================================

#[derive(Debug, Serialize)]
pub struct ConnectedPlayer {
    #[serde(rename = "userId")]
    pub user_id: String,
    pub username: String,
    pub status: String,
    #[serde(rename = "partyId")]
    pub party_id: Option<String>,
    #[serde(rename = "connectedAt")]
    pub connected_at: i64,
}

#[derive(Debug, Serialize)]
pub struct ConnectedPlayersResponse {
    pub players: Vec<ConnectedPlayer>,
}

// ============================================================================
// Route Handlers
// ============================================================================

/// GET /api/players/connected - Get list of connected players
pub async fn get_connected_players(
    State(state): State<Arc<AppState>>,
) -> Json<ConnectedPlayersResponse> {
    let sessions = state.session_manager.get_connected_users(5);

    let players: Vec<ConnectedPlayer> = sessions
        .into_iter()
        .map(|session| ConnectedPlayer {
            user_id: session.user_id,
            username: session.username,
            status: session.status.as_str().to_string(),
            party_id: session.party_id,
            connected_at: session.connected_at,
        })
        .collect();

    Json(ConnectedPlayersResponse { players })
}
