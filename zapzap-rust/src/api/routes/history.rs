//! History routes - game history endpoints

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

// ============================================================================
// Request/Response DTOs
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct HistoryQuery {
    #[serde(default = "default_limit")]
    pub limit: i32,
    #[serde(default)]
    pub offset: i32,
}

fn default_limit() -> i32 { 20 }

#[derive(Debug, Serialize)]
pub struct HistoryResponse {
    pub success: bool,
    pub games: Vec<GameHistoryEntry>,
    pub total: i32,
}

#[derive(Debug, Serialize)]
pub struct GameHistoryEntry {
    #[serde(rename = "partyId")]
    pub party_id: String,
    #[serde(rename = "partyName")]
    pub party_name: String,
    #[serde(rename = "finishedAt")]
    pub finished_at: i64,
    #[serde(rename = "playerCount")]
    pub player_count: i32,
    #[serde(rename = "roundsPlayed")]
    pub rounds_played: i32,
    #[serde(rename = "winnerUsername")]
    pub winner_username: String,
    #[serde(rename = "userPlacement")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_placement: Option<i32>,
    #[serde(rename = "userScore")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_score: Option<i32>,
}

#[derive(Debug, Serialize)]
pub struct GameDetailsResponse {
    pub success: bool,
    pub game: GameDetailsInfo,
    pub players: Vec<GamePlayerResult>,
    pub rounds: Vec<RoundScoreInfo>,
}

#[derive(Debug, Serialize)]
pub struct RoundScoreInfo {
    #[serde(rename = "roundNumber")]
    pub round_number: i32,
    pub players: Vec<PlayerRoundScore>,
}

#[derive(Debug, Serialize)]
pub struct PlayerRoundScore {
    #[serde(rename = "userId")]
    pub user_id: String,
    pub username: String,
    #[serde(rename = "playerIndex")]
    pub player_index: i32,
    #[serde(rename = "scoreThisRound")]
    pub score_this_round: i32,
    #[serde(rename = "totalScoreAfter")]
    pub total_score_after: i32,
    #[serde(rename = "handPoints")]
    pub hand_points: i32,
    #[serde(rename = "isZapZapCaller")]
    pub is_zapzap_caller: bool,
    #[serde(rename = "zapZapSuccess")]
    pub zapzap_success: bool,
    #[serde(rename = "wasCounterActed")]
    pub was_counteracted: bool,
    #[serde(rename = "handCards")]
    pub hand_cards: Vec<u8>,
    #[serde(rename = "isLowestHand")]
    pub is_lowest_hand: bool,
    #[serde(rename = "isEliminated")]
    pub is_eliminated: bool,
}

#[derive(Debug, Serialize)]
pub struct GameDetailsInfo {
    #[serde(rename = "partyId")]
    pub party_id: String,
    #[serde(rename = "partyName")]
    pub party_name: String,
    pub visibility: String,
    pub status: String,
    pub winner: WinnerInfo,
    #[serde(rename = "totalRounds")]
    pub total_rounds: i32,
    #[serde(rename = "wasGoldenScore")]
    pub was_golden_score: bool,
    #[serde(rename = "playerCount")]
    pub player_count: i32,
    #[serde(rename = "finishedAt")]
    pub finished_at: i64,
}

#[derive(Debug, Serialize)]
pub struct WinnerInfo {
    #[serde(rename = "userId")]
    pub user_id: String,
    pub username: String,
    #[serde(rename = "finalScore")]
    pub final_score: i32,
}

#[derive(Debug, Serialize)]
pub struct GamePlayerResult {
    #[serde(rename = "userId")]
    pub user_id: String,
    pub username: String,
    #[serde(rename = "finalScore")]
    pub final_score: i32,
    #[serde(rename = "finishPosition")]
    pub finish_position: i32,
    #[serde(rename = "roundsPlayed")]
    pub rounds_played: i32,
    #[serde(rename = "totalZapZapCalls")]
    pub total_zapzap_calls: i32,
    #[serde(rename = "successfulZapZaps")]
    pub successful_zapzaps: i32,
    #[serde(rename = "failedZapZaps")]
    pub failed_zapzaps: i32,
    #[serde(rename = "lowestHandCount")]
    pub lowest_hand_count: i32,
    #[serde(rename = "isWinner")]
    pub is_winner: bool,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
}

// ============================================================================
// Route Handlers
// ============================================================================

/// GET /api/history - Get user's finished games history
pub async fn get_history(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Query(params): Query<HistoryQuery>,
) -> Result<Json<HistoryResponse>, (StatusCode, Json<ErrorResponse>)> {
    let games = sqlx::query_as::<_, (String, String, i64, i32, i32, String, Option<i32>, Option<i32>)>(
        r#"
        SELECT
            gr.party_id,
            p.name as party_name,
            gr.finished_at,
            gr.player_count,
            gr.total_rounds,
            wu.username as winner_username,
            pgr.finish_position as user_placement,
            pgr.final_score as user_score
        FROM game_results gr
        JOIN parties p ON p.id = gr.party_id
        JOIN users wu ON wu.id = gr.winner_user_id
        LEFT JOIN player_game_results pgr ON pgr.party_id = gr.party_id AND pgr.user_id = ?
        WHERE pgr.user_id = ?
        ORDER BY gr.finished_at DESC
        LIMIT ? OFFSET ?
        "#
    )
    .bind(&claims.user_id)
    .bind(&claims.user_id)
    .bind(params.limit)
    .bind(params.offset)
    .fetch_all(state.party_repo.get_db())
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { error: e.to_string() })))?;

    let history: Vec<GameHistoryEntry> = games
        .into_iter()
        .map(|(party_id, party_name, finished_at, player_count, rounds_played, winner_username, user_placement, user_score)| {
            GameHistoryEntry {
                party_id,
                party_name,
                finished_at,
                player_count,
                rounds_played,
                winner_username,
                user_placement,
                user_score,
            }
        })
        .collect();

    // Get total count
    let total: (i32,) = sqlx::query_as(
        r#"
        SELECT COUNT(*)
        FROM player_game_results pgr
        WHERE pgr.user_id = ?
        "#
    )
    .bind(&claims.user_id)
    .fetch_one(state.party_repo.get_db())
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { error: e.to_string() })))?;

    Ok(Json(HistoryResponse {
        success: true,
        games: history,
        total: total.0,
    }))
}

/// GET /api/history/public - Get public finished games history
pub async fn get_public_history(
    State(state): State<Arc<AppState>>,
    Query(params): Query<HistoryQuery>,
) -> Result<Json<HistoryResponse>, (StatusCode, Json<ErrorResponse>)> {
    let games = sqlx::query_as::<_, (String, String, i64, i32, i32, String)>(
        r#"
        SELECT
            gr.party_id,
            p.name as party_name,
            gr.finished_at,
            gr.player_count,
            gr.total_rounds,
            wu.username as winner_username
        FROM game_results gr
        JOIN parties p ON p.id = gr.party_id
        JOIN users wu ON wu.id = gr.winner_user_id
        ORDER BY gr.finished_at DESC
        LIMIT ? OFFSET ?
        "#
    )
    .bind(params.limit)
    .bind(params.offset)
    .fetch_all(state.party_repo.get_db())
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { error: e.to_string() })))?;

    let history: Vec<GameHistoryEntry> = games
        .into_iter()
        .map(|(party_id, party_name, finished_at, player_count, rounds_played, winner_username)| {
            GameHistoryEntry {
                party_id,
                party_name,
                finished_at,
                player_count,
                rounds_played,
                winner_username,
                user_placement: None,
                user_score: None,
            }
        })
        .collect();

    // Get total count
    let total: (i32,) = sqlx::query_as("SELECT COUNT(*) FROM game_results")
        .fetch_one(state.party_repo.get_db())
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { error: e.to_string() })))?;

    Ok(Json(HistoryResponse {
        success: true,
        games: history,
        total: total.0,
    }))
}

/// GET /api/history/:partyId - Get detailed information about a finished game
pub async fn get_game_details(
    State(state): State<Arc<AppState>>,
    Extension(_claims): Extension<Claims>,
    Path(party_id): Path<String>,
) -> Result<Json<GameDetailsResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Get game result with party info and winner info
    let game_result = sqlx::query_as::<_, (String, String, String, i64, i32, bool, i32, String, String, i32)>(
        r#"
        SELECT
            p.name as party_name,
            p.visibility,
            p.status,
            gr.finished_at,
            gr.total_rounds,
            gr.was_golden_score,
            gr.player_count,
            gr.winner_user_id,
            wu.username as winner_username,
            COALESCE(wpgr.final_score, 0) as winner_final_score
        FROM game_results gr
        JOIN parties p ON p.id = gr.party_id
        JOIN users wu ON wu.id = gr.winner_user_id
        LEFT JOIN player_game_results wpgr ON wpgr.party_id = gr.party_id AND wpgr.user_id = gr.winner_user_id
        WHERE gr.party_id = ?
        "#
    )
    .bind(&party_id)
    .fetch_optional(state.party_repo.get_db())
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { error: e.to_string() })))?
    .ok_or_else(|| (StatusCode::NOT_FOUND, Json(ErrorResponse { error: "Game not found".to_string() })))?;

    let (party_name, visibility, status, finished_at, total_rounds, was_golden_score, player_count, winner_user_id, winner_username, winner_final_score) = game_result;

    // Get player results with stats calculated from round_scores
    let player_results = sqlx::query_as::<_, (String, String, i32, i32, bool, i32, i32, i32)>(
        r#"
        SELECT
            pgr.user_id,
            u.username,
            pgr.final_score,
            pgr.finish_position,
            pgr.is_winner,
            COALESCE((SELECT SUM(is_zapzap_caller) FROM round_scores WHERE party_id = pgr.party_id AND user_id = pgr.user_id), 0) as total_zapzap_calls,
            COALESCE((SELECT SUM(zapzap_success) FROM round_scores WHERE party_id = pgr.party_id AND user_id = pgr.user_id), 0) as successful_zapzaps,
            COALESCE((SELECT SUM(is_lowest_hand) FROM round_scores WHERE party_id = pgr.party_id AND user_id = pgr.user_id), 0) as lowest_hand_count
        FROM player_game_results pgr
        JOIN users u ON u.id = pgr.user_id
        WHERE pgr.party_id = ?
        ORDER BY pgr.finish_position ASC
        "#
    )
    .bind(&party_id)
    .fetch_all(state.party_repo.get_db())
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { error: e.to_string() })))?;

    let players: Vec<GamePlayerResult> = player_results
        .into_iter()
        .map(|(user_id, username, final_score, finish_position, is_winner, total_zapzap_calls, successful_zapzaps, lowest_hand_count)| {
            let failed_zapzaps = total_zapzap_calls - successful_zapzaps;
            GamePlayerResult {
                user_id,
                username,
                final_score,
                finish_position,
                rounds_played: total_rounds,
                total_zapzap_calls,
                successful_zapzaps,
                failed_zapzaps,
                lowest_hand_count,
                is_winner,
            }
        })
        .collect();

    // Query round scores
    let round_scores_raw = sqlx::query_as::<_, (i32, String, String, i32, i32, i32, i32, bool, bool, bool, String, bool, bool)>(
        r#"
        SELECT
            rs.round_number,
            rs.user_id,
            u.username,
            rs.player_index,
            rs.score_this_round,
            rs.total_score_after,
            rs.hand_points,
            rs.is_zapzap_caller = 1 as is_zapzap_caller,
            rs.zapzap_success = 1 as zapzap_success,
            rs.was_counteracted = 1 as was_counteracted,
            COALESCE(rs.hand_cards, '[]') as hand_cards,
            rs.is_lowest_hand = 1 as is_lowest_hand,
            rs.is_eliminated = 1 as is_eliminated
        FROM round_scores rs
        JOIN users u ON u.id = rs.user_id
        WHERE rs.party_id = ?
        ORDER BY rs.round_number ASC, rs.player_index ASC
        "#
    )
    .bind(&party_id)
    .fetch_all(state.party_repo.get_db())
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(ErrorResponse { error: e.to_string() })))?;

    // Group round scores by round number
    let mut rounds_map: std::collections::HashMap<i32, Vec<PlayerRoundScore>> = std::collections::HashMap::new();
    for (round_number, user_id, username, player_index, score_this_round, total_score_after, hand_points, is_zapzap_caller, zapzap_success, was_counteracted, hand_cards_json, is_lowest_hand, is_eliminated) in round_scores_raw {
        let hand_cards: Vec<u8> = serde_json::from_str(&hand_cards_json).unwrap_or_default();

        rounds_map.entry(round_number).or_default().push(PlayerRoundScore {
            user_id,
            username,
            player_index,
            score_this_round,
            total_score_after,
            hand_points,
            is_zapzap_caller,
            zapzap_success,
            was_counteracted,
            hand_cards,
            is_lowest_hand,
            is_eliminated,
        });
    }

    // Convert to sorted Vec
    let mut rounds: Vec<RoundScoreInfo> = rounds_map
        .into_iter()
        .map(|(round_number, players)| RoundScoreInfo { round_number, players })
        .collect();
    rounds.sort_by_key(|r| r.round_number);

    Ok(Json(GameDetailsResponse {
        success: true,
        game: GameDetailsInfo {
            party_id,
            party_name,
            visibility,
            status,
            winner: WinnerInfo {
                user_id: winner_user_id,
                username: winner_username,
                final_score: winner_final_score,
            },
            total_rounds,
            was_golden_score,
            player_count,
            finished_at,
        },
        players,
        rounds,
    }))
}
