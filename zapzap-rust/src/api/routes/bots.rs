use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};

use crate::api::AppState;
use crate::application::bot::{BotAdminError, CreateBot, DeleteBot};
use crate::domain::entities::{BotDifficulty, User};
use crate::domain::repositories::UserRepository;

// ============================================================================
// Request/Response DTOs
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct ListBotsQuery {
    pub difficulty: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct BotInfo {
    pub id: String,
    pub username: String,
    #[serde(rename = "userType")]
    pub user_type: String,
    #[serde(rename = "botDifficulty")]
    pub bot_difficulty: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ListBotsResponse {
    pub success: bool,
    pub bots: Vec<BotInfo>,
    pub count: usize,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub success: bool,
    pub error: String,
}

// ============================================================================
// Route Handlers
// ============================================================================

/// GET /api/bots - List all bots
pub async fn list_bots(
    State(state): State<Arc<AppState>>,
    Query(query): Query<ListBotsQuery>,
) -> Result<Json<ListBotsResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Valid difficulties
    let valid_difficulties = [
        "easy",
        "medium",
        "hard",
        "hard_vince",
        "ml",
        "drl",
        "llm",
        "thibot",
    ];

    // Parse and validate difficulty if provided
    let difficulty = if let Some(ref diff) = query.difficulty {
        let diff_lower = diff.to_lowercase();
        if !valid_difficulties.contains(&diff_lower.as_str()) {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    success: false,
                    error: format!(
                        "Invalid difficulty filter. Must be one of: {}",
                        valid_difficulties.join(", ")
                    ),
                }),
            ));
        }
        BotDifficulty::from_str(&diff_lower)
    } else {
        None
    };

    // Get bots from repository
    let bots = state
        .user_repo
        .find_all_bots(difficulty)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    success: false,
                    error: e.to_string(),
                }),
            )
        })?;

    let bot_infos: Vec<BotInfo> = bots
        .into_iter()
        .map(|bot| BotInfo {
            id: bot.id.clone(),
            username: bot.username.clone(),
            user_type: bot.user_type.as_str().to_string(),
            bot_difficulty: bot.bot_difficulty.map(|d| d.as_str().to_string()),
        })
        .collect();

    let count = bot_infos.len();

    Ok(Json(ListBotsResponse {
        success: true,
        bots: bot_infos,
        count,
    }))
}

/// A bot as the Node backend's `User.toPublicObject()` showed it
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BotPublic {
    pub id: String,
    pub username: String,
    pub user_type: String,
    pub bot_difficulty: Option<String>,
    pub is_admin: bool,
    pub last_login_at: Option<i64>,
    pub total_play_time_seconds: i64,
    pub email: Option<String>,
    pub is_google_user: bool,
    pub created_at: i64,
    pub updated_at: i64,
}

impl From<User> for BotPublic {
    fn from(u: User) -> Self {
        Self {
            is_google_user: u.google_id.is_some(),
            user_type: u.user_type.as_str().to_string(),
            bot_difficulty: u.bot_difficulty.map(|d| d.as_str().to_string()),
            id: u.id,
            username: u.username,
            is_admin: u.is_admin,
            last_login_at: u.last_login_at,
            total_play_time_seconds: u.total_play_time_seconds,
            email: u.email,
            created_at: u.created_at,
            updated_at: u.updated_at,
        }
    }
}

#[derive(Debug, Serialize)]
pub struct CreateBotResponse {
    pub success: bool,
    pub bot: BotPublic,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteBotResponse {
    pub success: bool,
    pub deleted_bot_id: String,
}

fn bot_admin_error(e: BotAdminError) -> (StatusCode, Json<ErrorResponse>) {
    // Every failure of these routes is a 400, as the Node backend answered
    (
        StatusCode::BAD_REQUEST,
        Json(ErrorResponse {
            success: false,
            error: e.to_string(),
        }),
    )
}

/// POST /api/bots - create a bot (admin; mounted behind auth + admin middleware)
pub async fn create_bot(
    State(state): State<Arc<AppState>>,
    body: Option<Json<serde_json::Value>>,
) -> Result<(StatusCode, Json<CreateBotResponse>), (StatusCode, Json<ErrorResponse>)> {
    let field = |name: &str| {
        body.as_ref()
            .and_then(|Json(b)| b.get(name))
            .and_then(|v| v.as_str())
    };

    let bot = CreateBot::new(state.user_repo.clone())
        .execute(field("username"), field("difficulty"))
        .await
        .map_err(bot_admin_error)?;

    Ok((
        StatusCode::CREATED,
        Json(CreateBotResponse {
            success: true,
            bot: bot.into(),
        }),
    ))
}

/// DELETE /api/bots/:botId - delete a bot (admin; mounted behind auth + admin middleware)
pub async fn delete_bot(
    State(state): State<Arc<AppState>>,
    Path(bot_id): Path<String>,
) -> Result<Json<DeleteBotResponse>, (StatusCode, Json<ErrorResponse>)> {
    let deleted_bot_id = DeleteBot::new(state.user_repo.clone())
        .execute(&bot_id)
        .await
        .map_err(bot_admin_error)?;

    Ok(Json(DeleteBotResponse {
        success: true,
        deleted_bot_id,
    }))
}
