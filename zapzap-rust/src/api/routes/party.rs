use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    Extension,
};
use serde::{Deserialize, Serialize};

use crate::api::error::{ApiBody, ApiError, ApiJson};
use crate::api::middleware::Claims;
use crate::api::AppState;
use crate::application::party::{
    AddBotToParty, AddBotToPartyInput, CreateParty, CreatePartyInput, DeleteParty,
    DeletePartyInput, GetPartyDetails, GetPartyDetailsInput, JoinParty, JoinPartyInput, LeaveParty,
    LeavePartyInput, ListPartiesInput, ListPublicParties, StartParty, StartPartyInput,
};
use crate::domain::entities::PartyVisibility;
use crate::domain::value_objects::{player_count_message, PartySettings};
use crate::infrastructure::app_state::GameEvent;

// ============================================================================
// Request/Response DTOs
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct CreatePartyRequest {
    pub name: Option<String>, // missing: 400 MISSING_PARTY_NAME as in Node, not axum's 422
    pub visibility: Option<String>,
    pub settings: Option<PartySettingsDto>,
    #[serde(rename = "botIds")]
    pub bot_ids: Option<Vec<String>>,
}

impl ApiBody for CreatePartyRequest {
    const INVALID_CODE: &'static str = "VALIDATION_ERROR";
    const INVALID_MESSAGE: &'static str = "Invalid party data";
}

#[derive(Debug, Deserialize)]
pub struct AddBotRequest {
    #[serde(rename = "botId")]
    pub bot_id: Option<String>,
}

impl ApiBody for AddBotRequest {
    const INVALID_CODE: &'static str = "MISSING_BOT_ID";
    const INVALID_MESSAGE: &'static str = "Bot ID is required";
}

/// Node's settings keys; other keys are ignored. `playerCount` is required when
/// `settings` is sent, as Node's `PartySettings` requires it.
#[derive(Debug, Deserialize)]
pub struct PartySettingsDto {
    /// Any number, so that 300 or 3.5 get the 3-8 message rather than "Invalid party data"
    #[serde(rename = "playerCount")]
    pub player_count: Option<f64>,
    #[serde(rename = "allowSpectators")]
    pub allow_spectators: Option<bool>,
    #[serde(rename = "roundTimeLimit")]
    pub round_time_limit: Option<u32>,
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
    pub settings: PartySettings,
    /// Unix seconds, as Node
    #[serde(rename = "createdAt")]
    pub created_at: i64,
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
    pub status: String,
    #[serde(rename = "playerCount")]
    pub player_count: usize,
    #[serde(rename = "maxPlayers")]
    pub max_players: u8,
    #[serde(rename = "isMember")]
    pub is_member: bool,
    /// The caller is a member of this playing party and the current turn is theirs
    #[serde(rename = "isMyTurn")]
    pub is_my_turn: bool,
    #[serde(rename = "createdAt")]
    pub created_at: i64,
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
    /// The `party_players` row id, an integer as on Node
    pub id: i64,
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
    pub joined_at: i64,
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
    pub settings: PartySettings,
    #[serde(rename = "currentRoundId")]
    pub current_round_id: Option<String>,
    #[serde(rename = "createdAt")]
    pub created_at: i64,
    #[serde(rename = "updatedAt")]
    pub updated_at: i64,
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
pub struct AddBotResponse {
    pub success: bool,
    pub party: JoinPartyInfo,
    pub bot: AddedBotInfo,
    #[serde(rename = "playerIndex")]
    pub player_index: u8,
}

#[derive(Debug, Serialize)]
pub struct AddedBotInfo {
    pub id: String,
    pub username: String,
    #[serde(rename = "botDifficulty")]
    pub bot_difficulty: Option<String>,
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

// ============================================================================
// Route Handlers
// ============================================================================

/// POST /api/party - Create a new party
pub async fn create_party(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    ApiJson(body): ApiJson<CreatePartyRequest>,
) -> Result<(StatusCode, Json<CreatePartyResponse>), ApiError> {
    let name = body
        .name
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ApiError::bad_request("MISSING_PARTY_NAME", "Party name is required"))?;

    // No settings: Node's PartySettings.createDefault() (Node itself answers 500 here)
    let settings = match body.settings {
        None => PartySettings::default(),
        Some(s) => PartySettings {
            player_count: s
                .player_count
                .ok_or_else(player_count_message)
                .and_then(PartySettings::player_count_from)
                .map_err(|message| ApiError::bad_request("VALIDATION_ERROR", message))?,
            allow_spectators: s.allow_spectators.unwrap_or(false),
            round_time_limit: s.round_time_limit.unwrap_or(0),
        },
    };

    let use_case = CreateParty::new(state.user_repo.clone(), state.party_repo.clone());
    let result = use_case
        .execute(CreatePartyInput {
            owner_id: claims.user_id.clone(),
            name,
            visibility: body.visibility.unwrap_or_else(|| "public".to_string()),
            settings,
            bot_ids: body.bot_ids.unwrap_or_default(),
        })
        .await?;

    // Emit SSE event for partyCreated, so that live party lists show the new party.
    // A private party is not in GET /party: announcing it would only leak it.
    if result.party.visibility == PartyVisibility::Public {
        let event = GameEvent::new(
            "partyUpdate",
            Some(result.party.id.clone()),
            Some(claims.user_id.clone()),
        )
        .with_action("partyCreated")
        .with_data(serde_json::json!({
            "partyName": result.party.name
        }));
        state.broadcast_event(event);
    }

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
                settings: result.party.settings.clone(),
                created_at: result.party.created_at,
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
) -> Result<Json<ListPartiesResponse>, ApiError> {
    let use_case = ListPublicParties::new(state.party_repo.clone());
    let result = use_case
        .execute(ListPartiesInput {
            user_id: claims.map(|c| c.user_id.clone()),
            status: query.status,
            limit: query.limit.unwrap_or(50),
            offset: query.offset.unwrap_or(0),
        })
        .await?;

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
                status: p.status,
                player_count: p.player_count,
                max_players: p.max_players,
                is_member: p.is_member,
                is_my_turn: p.is_my_turn,
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
) -> Result<Json<PartyDetailsResponse>, ApiError> {
    let use_case = GetPartyDetails::new(state.user_repo.clone(), state.party_repo.clone());
    let result = use_case
        .execute(GetPartyDetailsInput {
            user_id: claims.user_id.clone(),
            party_id,
        })
        .await?;

    Ok(Json(PartyDetailsResponse {
        success: true,
        party: PartyDetailInfo {
            id: result.party.id.clone(),
            name: result.party.name.clone(),
            owner_id: result.party.owner_id.clone(),
            invite_code: result.party.invite_code.clone(),
            visibility: result.party.visibility.as_str().to_string(),
            status: result.party.status.as_str().to_string(),
            settings: result.party.settings.clone(),
            current_round_id: result.party.current_round_id.clone(),
            created_at: result.party.created_at,
            updated_at: result.party.updated_at,
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
) -> Result<Json<JoinPartyResponse>, ApiError> {
    let invite_code = body.and_then(|b| b.invite_code.clone());

    let use_case = JoinParty::new(state.user_repo.clone(), state.party_repo.clone());
    let result = use_case
        .execute(JoinPartyInput {
            user_id: claims.user_id.clone(),
            party_id: party_id.clone(),
            invite_code,
        })
        .await?;

    // Emit SSE event for playerJoined
    let event = GameEvent::new(
        "partyUpdate",
        Some(result.party.id.clone()),
        Some(claims.user_id.clone()),
    )
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
) -> Result<Json<LeavePartyResponse>, ApiError> {
    let party_id_for_event = party_id.clone();
    let use_case = LeaveParty::new(state.user_repo.clone(), state.party_repo.clone());
    let result = use_case
        .execute(LeavePartyInput {
            user_id: claims.user_id.clone(),
            party_id,
        })
        .await?;

    // Emit SSE event for playerLeft
    let event = GameEvent::new(
        "partyUpdate",
        Some(party_id_for_event),
        Some(claims.user_id.clone()),
    )
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
) -> Result<Json<StartPartyResponse>, ApiError> {
    let party_id_for_event = party_id.clone();
    let use_case = StartParty::new(state.party_repo.clone());
    let result = use_case
        .execute(StartPartyInput {
            user_id: claims.user_id.clone(),
            party_id,
        })
        .await?;

    // Emit SSE event for partyStarted
    let event = GameEvent::new(
        "partyUpdate",
        Some(party_id_for_event),
        Some(claims.user_id.clone()),
    )
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
) -> Result<Json<DeletePartyResponse>, ApiError> {
    let party_id_for_event = party_id.clone();
    let use_case = DeleteParty::new(state.user_repo.clone(), state.party_repo.clone());
    let result = use_case
        .execute(DeletePartyInput {
            user_id: claims.user_id.clone(),
            party_id,
        })
        .await?;

    // Emit SSE event for partyDeleted
    let event = GameEvent::new(
        "partyUpdate",
        Some(party_id_for_event),
        Some(claims.user_id.clone()),
    )
    .with_action("partyDeleted")
    .with_data(serde_json::json!({
        "partyName": result.deleted_party_name,
        "visibility": result.deleted_party_visibility
    }));
    state.broadcast_event(event);

    Ok(Json(DeletePartyResponse {
        success: true,
        message: "Party deleted successfully".to_string(),
        deleted_party_id: result.deleted_party_id,
        deleted_party_name: result.deleted_party_name,
    }))
}

/// POST /api/party/:partyId/bots - The owner adds a bot to a waiting party
pub async fn add_bot(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
    ApiJson(body): ApiJson<AddBotRequest>,
) -> Result<(StatusCode, Json<AddBotResponse>), ApiError> {
    let bot_id = body.bot_id.filter(|s| !s.is_empty()).ok_or_else(|| {
        ApiError::bad_request(AddBotRequest::INVALID_CODE, AddBotRequest::INVALID_MESSAGE)
    })?;

    let use_case = AddBotToParty::new(state.user_repo.clone(), state.party_repo.clone());
    let result = use_case
        .execute(AddBotToPartyInput {
            user_id: claims.user_id.clone(),
            party_id,
            bot_id,
        })
        .await?;

    // Same event as a human joining: the lobby and the party lists refresh on it
    let event = GameEvent::new(
        "partyUpdate",
        Some(result.party.id.clone()),
        Some(result.bot.id.clone()),
    )
    .with_action("playerJoined")
    .with_data(serde_json::json!({
        "username": result.bot.username,
        "playerIndex": result.player_index
    }));
    state.broadcast_event(event);

    Ok((
        StatusCode::CREATED,
        Json(AddBotResponse {
            success: true,
            party: JoinPartyInfo {
                id: result.party.id,
                name: result.party.name,
                status: result.party.status.as_str().to_string(),
            },
            bot: AddedBotInfo {
                id: result.bot.id,
                username: result.bot.username,
                bot_difficulty: result.bot.bot_difficulty.map(|d| d.as_str().to_string()),
            },
            player_index: result.player_index,
        }),
    ))
}
