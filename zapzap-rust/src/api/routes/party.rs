use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    Extension,
};
use serde::{Deserialize, Serialize};

use crate::api::middleware::Claims;
use crate::api::AppState;
use crate::infrastructure::app_state::GameEvent;
use crate::application::party::{
    CreateParty, CreatePartyInput, DeleteParty, DeletePartyInput, GetPartyDetails,
    GetPartyDetailsInput, JoinParty, JoinPartyInput, LeaveParty, LeavePartyInput,
    ListPartiesInput, ListPublicParties, StartParty, StartPartyInput,
};
use crate::domain::value_objects::PartySettings;

/// Convert timestamp to ISO 8601 string
fn timestamp_to_rfc3339(ts: i64) -> String {
    chrono::DateTime::from_timestamp(ts, 0)
        .map(|dt| dt.to_rfc3339())
        .unwrap_or_else(|| "1970-01-01T00:00:00Z".to_string())
}

// ============================================================================
// Request/Response DTOs
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct CreatePartyRequest {
    pub name: String,
    pub visibility: Option<String>,
    pub settings: Option<PartySettingsDto>,
    #[serde(rename = "botIds")]
    pub bot_ids: Option<Vec<String>>,
}

#[derive(Debug, Deserialize)]
pub struct PartySettingsDto {
    #[serde(rename = "handSize")]
    pub hand_size: Option<u8>,
    #[serde(rename = "maxScore")]
    pub max_score: Option<u16>,
    #[serde(rename = "enableGoldenScore")]
    pub enable_golden_score: Option<bool>,
    #[serde(rename = "goldenScoreThreshold")]
    pub golden_score_threshold: Option<u16>,
}

#[derive(Debug, Deserialize)]
pub struct ListPartiesQuery {
    pub status: Option<String>,
    pub limit: Option<i32>,
    pub offset: Option<i32>,
}

#[derive(Debug, Deserialize)]
pub struct JoinPartyRequest {
    #[serde(rename = "inviteCode")]
    pub invite_code: Option<String>,
}

// Response types
#[derive(Debug, Serialize)]
pub struct PartyResponse {
    pub id: String,
    pub name: String,
    #[serde(rename = "ownerId")]
    pub owner_id: String,
    #[serde(rename = "inviteCode")]
    pub invite_code: String,
    pub visibility: String,
    pub status: String,
    pub settings: PartySettingsResponse,
    #[serde(rename = "createdAt")]
    pub created_at: String,
}

#[derive(Debug, Serialize)]
pub struct PartySettingsResponse {
    #[serde(rename = "handSize")]
    pub hand_size: u8,
    #[serde(rename = "maxScore")]
    pub max_score: u16,
    #[serde(rename = "enableGoldenScore")]
    pub enable_golden_score: bool,
    #[serde(rename = "goldenScoreThreshold")]
    pub golden_score_threshold: u16,
}

#[derive(Debug, Serialize)]
pub struct CreatePartyResponse {
    pub success: bool,
    pub party: PartyResponse,
    #[serde(rename = "botsJoined")]
    pub bots_joined: usize,
}

#[derive(Debug, Serialize)]
pub struct PartyListItem {
    pub id: String,
    pub name: String,
    #[serde(rename = "ownerId")]
    pub owner_id: String,
    #[serde(rename = "inviteCode")]
    pub invite_code: String,
    pub visibility: String,
    pub status: String,
    #[serde(rename = "playerCount")]
    pub player_count: usize,
    #[serde(rename = "maxPlayers")]
    pub max_players: u8,
    #[serde(rename = "isMember")]
    pub is_member: bool,
    #[serde(rename = "createdAt")]
    pub created_at: String,
}

#[derive(Debug, Serialize)]
pub struct ListPartiesResponse {
    pub success: bool,
    pub parties: Vec<PartyListItem>,
    pub total: usize,
    pub limit: i32,
    pub offset: i32,
}

#[derive(Debug, Serialize)]
pub struct PlayerInfo {
    pub id: String,
    #[serde(rename = "userId")]
    pub user_id: String,
    pub username: String,
    #[serde(rename = "userType")]
    pub user_type: String,
    #[serde(rename = "botDifficulty")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bot_difficulty: Option<String>,
    #[serde(rename = "playerIndex")]
    pub player_index: u8,
    #[serde(rename = "joinedAt")]
    pub joined_at: String,
}

#[derive(Debug, Serialize)]
pub struct PartyDetailsResponse {
    pub success: bool,
    pub party: PartyDetailInfo,
    pub players: Vec<PlayerInfo>,
    #[serde(rename = "isOwner")]
    pub is_owner: bool,
    #[serde(rename = "userPlayerIndex")]
    pub user_player_index: Option<u8>,
}

#[derive(Debug, Serialize)]
pub struct PartyDetailInfo {
    pub id: String,
    pub name: String,
    #[serde(rename = "ownerId")]
    pub owner_id: String,
    #[serde(rename = "inviteCode")]
    pub invite_code: String,
    pub visibility: String,
    pub status: String,
    pub settings: PartySettingsResponse,
    #[serde(rename = "currentRoundId")]
    pub current_round_id: Option<String>,
    #[serde(rename = "createdAt")]
    pub created_at: String,
    #[serde(rename = "updatedAt")]
    pub updated_at: String,
}

#[derive(Debug, Serialize)]
pub struct JoinPartyResponse {
    pub success: bool,
    pub party: JoinPartyInfo,
    #[serde(rename = "playerIndex")]
    pub player_index: u8,
}

#[derive(Debug, Serialize)]
pub struct JoinPartyInfo {
    pub id: String,
    pub name: String,
    pub status: String,
}

#[derive(Debug, Serialize)]
pub struct LeavePartyResponse {
    pub success: bool,
    pub message: String,
    #[serde(rename = "newOwner")]
    pub new_owner: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct StartPartyResponse {
    pub success: bool,
    pub party: StartPartyInfo,
    pub round: RoundInfo,
}

#[derive(Debug, Serialize)]
pub struct StartPartyInfo {
    pub id: String,
    pub status: String,
    #[serde(rename = "currentRoundId")]
    pub current_round_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct RoundInfo {
    pub id: String,
    #[serde(rename = "roundNumber")]
    pub round_number: u32,
    pub status: String,
}

#[derive(Debug, Serialize)]
pub struct DeletePartyResponse {
    pub success: bool,
    pub message: String,
    #[serde(rename = "deletedPartyId")]
    pub deleted_party_id: String,
    #[serde(rename = "deletedPartyName")]
    pub deleted_party_name: String,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
    pub code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,
}

// ============================================================================
// Route Handlers
// ============================================================================

/// POST /api/party - Create a new party
pub async fn create_party(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Json(body): Json<CreatePartyRequest>,
) -> Result<(StatusCode, Json<CreatePartyResponse>), (StatusCode, Json<ErrorResponse>)> {
    if body.name.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Party name is required".to_string(),
                code: "MISSING_PARTY_NAME".to_string(),
                details: None,
            }),
        ));
    }

    let settings = body.settings.map(|s| PartySettings {
        hand_size: s.hand_size.unwrap_or(5),
        max_score: s.max_score.unwrap_or(100),
        enable_golden_score: s.enable_golden_score.unwrap_or(true),
        golden_score_threshold: s.golden_score_threshold.unwrap_or(100),
    }).unwrap_or_default();

    let use_case = CreateParty::new(state.user_repo.clone(), state.party_repo.clone());
    let result = use_case
        .execute(CreatePartyInput {
            owner_id: claims.user_id.clone(),
            name: body.name,
            visibility: body.visibility.unwrap_or_else(|| "public".to_string()),
            settings,
            bot_ids: body.bot_ids.unwrap_or_default(),
        })
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: "Failed to create party".to_string(),
                    code: "CREATE_PARTY_ERROR".to_string(),
                    details: Some(e.to_string()),
                }),
            )
        })?;

    Ok((
        StatusCode::CREATED,
        Json(CreatePartyResponse {
            success: true,
            party: PartyResponse {
                id: result.party.id.clone(),
                name: result.party.name.clone(),
                owner_id: result.party.owner_id.clone(),
                invite_code: result.party.invite_code.clone(),
                visibility: result.party.visibility.as_str().to_string(),
                status: result.party.status.as_str().to_string(),
                settings: PartySettingsResponse {
                    hand_size: result.party.settings.hand_size,
                    max_score: result.party.settings.max_score,
                    enable_golden_score: result.party.settings.enable_golden_score,
                    golden_score_threshold: result.party.settings.golden_score_threshold,
                },
                created_at: timestamp_to_rfc3339(result.party.created_at),
            },
            bots_joined: result.bots_joined,
        }),
    ))
}

/// GET /api/party - List public parties
pub async fn list_parties(
    State(state): State<Arc<AppState>>,
    claims: Option<Extension<Claims>>,
    Query(query): Query<ListPartiesQuery>,
) -> Result<Json<ListPartiesResponse>, (StatusCode, Json<ErrorResponse>)> {
    let use_case = ListPublicParties::new(state.party_repo.clone());
    let result = use_case
        .execute(ListPartiesInput {
            user_id: claims.map(|c| c.user_id.clone()),
            status: query.status,
            limit: query.limit.unwrap_or(50),
            offset: query.offset.unwrap_or(0),
        })
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: "Failed to get parties".to_string(),
                    code: "GET_PARTIES_ERROR".to_string(),
                    details: Some(e.to_string()),
                }),
            )
        })?;

    Ok(Json(ListPartiesResponse {
        success: true,
        parties: result
            .parties
            .into_iter()
            .map(|p| PartyListItem {
                id: p.id,
                name: p.name,
                owner_id: p.owner_id,
                invite_code: p.invite_code,
                visibility: p.visibility,
                status: p.status,
                player_count: p.player_count,
                max_players: p.max_players,
                is_member: p.is_member,
                created_at: p.created_at,
            })
            .collect(),
        total: result.total,
        limit: result.limit,
        offset: result.offset,
    }))
}

/// GET /api/party/:partyId - Get party details
pub async fn get_party_details(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
) -> Result<Json<PartyDetailsResponse>, (StatusCode, Json<ErrorResponse>)> {
    let use_case = GetPartyDetails::new(state.user_repo.clone(), state.party_repo.clone());
    let result = use_case
        .execute(GetPartyDetailsInput {
            user_id: claims.user_id.clone(),
            party_id,
        })
        .await
        .map_err(|e| {
            let (status, code) = match e.to_string().as_str() {
                "Party not found" => (StatusCode::NOT_FOUND, "PARTY_NOT_FOUND"),
                "User is not in this party" => (StatusCode::FORBIDDEN, "NOT_IN_PARTY"),
                _ => (StatusCode::INTERNAL_SERVER_ERROR, "GET_PARTY_ERROR"),
            };
            (
                status,
                Json(ErrorResponse {
                    error: e.to_string(),
                    code: code.to_string(),
                    details: None,
                }),
            )
        })?;

    Ok(Json(PartyDetailsResponse {
        success: true,
        party: PartyDetailInfo {
            id: result.party.id.clone(),
            name: result.party.name.clone(),
            owner_id: result.party.owner_id.clone(),
            invite_code: result.party.invite_code.clone(),
            visibility: result.party.visibility.as_str().to_string(),
            status: result.party.status.as_str().to_string(),
            settings: PartySettingsResponse {
                hand_size: result.party.settings.hand_size,
                max_score: result.party.settings.max_score,
                enable_golden_score: result.party.settings.enable_golden_score,
                golden_score_threshold: result.party.settings.golden_score_threshold,
            },
            current_round_id: result.party.current_round_id.clone(),
            created_at: timestamp_to_rfc3339(result.party.created_at),
            updated_at: timestamp_to_rfc3339(result.party.updated_at),
        },
        players: result
            .players
            .into_iter()
            .map(|p| PlayerInfo {
                id: p.id,
                user_id: p.user_id,
                username: p.username,
                user_type: p.user_type,
                bot_difficulty: p.bot_difficulty,
                player_index: p.player_index,
                joined_at: p.joined_at,
            })
            .collect(),
        is_owner: result.is_owner,
        user_player_index: result.user_player_index,
    }))
}

/// POST /api/party/:partyId/join - Join a party
pub async fn join_party(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
    body: Option<Json<JoinPartyRequest>>,
) -> Result<Json<JoinPartyResponse>, (StatusCode, Json<ErrorResponse>)> {
    let invite_code = body.and_then(|b| b.invite_code.clone());

    let use_case = JoinParty::new(state.user_repo.clone(), state.party_repo.clone());
    let result = use_case
        .execute(JoinPartyInput {
            user_id: claims.user_id.clone(),
            party_id: party_id.clone(),
            invite_code,
        })
        .await
        .map_err(|e| {
            let err_msg = e.to_string();
            let (status, code) = if err_msg.contains("not found") || err_msg.contains("does not exist") {
                (StatusCode::NOT_FOUND, "PARTY_NOT_FOUND")
            } else if err_msg.contains("full") {
                (StatusCode::CONFLICT, "PARTY_FULL")
            } else if err_msg.contains("already in party") {
                (StatusCode::CONFLICT, "ALREADY_IN_PARTY")
            } else if err_msg.contains("already started") {
                (StatusCode::CONFLICT, "PARTY_STARTED")
            } else {
                (StatusCode::INTERNAL_SERVER_ERROR, "JOIN_PARTY_ERROR")
            };
            (
                status,
                Json(ErrorResponse {
                    error: err_msg,
                    code: code.to_string(),
                    details: None,
                }),
            )
        })?;

    // Emit SSE event for playerJoined
    let event = GameEvent::new("partyUpdate", Some(result.party.id.clone()), Some(claims.user_id.clone()))
        .with_action("playerJoined")
        .with_data(serde_json::json!({
            "username": claims.username,
            "playerIndex": result.player_index
        }));
    state.broadcast_event(event);

    Ok(Json(JoinPartyResponse {
        success: true,
        party: JoinPartyInfo {
            id: result.party.id,
            name: result.party.name,
            status: result.party.status.as_str().to_string(),
        },
        player_index: result.player_index,
    }))
}

/// POST /api/party/:partyId/leave - Leave a party
pub async fn leave_party(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
) -> Result<Json<LeavePartyResponse>, (StatusCode, Json<ErrorResponse>)> {
    let party_id_for_event = party_id.clone();
    let use_case = LeaveParty::new(state.user_repo.clone(), state.party_repo.clone());
    let result = use_case
        .execute(LeavePartyInput {
            user_id: claims.user_id.clone(),
            party_id,
        })
        .await
        .map_err(|e| {
            let err_msg = e.to_string();
            let (status, code) = match err_msg.as_str() {
                "Party not found" => (StatusCode::NOT_FOUND, "PARTY_NOT_FOUND"),
                "User is not in this party" => (StatusCode::FORBIDDEN, "NOT_IN_PARTY"),
                _ => (StatusCode::INTERNAL_SERVER_ERROR, "LEAVE_PARTY_ERROR"),
            };
            (
                status,
                Json(ErrorResponse {
                    error: err_msg,
                    code: code.to_string(),
                    details: None,
                }),
            )
        })?;

    // Emit SSE event for playerLeft
    let event = GameEvent::new("partyUpdate", Some(party_id_for_event), Some(claims.user_id.clone()))
        .with_action("playerLeft")
        .with_data(serde_json::json!({
            "username": claims.username,
            "newOwner": result.new_owner_id
        }));
    state.broadcast_event(event);

    Ok(Json(LeavePartyResponse {
        success: true,
        message: "Left party successfully".to_string(),
        new_owner: result.new_owner_id,
    }))
}

/// POST /api/party/:partyId/start - Start a party
pub async fn start_party(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
) -> Result<Json<StartPartyResponse>, (StatusCode, Json<ErrorResponse>)> {
    let party_id_for_event = party_id.clone();
    let use_case = StartParty::new(state.party_repo.clone());
    let result = use_case
        .execute(StartPartyInput {
            user_id: claims.user_id.clone(),
            party_id,
        })
        .await
        .map_err(|e| {
            let err_msg = e.to_string();
            let (status, code) = if err_msg.contains("not found") {
                (StatusCode::NOT_FOUND, "PARTY_NOT_FOUND")
            } else if err_msg.contains("owner") {
                (StatusCode::FORBIDDEN, "NOT_OWNER")
            } else if err_msg.contains("already playing") {
                (StatusCode::CONFLICT, "PARTY_ALREADY_PLAYING")
            } else {
                (StatusCode::INTERNAL_SERVER_ERROR, "START_PARTY_ERROR")
            };
            (
                status,
                Json(ErrorResponse {
                    error: err_msg,
                    code: code.to_string(),
                    details: None,
                }),
            )
        })?;

    // Emit SSE event for partyStarted
    let event = GameEvent::new("partyUpdate", Some(party_id_for_event), Some(claims.user_id.clone()))
        .with_action("partyStarted")
        .with_data(serde_json::json!({
            "roundId": result.round.id,
            "roundNumber": result.round.round_number
        }));
    state.broadcast_event(event);

    Ok(Json(StartPartyResponse {
        success: true,
        party: StartPartyInfo {
            id: result.party.id,
            status: result.party.status.as_str().to_string(),
            current_round_id: result.party.current_round_id,
        },
        round: RoundInfo {
            id: result.round.id,
            round_number: result.round.round_number,
            status: result.round.status.as_str().to_string(),
        },
    }))
}

/// DELETE /api/party/:partyId - Delete a party
pub async fn delete_party(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
) -> Result<Json<DeletePartyResponse>, (StatusCode, Json<ErrorResponse>)> {
    let party_id_for_event = party_id.clone();
    let use_case = DeleteParty::new(state.user_repo.clone(), state.party_repo.clone());
    let result = use_case
        .execute(DeletePartyInput {
            user_id: claims.user_id.clone(),
            party_id,
        })
        .await
        .map_err(|e| {
            let err_msg = e.to_string();
            let (status, code) = if err_msg.contains("not found") {
                (StatusCode::NOT_FOUND, "PARTY_NOT_FOUND")
            } else if err_msg.contains("not in this party") {
                (StatusCode::FORBIDDEN, "NOT_IN_PARTY")
            } else if err_msg.contains("owner") || err_msg.contains("authorized") {
                (StatusCode::FORBIDDEN, "NOT_AUTHORIZED")
            } else if err_msg.contains("active game") {
                (StatusCode::CONFLICT, "PARTY_PLAYING")
            } else {
                (StatusCode::INTERNAL_SERVER_ERROR, "DELETE_PARTY_ERROR")
            };
            (
                status,
                Json(ErrorResponse {
                    error: err_msg,
                    code: code.to_string(),
                    details: None,
                }),
            )
        })?;

    // Emit SSE event for partyDeleted
    let event = GameEvent::new("partyUpdate", Some(party_id_for_event), Some(claims.user_id.clone()))
        .with_action("partyDeleted")
        .with_data(serde_json::json!({
            "partyName": result.deleted_party_name
        }));
    state.broadcast_event(event);

    Ok(Json(DeletePartyResponse {
        success: true,
        message: "Party deleted successfully".to_string(),
        deleted_party_id: result.deleted_party_id,
        deleted_party_name: result.deleted_party_name,
    }))
}
