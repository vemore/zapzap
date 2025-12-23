//! Stats routes - statistics and leaderboard endpoints

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
use crate::domain::repositories::UserRepository;

// ============================================================================
// Request/Response DTOs
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct LeaderboardQuery {
    #[serde(rename = "minGames", default = "default_min_games")]
    pub min_games: i32,
    #[serde(default = "default_limit")]
    pub limit: i32,
    #[serde(default)]
    pub offset: i32,
}

fn default_min_games() -> i32 { 5 }
fn default_limit() -> i32 { 50 }

// User Stats Response (matching JS format)
#[derive(Debug, Serialize)]
pub struct UserStatsResponse {
    pub success: bool,
    #[serde(rename = "userId")]
    pub user_id: String,
    pub username: String,
    pub stats: UserStatsDetail,
}

#[derive(Debug, Serialize)]
pub struct UserStatsDetail {
    #[serde(rename = "gamesPlayed")]
    pub games_played: i32,
    pub wins: i32,
    pub losses: i32,
    #[serde(rename = "winRate")]
    pub win_rate: f64,
    #[serde(rename = "averageScore")]
    pub average_score: f64,
    #[serde(rename = "bestScore")]
    pub best_score: i32,
    #[serde(rename = "totalRoundsPlayed")]
    pub total_rounds_played: i32,
    pub zapzaps: ZapZapStats,
    #[serde(rename = "lowestHandCount")]
    pub lowest_hand_count: i32,
}

#[derive(Debug, Serialize)]
pub struct ZapZapStats {
    pub total: i32,
    pub successful: i32,
    pub failed: i32,
    #[serde(rename = "successRate")]
    pub success_rate: f64,
}

#[derive(Debug, Serialize)]
pub struct LeaderboardResponse {
    pub success: bool,
    pub leaderboard: Vec<LeaderboardEntry>,
    pub total: i32,
}

#[derive(Debug, Serialize)]
pub struct LeaderboardEntry {
    pub rank: i32,
    #[serde(rename = "userId")]
    pub user_id: String,
    pub username: String,
    #[serde(rename = "gamesPlayed")]
    pub games_played: i32,
    pub wins: i32,
    #[serde(rename = "winRate")]
    pub win_rate: f64,
}

// Bot Stats Response (matching JS format)
#[derive(Debug, Serialize)]
pub struct BotStatsResponse {
    pub success: bool,
    pub totals: BotTotals,
    #[serde(rename = "byDifficulty")]
    pub by_difficulty: Vec<DifficultyStats>,
    #[serde(rename = "byBot")]
    pub by_bot: Vec<BotIndividualStats>,
}

#[derive(Debug, Serialize)]
pub struct BotTotals {
    #[serde(rename = "totalBots")]
    pub total_bots: i32,
    #[serde(rename = "totalGamesPlayed")]
    pub total_games_played: i32,
    #[serde(rename = "totalRoundsPlayed")]
    pub total_rounds_played: i32,
    #[serde(rename = "totalWins")]
    pub total_wins: i32,
    #[serde(rename = "totalZapzapCalls")]
    pub total_zapzap_calls: i32,
    #[serde(rename = "totalSuccessfulZapzaps")]
    pub total_successful_zapzaps: i32,
    #[serde(rename = "overallWinRate")]
    pub overall_win_rate: f64,
    #[serde(rename = "overallZapzapSuccessRate")]
    pub overall_zapzap_success_rate: f64,
}

#[derive(Debug, Serialize)]
pub struct DifficultyStats {
    pub difficulty: String,
    #[serde(rename = "botCount")]
    pub bot_count: i32,
    #[serde(rename = "gamesPlayed")]
    pub games_played: i32,
    #[serde(rename = "roundsPlayed")]
    pub rounds_played: i32,
    pub wins: i32,
    #[serde(rename = "winRate")]
    pub win_rate: f64,
    pub zapzaps: ZapZapStats,
    #[serde(rename = "lowestHandCount")]
    pub lowest_hand_count: i32,
    #[serde(rename = "roundWinRate")]
    pub round_win_rate: f64,
}

#[derive(Debug, Serialize)]
pub struct BotIndividualStats {
    #[serde(rename = "botId")]
    pub bot_id: String,
    pub username: String,
    pub difficulty: String,
    #[serde(rename = "gamesPlayed")]
    pub games_played: i32,
    #[serde(rename = "roundsPlayed")]
    pub rounds_played: i32,
    pub wins: i32,
    #[serde(rename = "winRate")]
    pub win_rate: f64,
    pub zapzaps: ZapZapStats,
    #[serde(rename = "lowestHandCount")]
    pub lowest_hand_count: i32,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
}

// ============================================================================
// Route Handlers
// ============================================================================

/// GET /api/stats/me - Get current user's personal statistics
pub async fn get_my_stats(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
) -> Result<Json<UserStatsResponse>, (StatusCode, Json<ErrorResponse>)> {
    get_user_stats_internal(state, &claims.user_id).await
}

/// GET /api/stats/user/:userId - Get statistics for a specific user
pub async fn get_user_stats(
    State(state): State<Arc<AppState>>,
    Path(user_id): Path<String>,
) -> Result<Json<UserStatsResponse>, (StatusCode, Json<ErrorResponse>)> {
    get_user_stats_internal(state, &user_id).await
}

async fn get_user_stats_internal(
    state: Arc<AppState>,
    user_id: &str,
) -> Result<Json<UserStatsResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Get user info
    let user = state.user_repo.find_by_id(user_id).await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { error: e.to_string() })))?
        .ok_or_else(|| (StatusCode::NOT_FOUND, Json(ErrorResponse { error: "User not found".to_string() })))?;

    // Query stats from database - calculate zapzap stats from round_scores
    let stats = sqlx::query_as::<_, (i32, i32, f64, i32, i32, i32, i32, i32)>(
        r#"
        SELECT
            COALESCE(COUNT(*), 0) as games_played,
            COALESCE(SUM(CASE WHEN is_winner = 1 THEN 1 ELSE 0 END), 0) as wins,
            COALESCE(CAST(AVG(final_score) AS REAL), 0.0) as avg_score,
            COALESCE(MIN(final_score), 0) as best_score,
            COALESCE(SUM(rounds_played), 0) as total_rounds,
            COALESCE((SELECT SUM(is_zapzap_caller) FROM round_scores WHERE user_id = pgr.user_id), 0) as total_zapzaps,
            COALESCE((SELECT SUM(zapzap_success) FROM round_scores WHERE user_id = pgr.user_id), 0) as successful_zapzaps,
            COALESCE((SELECT SUM(is_lowest_hand) FROM round_scores WHERE user_id = pgr.user_id), 0) as lowest_hand_count
        FROM player_game_results pgr
        WHERE user_id = ?
        "#
    )
    .bind(user_id)
    .fetch_optional(state.party_repo.get_db())
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { error: e.to_string() })))?
    .unwrap_or((0, 0, 0.0, 0, 0, 0, 0, 0));

    let (games_played, wins, avg_score, best_score, total_rounds, total_zapzaps, successful_zapzaps, lowest_hand_count) = stats;
    let failed_zapzaps = total_zapzaps - successful_zapzaps;
    let losses = games_played - wins;
    let win_rate = if games_played > 0 { wins as f64 / games_played as f64 } else { 0.0 };
    let zapzap_success_rate = if total_zapzaps > 0 { successful_zapzaps as f64 / total_zapzaps as f64 } else { 0.0 };

    Ok(Json(UserStatsResponse {
        success: true,
        user_id: user.id.clone(),
        username: user.username.clone(),
        stats: UserStatsDetail {
            games_played,
            wins,
            losses,
            win_rate,
            average_score: avg_score,
            best_score,
            total_rounds_played: total_rounds,
            zapzaps: ZapZapStats {
                total: total_zapzaps,
                successful: successful_zapzaps,
                failed: failed_zapzaps,
                success_rate: zapzap_success_rate,
            },
            lowest_hand_count,
        },
    }))
}

/// GET /api/stats/leaderboard - Get global leaderboard sorted by win rate
pub async fn get_leaderboard(
    State(state): State<Arc<AppState>>,
    Query(params): Query<LeaderboardQuery>,
) -> Result<Json<LeaderboardResponse>, (StatusCode, Json<ErrorResponse>)> {
    let entries = sqlx::query_as::<_, (String, String, i32, i32)>(
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
        HAVING games_played >= ?
        ORDER BY (CAST(games_won AS FLOAT) / games_played) DESC, games_played DESC
        LIMIT ? OFFSET ?
        "#
    )
    .bind(params.min_games)
    .bind(params.limit)
    .bind(params.offset)
    .fetch_all(state.party_repo.get_db())
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { error: e.to_string() })))?;

    let leaderboard: Vec<LeaderboardEntry> = entries
        .into_iter()
        .enumerate()
        .map(|(i, (user_id, username, games_played, wins))| {
            LeaderboardEntry {
                rank: (params.offset + i as i32 + 1),
                user_id,
                username,
                games_played,
                wins,
                win_rate: if games_played > 0 { wins as f64 / games_played as f64 } else { 0.0 },
            }
        })
        .collect();

    // Get total count - fixed query
    let total: i32 = sqlx::query_scalar(
        r#"
        SELECT COUNT(*) FROM (
            SELECT u.id
            FROM player_game_results pgr
            JOIN users u ON u.id = pgr.user_id
            WHERE u.user_type = 'human'
            GROUP BY u.id
            HAVING COUNT(*) >= ?
        )
        "#
    )
    .bind(params.min_games)
    .fetch_one(state.party_repo.get_db())
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { error: e.to_string() })))?;

    Ok(Json(LeaderboardResponse {
        success: true,
        leaderboard,
        total,
    }))
}

/// GET /api/stats/bots - Get statistics for all bots, grouped by difficulty
pub async fn get_bot_stats(
    State(state): State<Arc<AppState>>,
) -> Result<Json<BotStatsResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Get stats by difficulty - calculate zapzap from round_scores
    let difficulty_stats = sqlx::query_as::<_, (String, i32, i32, i32, i32, i32, i32, i32)>(
        r#"
        SELECT
            u.bot_difficulty,
            COUNT(DISTINCT u.id) as bot_count,
            COUNT(*) as games_played,
            COALESCE(SUM(pgr.rounds_played), 0) as total_rounds,
            SUM(CASE WHEN pgr.is_winner = 1 THEN 1 ELSE 0 END) as wins,
            COALESCE((SELECT SUM(rs.is_zapzap_caller) FROM round_scores rs JOIN users bu ON rs.user_id = bu.id WHERE bu.bot_difficulty = u.bot_difficulty), 0) as zapzap_total,
            COALESCE((SELECT SUM(rs.zapzap_success) FROM round_scores rs JOIN users bu ON rs.user_id = bu.id WHERE bu.bot_difficulty = u.bot_difficulty), 0) as zapzap_success,
            COALESCE((SELECT SUM(rs.is_lowest_hand) FROM round_scores rs JOIN users bu ON rs.user_id = bu.id WHERE bu.bot_difficulty = u.bot_difficulty), 0) as lowest_hand_count
        FROM player_game_results pgr
        JOIN users u ON u.id = pgr.user_id
        WHERE u.user_type = 'bot' AND u.bot_difficulty IS NOT NULL
        GROUP BY u.bot_difficulty
        ORDER BY (CAST(SUM(CASE WHEN pgr.is_winner = 1 THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*)) DESC
        "#
    )
    .fetch_all(state.party_repo.get_db())
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { error: e.to_string() })))?;

    // Get stats by individual bot - calculate zapzap from round_scores
    let bot_stats = sqlx::query_as::<_, (String, String, String, i32, i32, i32, i32, i32, i32)>(
        r#"
        SELECT
            u.id as bot_id,
            u.username,
            u.bot_difficulty,
            COUNT(*) as games_played,
            COALESCE(SUM(pgr.rounds_played), 0) as total_rounds,
            SUM(CASE WHEN pgr.is_winner = 1 THEN 1 ELSE 0 END) as wins,
            COALESCE((SELECT SUM(is_zapzap_caller) FROM round_scores WHERE user_id = u.id), 0) as zapzap_total,
            COALESCE((SELECT SUM(zapzap_success) FROM round_scores WHERE user_id = u.id), 0) as zapzap_success,
            COALESCE((SELECT SUM(is_lowest_hand) FROM round_scores WHERE user_id = u.id), 0) as lowest_hand_count
        FROM player_game_results pgr
        JOIN users u ON u.id = pgr.user_id
        WHERE u.user_type = 'bot' AND u.bot_difficulty IS NOT NULL
        GROUP BY u.id
        ORDER BY (CAST(SUM(CASE WHEN pgr.is_winner = 1 THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*)) DESC
        "#
    )
    .fetch_all(state.party_repo.get_db())
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { error: e.to_string() })))?;

    // Build byDifficulty array
    let by_difficulty: Vec<DifficultyStats> = difficulty_stats
        .into_iter()
        .map(|(difficulty, bot_count, games_played, total_rounds, wins, zapzap_total, zapzap_success, lowest_hand_count)| {
            let zapzap_failed = zapzap_total - zapzap_success;
            let win_rate = if games_played > 0 { wins as f64 / games_played as f64 } else { 0.0 };
            let zapzap_success_rate = if zapzap_total > 0 { zapzap_success as f64 / zapzap_total as f64 } else { 0.0 };
            let round_win_rate = if total_rounds > 0 { lowest_hand_count as f64 / total_rounds as f64 } else { 0.0 };

            DifficultyStats {
                difficulty,
                bot_count,
                games_played,
                rounds_played: total_rounds,
                wins,
                win_rate,
                zapzaps: ZapZapStats {
                    total: zapzap_total,
                    successful: zapzap_success,
                    failed: zapzap_failed,
                    success_rate: zapzap_success_rate,
                },
                lowest_hand_count,
                round_win_rate,
            }
        })
        .collect();

    // Build byBot array
    let by_bot: Vec<BotIndividualStats> = bot_stats
        .into_iter()
        .map(|(bot_id, username, difficulty, games_played, total_rounds, wins, zapzap_total, zapzap_success, lowest_hand_count)| {
            let zapzap_failed = zapzap_total - zapzap_success;
            let win_rate = if games_played > 0 { wins as f64 / games_played as f64 } else { 0.0 };
            let zapzap_success_rate = if zapzap_total > 0 { zapzap_success as f64 / zapzap_total as f64 } else { 0.0 };

            BotIndividualStats {
                bot_id,
                username,
                difficulty,
                games_played,
                rounds_played: total_rounds,
                wins,
                win_rate,
                zapzaps: ZapZapStats {
                    total: zapzap_total,
                    successful: zapzap_success,
                    failed: zapzap_failed,
                    success_rate: zapzap_success_rate,
                },
                lowest_hand_count,
            }
        })
        .collect();

    // Calculate totals
    let total_bots: i32 = by_difficulty.iter().map(|d| d.bot_count).sum();
    let total_games_played: i32 = by_difficulty.iter().map(|d| d.games_played).sum();
    let total_rounds_played: i32 = by_difficulty.iter().map(|d| d.rounds_played).sum();
    let total_wins: i32 = by_difficulty.iter().map(|d| d.wins).sum();
    let total_zapzap_calls: i32 = by_difficulty.iter().map(|d| d.zapzaps.total).sum();
    let total_successful_zapzaps: i32 = by_difficulty.iter().map(|d| d.zapzaps.successful).sum();

    let overall_win_rate = if total_games_played > 0 { total_wins as f64 / total_games_played as f64 } else { 0.0 };
    let overall_zapzap_success_rate = if total_zapzap_calls > 0 { total_successful_zapzaps as f64 / total_zapzap_calls as f64 } else { 0.0 };

    Ok(Json(BotStatsResponse {
        success: true,
        totals: BotTotals {
            total_bots,
            total_games_played,
            total_rounds_played,
            total_wins,
            total_zapzap_calls,
            total_successful_zapzaps,
            overall_win_rate,
            overall_zapzap_success_rate,
        },
        by_difficulty,
        by_bot,
    }))
}
