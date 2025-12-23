//! Admin routes - admin panel operations

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
use crate::domain::repositories::{PartyRepository, UserRepository};

// ============================================================================
// Request/Response DTOs
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct ListUsersQuery {
    #[serde(default = "default_limit")]
    pub limit: i32,
    #[serde(default)]
    pub offset: i32,
}

#[derive(Debug, Deserialize)]
pub struct ListPartiesQuery {
    pub status: Option<String>,
    #[serde(default = "default_limit")]
    pub limit: i32,
    #[serde(default)]
    pub offset: i32,
}

fn default_limit() -> i32 { 50 }

#[derive(Debug, Deserialize)]
pub struct SetAdminRequest {
    #[serde(rename = "isAdmin")]
    pub is_admin: bool,
}

// Users list response with pagination (matching JS format)
#[derive(Debug, Serialize)]
pub struct UsersListResponse {
    pub success: bool,
    pub users: Vec<UserInfo>,
    pub pagination: Pagination,
}

#[derive(Debug, Serialize)]
pub struct Pagination {
    pub total: i32,
    pub limit: i32,
    pub offset: i32,
}

#[derive(Debug, Serialize)]
pub struct UserInfo {
    pub id: String,
    pub username: String,
    #[serde(rename = "userType")]
    pub user_type: String,
    #[serde(rename = "isAdmin")]
    pub is_admin: bool,
    #[serde(rename = "lastLoginAt")]
    pub last_login_at: Option<i64>,
    #[serde(rename = "totalPlayTimeSeconds")]
    pub total_play_time_seconds: i32,
    #[serde(rename = "gamesPlayed")]
    pub games_played: i32,
    #[serde(rename = "createdAt")]
    pub created_at: i64,
    #[serde(rename = "updatedAt")]
    pub updated_at: i64,
}

// Parties list response with pagination
#[derive(Debug, Serialize)]
pub struct PartiesListResponse {
    pub success: bool,
    pub parties: Vec<PartyInfo>,
    pub pagination: Pagination,
}

#[derive(Debug, Serialize)]
pub struct PartyInfo {
    pub id: String,
    pub name: String,
    pub status: String,
    #[serde(rename = "playerCount")]
    pub player_count: i32,
    #[serde(rename = "createdAt")]
    pub created_at: i64,
    #[serde(rename = "ownerUsername")]
    pub owner_username: String,
}

// Statistics response (matching JS format)
#[derive(Debug, Serialize)]
pub struct StatisticsResponse {
    pub success: bool,
    pub stats: AdminStats,
}

#[derive(Debug, Serialize)]
pub struct AdminStats {
    pub users: UserStats,
    pub parties: PartyStats,
    pub rounds: RoundStats,
    #[serde(rename = "gamesOverTime")]
    pub games_over_time: GamesOverTime,
    #[serde(rename = "mostActiveUsers")]
    pub most_active_users: Vec<ActiveUser>,
}

#[derive(Debug, Serialize)]
pub struct UserStats {
    pub total: i32,
}

#[derive(Debug, Serialize)]
pub struct PartyStats {
    pub total: i32,
    pub waiting: i32,
    pub playing: i32,
    pub finished: i32,
    #[serde(rename = "completionRate")]
    pub completion_rate: f64,
}

#[derive(Debug, Serialize)]
pub struct RoundStats {
    pub total: i32,
}

#[derive(Debug, Serialize)]
pub struct GamesOverTime {
    pub daily: Vec<GamePeriod>,
    pub weekly: Vec<GamePeriod>,
    pub monthly: Vec<GamePeriod>,
}

#[derive(Debug, Serialize)]
pub struct GamePeriod {
    pub period: String,
    pub count: i32,
}

#[derive(Debug, Serialize)]
pub struct ActiveUser {
    #[serde(rename = "userId")]
    pub user_id: String,
    pub username: String,
    #[serde(rename = "gamesPlayed")]
    pub games_played: i32,
    pub wins: i32,
}

#[derive(Debug, Serialize)]
pub struct SuccessResponse {
    pub success: bool,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub success: bool,
    pub error: String,
}

// ============================================================================
// Route Handlers
// ============================================================================

/// GET /api/admin/users - List all human users with stats
pub async fn list_users(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Query(params): Query<ListUsersQuery>,
) -> Result<Json<UsersListResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Verify admin
    if !claims.is_admin {
        return Err((StatusCode::FORBIDDEN, Json(ErrorResponse { success: false, error: "Admin access required".to_string() })));
    }

    // Get users with stats
    let users = sqlx::query_as::<_, (String, String, String, bool, Option<i64>, i32, i32, i64, i64)>(
        r#"
        SELECT
            u.id,
            u.username,
            u.user_type,
            u.is_admin,
            u.last_login_at,
            COALESCE(u.total_play_time_seconds, 0) as total_play_time,
            COALESCE(pgr.games_played, 0) as games_played,
            u.created_at,
            u.updated_at
        FROM users u
        LEFT JOIN (
            SELECT user_id, COUNT(*) as games_played
            FROM player_game_results
            GROUP BY user_id
        ) pgr ON pgr.user_id = u.id
        WHERE u.user_type = 'human'
        ORDER BY u.created_at DESC
        LIMIT ? OFFSET ?
        "#
    )
    .bind(params.limit)
    .bind(params.offset)
    .fetch_all(state.party_repo.get_db())
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    let user_list: Vec<UserInfo> = users
        .into_iter()
        .map(|(id, username, user_type, is_admin, last_login_at, total_play_time, games_played, created_at, updated_at)| {
            UserInfo {
                id,
                username,
                user_type,
                is_admin,
                last_login_at,
                total_play_time_seconds: total_play_time,
                games_played,
                created_at,
                updated_at,
            }
        })
        .collect();

    // Get total count
    let total: i32 = sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE user_type = 'human'")
        .fetch_one(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    Ok(Json(UsersListResponse {
        success: true,
        users: user_list,
        pagination: Pagination {
            total,
            limit: params.limit,
            offset: params.offset,
        },
    }))
}

/// DELETE /api/admin/users/:userId - Delete a user
pub async fn delete_user(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(user_id): Path<String>,
) -> Result<Json<SuccessResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Verify admin
    if !claims.is_admin {
        return Err((StatusCode::FORBIDDEN, Json(ErrorResponse { success: false, error: "Admin access required".to_string() })));
    }

    // Cannot delete self
    if user_id == claims.user_id {
        return Err((StatusCode::BAD_REQUEST, Json(ErrorResponse { success: false, error: "Cannot delete yourself".to_string() })));
    }

    // Check user exists
    let user = state.user_repo.find_by_id(&user_id).await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?
        .ok_or_else(|| (StatusCode::NOT_FOUND, Json(ErrorResponse { success: false, error: "User not found".to_string() })))?;

    // Cannot delete admin
    if user.is_admin {
        return Err((StatusCode::BAD_REQUEST, Json(ErrorResponse { success: false, error: "Cannot delete an admin user".to_string() })));
    }

    // Delete user
    sqlx::query("DELETE FROM users WHERE id = ?")
        .bind(&user_id)
        .execute(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    Ok(Json(SuccessResponse { success: true }))
}

/// POST /api/admin/users/:userId/admin - Grant or revoke admin rights
pub async fn set_user_admin(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(user_id): Path<String>,
    Json(body): Json<SetAdminRequest>,
) -> Result<Json<SuccessResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Verify admin
    if !claims.is_admin {
        return Err((StatusCode::FORBIDDEN, Json(ErrorResponse { success: false, error: "Admin access required".to_string() })));
    }

    // Cannot modify self
    if user_id == claims.user_id {
        return Err((StatusCode::BAD_REQUEST, Json(ErrorResponse { success: false, error: "Cannot modify your own admin status".to_string() })));
    }

    // Check user exists
    state.user_repo.find_by_id(&user_id).await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?
        .ok_or_else(|| (StatusCode::NOT_FOUND, Json(ErrorResponse { success: false, error: "User not found".to_string() })))?;

    // Update admin status
    sqlx::query("UPDATE users SET is_admin = ? WHERE id = ?")
        .bind(body.is_admin)
        .bind(&user_id)
        .execute(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    Ok(Json(SuccessResponse { success: true }))
}

/// GET /api/admin/parties - List all parties
pub async fn list_parties(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Query(params): Query<ListPartiesQuery>,
) -> Result<Json<PartiesListResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Verify admin
    if !claims.is_admin {
        return Err((StatusCode::FORBIDDEN, Json(ErrorResponse { success: false, error: "Admin access required".to_string() })));
    }

    // Build query with optional status filter
    let (parties, total) = if let Some(status) = &params.status {
        let parties = sqlx::query_as::<_, (String, String, String, i32, i64, String)>(
            r#"
            SELECT
                p.id,
                p.name,
                p.status,
                (SELECT COUNT(*) FROM party_players WHERE party_id = p.id) as player_count,
                p.created_at,
                COALESCE(u.username, 'Unknown') as owner_username
            FROM parties p
            LEFT JOIN users u ON u.id = p.owner_id
            WHERE p.status = ?
            ORDER BY p.created_at DESC
            LIMIT ? OFFSET ?
            "#
        )
        .bind(status)
        .bind(params.limit)
        .bind(params.offset)
        .fetch_all(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

        let total: i32 = sqlx::query_scalar("SELECT COUNT(*) FROM parties WHERE status = ?")
            .bind(status)
            .fetch_one(state.party_repo.get_db())
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

        (parties, total)
    } else {
        let parties = sqlx::query_as::<_, (String, String, String, i32, i64, String)>(
            r#"
            SELECT
                p.id,
                p.name,
                p.status,
                (SELECT COUNT(*) FROM party_players WHERE party_id = p.id) as player_count,
                p.created_at,
                COALESCE(u.username, 'Unknown') as owner_username
            FROM parties p
            LEFT JOIN users u ON u.id = p.owner_id
            ORDER BY p.created_at DESC
            LIMIT ? OFFSET ?
            "#
        )
        .bind(params.limit)
        .bind(params.offset)
        .fetch_all(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

        let total: i32 = sqlx::query_scalar("SELECT COUNT(*) FROM parties")
            .fetch_one(state.party_repo.get_db())
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

        (parties, total)
    };

    let party_list: Vec<PartyInfo> = parties
        .into_iter()
        .map(|(id, name, status, player_count, created_at, owner_username)| {
            PartyInfo {
                id,
                name,
                status,
                player_count,
                created_at,
                owner_username,
            }
        })
        .collect();

    Ok(Json(PartiesListResponse {
        success: true,
        parties: party_list,
        pagination: Pagination {
            total,
            limit: params.limit,
            offset: params.offset,
        },
    }))
}

/// POST /api/admin/parties/:partyId/stop - Force stop a party
pub async fn stop_party(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
) -> Result<Json<SuccessResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Verify admin
    if !claims.is_admin {
        return Err((StatusCode::FORBIDDEN, Json(ErrorResponse { success: false, error: "Admin access required".to_string() })));
    }

    // Check party exists
    let party = state.party_repo.find_by_id(&party_id).await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?
        .ok_or_else(|| (StatusCode::NOT_FOUND, Json(ErrorResponse { success: false, error: "Party not found".to_string() })))?;

    if party.status.as_str() == "finished" {
        return Err((StatusCode::BAD_REQUEST, Json(ErrorResponse { success: false, error: "Party is already finished".to_string() })));
    }

    // Update party status to finished
    sqlx::query("UPDATE parties SET status = 'finished', updated_at = ? WHERE id = ?")
        .bind(chrono::Utc::now().timestamp())
        .bind(&party_id)
        .execute(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    Ok(Json(SuccessResponse { success: true }))
}

/// DELETE /api/admin/parties/:partyId - Delete a party
pub async fn admin_delete_party(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
) -> Result<Json<SuccessResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Verify admin
    if !claims.is_admin {
        return Err((StatusCode::FORBIDDEN, Json(ErrorResponse { success: false, error: "Admin access required".to_string() })));
    }

    // Check party exists
    state.party_repo.find_by_id(&party_id).await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?
        .ok_or_else(|| (StatusCode::NOT_FOUND, Json(ErrorResponse { success: false, error: "Party not found".to_string() })))?;

    // Delete party and related data
    sqlx::query("DELETE FROM party_players WHERE party_id = ?")
        .bind(&party_id)
        .execute(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    sqlx::query("DELETE FROM parties WHERE id = ?")
        .bind(&party_id)
        .execute(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    Ok(Json(SuccessResponse { success: true }))
}

/// GET /api/admin/statistics - Get platform statistics
pub async fn get_statistics(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
) -> Result<Json<StatisticsResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Verify admin
    if !claims.is_admin {
        return Err((StatusCode::FORBIDDEN, Json(ErrorResponse { success: false, error: "Admin access required".to_string() })));
    }

    // Get user count
    let total_users: i32 = sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE user_type = 'human'")
        .fetch_one(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    // Get party counts
    let total_parties: i32 = sqlx::query_scalar("SELECT COUNT(*) FROM parties")
        .fetch_one(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    let waiting_parties: i32 = sqlx::query_scalar("SELECT COUNT(*) FROM parties WHERE status = 'waiting'")
        .fetch_one(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    let playing_parties: i32 = sqlx::query_scalar("SELECT COUNT(*) FROM parties WHERE status = 'playing'")
        .fetch_one(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    let finished_parties: i32 = sqlx::query_scalar("SELECT COUNT(*) FROM parties WHERE status = 'finished'")
        .fetch_one(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    // Get total rounds
    let total_rounds: i32 = sqlx::query_scalar("SELECT COUNT(*) FROM rounds")
        .fetch_one(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    // Get most active users
    let active_users = sqlx::query_as::<_, (String, String, i32, i32)>(
        r#"
        SELECT
            u.id,
            u.username,
            COUNT(*) as games_played,
            SUM(CASE WHEN pgr.is_winner = 1 THEN 1 ELSE 0 END) as games_won
        FROM player_game_results pgr
        JOIN users u ON u.id = pgr.user_id
        WHERE u.user_type = 'human'
        GROUP BY u.id
        ORDER BY games_played DESC
        LIMIT 10
        "#
    )
    .fetch_all(state.party_repo.get_db())
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { success: false, error: e.to_string() })))?;

    let most_active_users: Vec<ActiveUser> = active_users
        .into_iter()
        .map(|(user_id, username, games_played, wins)| {
            ActiveUser {
                user_id,
                username,
                games_played,
                wins,
            }
        })
        .collect();

    let completion_rate = if total_parties > 0 {
        (finished_parties as f64 / total_parties as f64) * 100.0
    } else {
        0.0
    };

    Ok(Json(StatisticsResponse {
        success: true,
        stats: AdminStats {
            users: UserStats { total: total_users },
            parties: PartyStats {
                total: total_parties,
                waiting: waiting_parties,
                playing: playing_parties,
                finished: finished_parties,
                completion_rate,
            },
            rounds: RoundStats { total: total_rounds },
            games_over_time: GamesOverTime {
                daily: vec![],  // TODO: Implement if needed
                weekly: vec![],
                monthly: vec![],
            },
            most_active_users,
        },
    }))
}
