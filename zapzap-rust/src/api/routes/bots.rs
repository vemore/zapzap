use std::sync::Arc;

use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};

use crate::api::AppState;
use crate::domain::entities::BotDifficulty;
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
