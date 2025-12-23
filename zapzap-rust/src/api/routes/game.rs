use std::sync::Arc;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    Extension,
};
use serde::{Deserialize, Serialize};

use crate::api::middleware::Claims;
use crate::api::AppState;
use crate::infrastructure::app_state::GameEvent;
use crate::application::game::{
    CallZapZap, CallZapZapInput, DrawCard, DrawCardInput, GetGameState, GetGameStateInput,
    NextRound, NextRoundInput, PlayCards, PlayCardsInput, SelectHandSize, SelectHandSizeInput,
};
use crate::application::bot::{ReflectOnRound, ReflectOnRoundInput, RoundOutcome};

// ============================================================================
// Request/Response DTOs
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct PlayCardsRequest {
    #[serde(rename = "cardIds")]
    pub card_ids: Vec<u8>,
}

#[derive(Debug, Deserialize)]
pub struct DrawCardRequest {
    pub source: String,
    #[serde(rename = "cardId")]
    pub card_id: Option<u8>,
}

#[derive(Debug, Deserialize)]
pub struct SelectHandSizeRequest {
    #[serde(rename = "handSize")]
    pub hand_size: u8,
}

// Response types
#[derive(Debug, Serialize)]
pub struct GameStateResponse {
    pub success: bool,
    pub party: PartyInfo,
    pub players: Vec<PlayerInfo>,
    pub round: Option<RoundInfo>,
    #[serde(rename = "gameState")]
    pub game_state: Option<GameStateInfo>,
}

#[derive(Debug, Serialize)]
pub struct PartyInfo {
    pub id: String,
    pub name: String,
    pub status: String,
}

#[derive(Debug, Serialize)]
pub struct PlayerInfo {
    #[serde(rename = "userId")]
    pub user_id: String,
    pub username: String,
    #[serde(rename = "playerIndex")]
    pub player_index: u8,
    #[serde(rename = "userType")]
    pub user_type: String,
    #[serde(rename = "botDifficulty")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bot_difficulty: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct RoundInfo {
    pub id: String,
    #[serde(rename = "roundNumber")]
    pub round_number: u32,
    pub status: String,
}

#[derive(Debug, Serialize)]
pub struct GameStateInfo {
    #[serde(rename = "currentTurn")]
    pub current_turn: u8,
    #[serde(rename = "currentAction")]
    pub current_action: String,
    #[serde(rename = "deckSize")]
    pub deck_size: usize,
    #[serde(rename = "lastCardsPlayed")]
    pub last_cards_played: Vec<u8>,
    #[serde(rename = "cardsPlayed")]
    pub cards_played: Vec<u8>,
    pub scores: std::collections::HashMap<String, u16>,
    #[serde(rename = "playerHand")]
    pub player_hand: Vec<u8>,
    #[serde(rename = "otherPlayersHandSizes")]
    pub other_players_hand_sizes: std::collections::HashMap<String, usize>,
    #[serde(rename = "lastAction")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_action: Option<serde_json::Value>,
    #[serde(rename = "isGoldenScore")]
    pub is_golden_score: bool,
    #[serde(rename = "eliminatedPlayers")]
    pub eliminated_players: Vec<u8>,
    #[serde(rename = "startingPlayer")]
    pub starting_player: u8,
    // Round end data (only populated when finished)
    #[serde(rename = "allHands")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub all_hands: Option<std::collections::HashMap<String, Vec<u8>>>,
    #[serde(rename = "handPoints")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hand_points: Option<std::collections::HashMap<String, u16>>,
    #[serde(rename = "zapZapCaller")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub zapzap_caller: Option<u8>,
    #[serde(rename = "lowestHandPlayerIndex")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lowest_hand_player_index: Option<u8>,
    #[serde(rename = "wasCounterActed")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub was_counter_acted: Option<bool>,
    #[serde(rename = "counterActedByPlayerIndex")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub counter_acted_by_player_index: Option<u8>,
    #[serde(rename = "roundScores")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub round_scores: Option<std::collections::HashMap<String, u16>>,
    // Game end data
    #[serde(rename = "gameFinished")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub game_finished: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub winner: Option<WinnerInfo>,
}

#[derive(Debug, Serialize)]
pub struct WinnerInfo {
    #[serde(rename = "userId")]
    pub user_id: String,
    #[serde(rename = "playerIndex")]
    pub player_index: u8,
    pub username: String,
    pub score: u16,
}

#[derive(Debug, Serialize)]
pub struct PlayCardsResponse {
    pub success: bool,
    #[serde(rename = "cardsPlayed")]
    pub cards_played: Vec<u8>,
    #[serde(rename = "remainingCards")]
    pub remaining_cards: usize,
    #[serde(rename = "gameState")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub game_state: Option<GameStateInfo>,
}

#[derive(Debug, Serialize)]
pub struct DrawCardResponse {
    pub success: bool,
    #[serde(rename = "cardDrawn")]
    pub card_drawn: u8,
    pub source: String,
    #[serde(rename = "handSize")]
    pub hand_size: usize,
    #[serde(rename = "gameState")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub game_state: Option<GameStateInfo>,
}

#[derive(Debug, Serialize)]
pub struct SelectHandSizeResponse {
    pub success: bool,
    #[serde(rename = "handSize")]
    pub hand_size: u8,
    #[serde(rename = "gameState")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub game_state: Option<GameStateInfo>,
}

#[derive(Debug, Serialize)]
pub struct ZapZapResponse {
    pub success: bool,
    #[serde(rename = "zapzapSuccess")]
    pub zapzap_success: bool,
    pub counteracted: bool,
    #[serde(rename = "counteractedBy")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub counteracted_by: Option<String>,
    pub scores: Vec<ScoreEntry>,
    #[serde(rename = "handPoints")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hand_points: Option<u16>,
    #[serde(rename = "callerPoints")]
    pub caller_points: u16,
}

#[derive(Debug, Clone, Serialize)]
pub struct ScoreEntry {
    #[serde(rename = "playerIndex")]
    pub player_index: u8,
    pub score: u16,
}

#[derive(Debug, Serialize)]
pub struct NextRoundResponse {
    pub success: bool,
    #[serde(rename = "gameFinished")]
    pub game_finished: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub winner: Option<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub round: Option<NextRoundInfo>,
    #[serde(rename = "startingPlayer")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub starting_player: Option<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scores: Option<Vec<ScoreEntry>>,
    #[serde(rename = "eliminatedPlayers")]
    pub eliminated_players: Vec<u8>,
    #[serde(rename = "finalScores")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub final_scores: Option<Vec<ScoreEntry>>,
}

#[derive(Debug, Serialize)]
pub struct NextRoundInfo {
    pub id: String,
    #[serde(rename = "roundNumber")]
    pub round_number: u32,
}

#[derive(Debug, Serialize)]
pub struct TriggerBotResponse {
    pub success: bool,
    pub message: String,
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

/// GET /api/game/:partyId/state - Get current game state
pub async fn get_game_state(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
) -> Result<Json<GameStateResponse>, (StatusCode, Json<ErrorResponse>)> {
    let use_case = GetGameState::new(state.user_repo.clone(), state.party_repo.clone());
    let result = use_case
        .execute(GetGameStateInput {
            user_id: claims.user_id.clone(),
            party_id,
        })
        .await
        .map_err(|e| {
            let err_msg = e.to_string();
            let (status, code) = match err_msg.as_str() {
                "Party not found" => (StatusCode::NOT_FOUND, "PARTY_NOT_FOUND"),
                "User is not in this party" => (StatusCode::FORBIDDEN, "NOT_IN_PARTY"),
                _ => (StatusCode::INTERNAL_SERVER_ERROR, "GET_STATE_ERROR"),
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

    // Get current player's index
    let my_player_index = result.player_index.unwrap_or(0);

    let game_state_info = result.game_state.map(|gs| {
        // Build scores as HashMap<String, u16> like JS
        let mut scores_map = std::collections::HashMap::new();
        for (i, &score) in gs.scores.iter().enumerate() {
            scores_map.insert(i.to_string(), score);
        }

        // Build otherPlayersHandSizes as HashMap<String, usize>
        let mut other_hand_sizes = std::collections::HashMap::new();
        for (i, &size) in gs.hand_sizes.iter().enumerate() {
            if i as u8 != my_player_index {
                other_hand_sizes.insert(i.to_string(), size);
            }
        }

        // Build eliminated players list from scores > 100
        let eliminated_players: Vec<u8> = gs.scores.iter()
            .enumerate()
            .filter(|(_, &score)| score > 100)
            .map(|(i, _)| i as u8)
            .collect();

        GameStateInfo {
            current_turn: gs.current_turn,
            current_action: gs.current_action,
            deck_size: gs.deck_size,
            last_cards_played: gs.last_cards_played.clone(),
            cards_played: gs.cards_played.clone(),
            scores: scores_map,
            player_hand: gs.my_hand,
            other_players_hand_sizes: other_hand_sizes,
            last_action: gs.last_action,
            is_golden_score: gs.is_golden_score,
            eliminated_players,
            starting_player: gs.starting_player,
            // Round end data - populated when currentAction == "finished"
            all_hands: gs.all_hands,
            hand_points: gs.hand_points,
            zapzap_caller: gs.zapzap_caller,
            lowest_hand_player_index: gs.lowest_hand_player_index,
            was_counter_acted: gs.was_counter_acted,
            counter_acted_by_player_index: gs.counter_acted_by_player_index,
            round_scores: gs.round_scores,
            game_finished: gs.game_finished,
            winner: gs.winner.map(|w| WinnerInfo {
                user_id: w.user_id,
                player_index: w.player_index,
                username: w.username,
                score: w.score,
            }),
        }
    });

    Ok(Json(GameStateResponse {
        success: true,
        party: PartyInfo {
            id: result.party.id,
            name: result.party.name,
            status: result.party.status.as_str().to_string(),
        },
        players: result
            .players
            .into_iter()
            .map(|p| PlayerInfo {
                user_id: p.user.id.clone(),
                username: p.user.username.clone(),
                player_index: p.player_index,
                user_type: p.user.user_type.as_str().to_string(),
                bot_difficulty: p.user.bot_difficulty.map(|d| d.as_str().to_string()),
            })
            .collect(),
        round: result.round.map(|r| RoundInfo {
            id: r.id,
            round_number: r.round_number,
            status: r.status.as_str().to_string(),
        }),
        game_state: game_state_info,
    }))
}

/// POST /api/game/:partyId/selectHandSize - Select hand size
pub async fn select_hand_size(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
    Json(body): Json<SelectHandSizeRequest>,
) -> Result<Json<SelectHandSizeResponse>, (StatusCode, Json<ErrorResponse>)> {
    let party_id_for_event = party_id.clone();
    let party_id_for_bot = party_id.clone();
    let use_case = SelectHandSize::new(state.party_repo.clone());
    let result = use_case
        .execute(SelectHandSizeInput {
            party_id,
            user_id: claims.user_id.clone(),
            hand_size: body.hand_size,
        })
        .await
        .map_err(|e| {
            let err_msg = e.to_string();
            let (status, code) = if err_msg.contains("not found") {
                (StatusCode::NOT_FOUND, "PARTY_NOT_FOUND")
            } else if err_msg.contains("not in this party") {
                (StatusCode::FORBIDDEN, "NOT_IN_PARTY")
            } else if err_msg.contains("Not your turn") {
                (StatusCode::FORBIDDEN, "NOT_YOUR_TURN")
            } else if err_msg.contains("selection phase") || err_msg.contains("Wrong action") {
                (StatusCode::BAD_REQUEST, "INVALID_ACTION_STATE")
            } else if err_msg.contains("must be") || err_msg.contains("Invalid") {
                (StatusCode::BAD_REQUEST, "INVALID_HAND_SIZE")
            } else {
                (StatusCode::INTERNAL_SERVER_ERROR, "SELECT_HAND_SIZE_ERROR")
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

    // Emit SSE event
    let event = GameEvent::new("gameUpdate", Some(party_id_for_event), Some(claims.user_id.clone()))
        .with_action("selectHandSize")
        .with_data(serde_json::json!({
            "handSize": body.hand_size
        }));
    state.broadcast_event(event);

    // Spawn background task to trigger bot if it's a bot's turn
    let state_clone = state.clone();
    tokio::spawn(async move {
        // Small delay to let the state settle
        tokio::time::sleep(tokio::time::Duration::from_millis(300)).await;
        if let Err(e) = trigger_bot_internal(&state_clone, &party_id_for_bot).await {
            tracing::error!("Auto bot trigger after select_hand_size failed: {}", e);
        }
    });

    Ok(Json(SelectHandSizeResponse {
        success: true,
        hand_size: result.hand_size,
        game_state: None,
    }))
}

/// POST /api/game/:partyId/play - Play cards
pub async fn play_cards(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
    Json(body): Json<PlayCardsRequest>,
) -> Result<Json<PlayCardsResponse>, (StatusCode, Json<ErrorResponse>)> {
    if body.card_ids.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Card IDs are required".to_string(),
                code: "MISSING_CARDS".to_string(),
                details: None,
            }),
        ));
    }

    let party_id_for_bot = party_id.clone();
    let use_case = PlayCards::new(state.party_repo.clone());
    let result = use_case
        .execute(PlayCardsInput {
            party_id,
            user_id: claims.user_id.clone(),
            card_ids: body.card_ids.clone(),
        })
        .await
        .map_err(|e| {
            let err_msg = e.to_string();
            let (status, code) = if err_msg.contains("not found") {
                (StatusCode::NOT_FOUND, "PARTY_NOT_FOUND")
            } else if err_msg.contains("not in this party") {
                (StatusCode::FORBIDDEN, "NOT_IN_PARTY")
            } else if err_msg.contains("Not your turn") {
                (StatusCode::FORBIDDEN, "NOT_YOUR_TURN")
            } else if err_msg.contains("not PLAY") || err_msg.contains("Wrong action") {
                (StatusCode::BAD_REQUEST, "INVALID_ACTION_STATE")
            } else if err_msg.contains("not in hand") {
                (StatusCode::BAD_REQUEST, "INVALID_CARDS")
            } else if err_msg.contains("at least 2") || err_msg.contains("No cards") {
                (StatusCode::BAD_REQUEST, "INVALID_PLAY")
            } else if err_msg.contains("Invalid") || err_msg.contains("combination") {
                (StatusCode::BAD_REQUEST, "INVALID_PLAY")
            } else {
                (StatusCode::INTERNAL_SERVER_ERROR, "PLAY_CARDS_ERROR")
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

    // Emit SSE event
    let event = GameEvent::new("gameUpdate", Some(party_id_for_bot.clone()), Some(claims.user_id.clone()))
        .with_action("play")
        .with_data(serde_json::json!({
            "cardIds": body.card_ids
        }));
    state.broadcast_event(event);

    // Spawn background task to trigger bot if it's a bot's turn
    let state_clone = state.clone();
    tokio::spawn(async move {
        // Small delay to let the state settle
        tokio::time::sleep(tokio::time::Duration::from_millis(300)).await;
        if let Err(e) = trigger_bot_internal(&state_clone, &party_id_for_bot).await {
            tracing::error!("Auto bot trigger failed: {}", e);
        }
    });

    Ok(Json(PlayCardsResponse {
        success: true,
        cards_played: result.cards_played,
        remaining_cards: result.remaining_cards,
        game_state: None,
    }))
}

/// POST /api/game/:partyId/draw - Draw a card
pub async fn draw_card(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
    Json(body): Json<DrawCardRequest>,
) -> Result<Json<DrawCardResponse>, (StatusCode, Json<ErrorResponse>)> {
    if body.source != "deck" && body.source != "played" {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Source must be \"deck\" or \"played\"".to_string(),
                code: "INVALID_SOURCE".to_string(),
                details: None,
            }),
        ));
    }

    let party_id_for_bot = party_id.clone();
    let use_case = DrawCard::new(state.party_repo.clone());
    let result = use_case
        .execute(DrawCardInput {
            party_id,
            user_id: claims.user_id.clone(),
            source: body.source.clone(),
            card_id: body.card_id,
        })
        .await
        .map_err(|e| {
            let err_msg = e.to_string();
            let (status, code) = if err_msg.contains("not found") {
                (StatusCode::NOT_FOUND, "PARTY_NOT_FOUND")
            } else if err_msg.contains("not in this party") {
                (StatusCode::FORBIDDEN, "NOT_IN_PARTY")
            } else if err_msg.contains("Not your turn") {
                (StatusCode::FORBIDDEN, "NOT_YOUR_TURN")
            } else if err_msg.contains("not DRAW") || err_msg.contains("Wrong action") {
                (StatusCode::BAD_REQUEST, "INVALID_ACTION_STATE")
            } else if err_msg.contains("empty") {
                (StatusCode::BAD_REQUEST, "DECK_EMPTY")
            } else if err_msg.contains("No cards available") {
                (StatusCode::BAD_REQUEST, "NO_CARDS_AVAILABLE")
            } else if err_msg.contains("not available") {
                (StatusCode::BAD_REQUEST, "CARD_NOT_AVAILABLE")
            } else {
                (StatusCode::INTERNAL_SERVER_ERROR, "DRAW_CARD_ERROR")
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

    // Emit SSE event
    let event = GameEvent::new("gameUpdate", Some(party_id_for_bot.clone()), Some(claims.user_id.clone()))
        .with_action("draw")
        .with_data(serde_json::json!({
            "source": body.source
        }));
    state.broadcast_event(event);

    // Spawn background task to trigger bot if it's a bot's turn
    let state_clone = state.clone();
    tokio::spawn(async move {
        // Small delay to let the state settle
        tokio::time::sleep(tokio::time::Duration::from_millis(300)).await;
        if let Err(e) = trigger_bot_internal(&state_clone, &party_id_for_bot).await {
            tracing::error!("Auto bot trigger failed: {}", e);
        }
    });

    Ok(Json(DrawCardResponse {
        success: true,
        card_drawn: result.card_drawn,
        source: result.source,
        hand_size: result.hand_size,
        game_state: None,
    }))
}

/// POST /api/game/:partyId/zapzap - Call ZapZap
pub async fn call_zapzap(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
) -> Result<Json<ZapZapResponse>, (StatusCode, Json<ErrorResponse>)> {
    let party_id_for_event = party_id.clone();
    let use_case = CallZapZap::new(state.party_repo.clone());
    let result = use_case
        .execute(CallZapZapInput {
            party_id,
            user_id: claims.user_id.clone(),
        })
        .await
        .map_err(|e| {
            let err_msg = e.to_string();
            let (status, code) = if err_msg.contains("not found") {
                (StatusCode::NOT_FOUND, "PARTY_NOT_FOUND")
            } else if err_msg.contains("not in this party") {
                (StatusCode::FORBIDDEN, "NOT_IN_PARTY")
            } else if err_msg.contains("Not your turn") {
                (StatusCode::FORBIDDEN, "NOT_YOUR_TURN")
            } else if err_msg.contains("too high") || err_msg.contains("Hand value") {
                (StatusCode::BAD_REQUEST, "HAND_TOO_HIGH")
            } else if err_msg.contains("Cannot call") || err_msg.contains("Wrong action") {
                (StatusCode::BAD_REQUEST, "INVALID_ACTION_STATE")
            } else {
                (StatusCode::INTERNAL_SERVER_ERROR, "ZAPZAP_ERROR")
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

    // Emit SSE event
    let event = GameEvent::new("gameUpdate", Some(party_id_for_event.clone()), Some(claims.user_id.clone()))
        .with_action("zapzap")
        .with_data(serde_json::json!({
            "success": result.success,
            "counteracted": result.counteracted
        }));
    state.broadcast_event(event);

    // Trigger LLM reflection for any LLM bots in the party (human called ZapZap)
    {
        use crate::domain::repositories::PartyRepository;
        let party_id_for_reflection = party_id_for_event.clone();
        let state_for_reflection = state.clone();
        let counteracted = result.counteracted;
        let user_id_for_reflection = claims.user_id.clone();

        tokio::spawn(async move {
            // Get game state for round number
            let game_state = match state_for_reflection.party_repo.get_game_state(&party_id_for_reflection).await {
                Ok(Some(gs)) => gs,
                _ => return,
            };

            // Get players to find caller's index
            let players = match state_for_reflection.party_repo.get_party_players(&party_id_for_reflection).await {
                Ok(p) => p,
                _ => return,
            };

            let caller_idx = players.iter()
                .find(|p| p.user_id == user_id_for_reflection)
                .map(|p| p.player_index);

            trigger_llm_reflection(
                &state_for_reflection,
                &party_id_for_reflection,
                game_state.round_number as u32,
                caller_idx,
                counteracted,
            ).await;
        });
    }

    Ok(Json(ZapZapResponse {
        success: true,
        zapzap_success: result.success,
        counteracted: result.counteracted,
        counteracted_by: result.counteracted_by,
        scores: result
            .scores
            .into_iter()
            .map(|(idx, score)| ScoreEntry {
                player_index: idx,
                score,
            })
            .collect(),
        hand_points: None,
        caller_points: result.caller_hand_points,
    }))
}

/// POST /api/game/:partyId/nextRound - Start next round
pub async fn next_round(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
) -> Result<Json<NextRoundResponse>, (StatusCode, Json<ErrorResponse>)> {
    let party_id_for_event = party_id.clone();
    let party_id_for_bot = party_id.clone();
    let use_case = NextRound::new(state.party_repo.clone());
    let result = use_case
        .execute(NextRoundInput {
            party_id,
            user_id: claims.user_id.clone(),
        })
        .await
        .map_err(|e| {
            let err_msg = e.to_string();
            let (status, code) = if err_msg.contains("not found") {
                (StatusCode::NOT_FOUND, "PARTY_NOT_FOUND")
            } else if err_msg.contains("not in this party") {
                (StatusCode::FORBIDDEN, "NOT_IN_PARTY")
            } else if err_msg.contains("not in playing") || err_msg.contains("not playing") {
                (StatusCode::BAD_REQUEST, "INVALID_PARTY_STATE")
            } else if err_msg.contains("not finished") {
                (StatusCode::BAD_REQUEST, "ROUND_NOT_FINISHED")
            } else {
                (StatusCode::INTERNAL_SERVER_ERROR, "NEXT_ROUND_ERROR")
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

    // Emit SSE event
    let action = if result.game_finished { "gameFinished" } else { "roundStarted" };
    let event = GameEvent::new("gameUpdate", Some(party_id_for_event), Some(claims.user_id.clone()))
        .with_action(action)
        .with_data(serde_json::json!({
            "gameFinished": result.game_finished
        }));
    state.broadcast_event(event);

    // starting_player is stored in GameState, not in Round
    let starting_player = result.starting_player;

    // Spawn background task to trigger bot if starting player is a bot
    if !result.game_finished {
        let state_clone = state.clone();
        tokio::spawn(async move {
            // Small delay to let the state settle
            tokio::time::sleep(tokio::time::Duration::from_millis(300)).await;
            if let Err(e) = trigger_bot_internal(&state_clone, &party_id_for_bot).await {
                tracing::error!("Auto bot trigger after next_round failed: {}", e);
            }
        });
    }

    // Convert scores to ScoreEntry format
    let score_entries: Vec<ScoreEntry> = result
        .scores
        .iter()
        .enumerate()
        .map(|(i, &score)| ScoreEntry {
            player_index: i as u8,
            score,
        })
        .collect();

    // If game finished, final_scores are the same as scores
    let final_scores = if result.game_finished {
        Some(score_entries.clone())
    } else {
        None
    };

    Ok(Json(NextRoundResponse {
        success: true,
        game_finished: result.game_finished,
        winner: result.winner,
        round: result.round.map(|r| NextRoundInfo {
            id: r.id,
            round_number: r.round_number,
        }),
        starting_player: Some(starting_player),
        scores: Some(score_entries),
        eliminated_players: result.eliminated_players,
        final_scores,
    }))
}

/// POST /api/game/:partyId/trigger-bot - Manually trigger bot turn
pub async fn trigger_bot(
    State(state): State<Arc<AppState>>,
    Path(party_id): Path<String>,
) -> Result<Json<TriggerBotResponse>, (StatusCode, Json<ErrorResponse>)> {
    use crate::domain::repositories::{PartyRepository, UserRepository};
    use crate::infrastructure::bot::strategies::{BotStrategy, DrawSource, EasyBotStrategy, HardBotStrategy, MediumBotStrategy, LlmBotStrategy, ThibotStrategy, VinceBotStrategy};

    let max_iterations = 50; // Safety limit
    let mut iterations = 0;
    let mut actions_taken = 0;

    loop {
        iterations += 1;
        if iterations > max_iterations {
            tracing::warn!("Bot trigger hit max iterations for party {}", party_id);
            break;
        }

        // Get game state
        let game_state = match state.party_repo.get_game_state(&party_id).await {
            Ok(Some(gs)) => gs,
            Ok(None) => {
                return Ok(Json(TriggerBotResponse {
                    success: true,
                    message: format!("No game state found. Actions taken: {}", actions_taken),
                }));
            }
            Err(e) => {
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse {
                        error: e.to_string(),
                        code: "GAME_STATE_ERROR".to_string(),
                        details: None,
                    }),
                ));
            }
        };

        // Check if round is finished
        if game_state.current_action == crate::domain::value_objects::GameAction::Finished {
            return Ok(Json(TriggerBotResponse {
                success: true,
                message: format!("Round finished. Actions taken: {}", actions_taken),
            }));
        }

        // Get current player
        let players = match state.party_repo.get_party_players(&party_id).await {
            Ok(p) => p,
            Err(e) => {
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse {
                        error: e.to_string(),
                        code: "PLAYERS_ERROR".to_string(),
                        details: None,
                    }),
                ));
            }
        };

        let current_player = players.iter().find(|p| p.player_index == game_state.current_turn);
        let current_player = match current_player {
            Some(p) => p,
            None => {
                return Ok(Json(TriggerBotResponse {
                    success: true,
                    message: format!("No current player found. Actions taken: {}", actions_taken),
                }));
            }
        };

        // Get user info
        let user = match state.user_repo.find_by_id(&current_player.user_id).await {
            Ok(Some(u)) => u,
            Ok(None) => {
                return Ok(Json(TriggerBotResponse {
                    success: true,
                    message: format!("User not found. Actions taken: {}", actions_taken),
                }));
            }
            Err(e) => {
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse {
                        error: e.to_string(),
                        code: "USER_ERROR".to_string(),
                        details: None,
                    }),
                ));
            }
        };

        // Check if user is a bot
        if user.user_type.as_str() != "bot" {
            // Human's turn - stop triggering
            return Ok(Json(TriggerBotResponse {
                success: true,
                message: format!("Human player's turn. Actions taken: {}", actions_taken),
            }));
        }

        // Check if bot is eliminated - skip to next player
        if game_state.is_eliminated(current_player.player_index) {
            tracing::info!("Bot {} is eliminated, advancing to next player", user.username);
            // Advance to next non-eliminated player
            let mut next_turn = (game_state.current_turn + 1) % game_state.player_count;
            let mut attempts = 0;
            while game_state.is_eliminated(next_turn) && attempts < game_state.player_count {
                next_turn = (next_turn + 1) % game_state.player_count;
                attempts += 1;
            }

            // Update game state with new current turn
            let mut updated_state = game_state.clone();
            updated_state.current_turn = next_turn;
            if let Err(e) = state.party_repo.save_game_state(&party_id, &updated_state).await {
                tracing::error!("Failed to update game state: {}", e);
            }
            continue; // Continue loop to process next player
        }

        let player_index = current_player.player_index;
        let user_id = user.id.clone();

        // Check if this is an LLM bot
        let is_llm_bot = matches!(user.bot_difficulty, Some(crate::domain::entities::BotDifficulty::Llm));

        // Execute bot action based on current action state
        match game_state.current_action {
            crate::domain::value_objects::GameAction::SelectHandSize => {
                // Hand size selection uses fallback strategy for all bots
                let strategy = HardBotStrategy::new();
                let hand_size = strategy.select_hand_size(&game_state, player_index);
                tracing::info!("Bot {} selecting hand size: {}", user.username, hand_size);

                let use_case = SelectHandSize::new(state.party_repo.clone());
                match use_case.execute(SelectHandSizeInput {
                    party_id: party_id.clone(),
                    user_id: user_id.clone(),
                    hand_size,
                }).await {
                    Ok(_) => {
                        actions_taken += 1;
                        tracing::info!("Bot {} selected hand size {}", user.username, hand_size);
                    }
                    Err(e) => {
                        tracing::error!("Bot select hand size error: {}", e);
                        return Err((
                            StatusCode::INTERNAL_SERVER_ERROR,
                            Json(ErrorResponse {
                                error: format!("Bot select hand size failed: {}", e),
                                code: "BOT_ACTION_ERROR".to_string(),
                                details: None,
                            }),
                        ));
                    }
                }
            }
            crate::domain::value_objects::GameAction::Play => {
                // Handle LLM bots with async strategy
                if is_llm_bot {
                    let memory = state.get_llm_memory(&user_id).await;
                    let llm_strategy = LlmBotStrategy::new(state.llm_service.clone(), Some(memory));

                    // Check if should call ZapZap (async)
                    if llm_strategy.should_call_zapzap_async(&game_state, player_index).await {
                        tracing::info!("LLM Bot {} calling ZapZap", user.username);

                        let use_case = CallZapZap::new(state.party_repo.clone());
                        match use_case.execute(CallZapZapInput {
                            party_id: party_id.clone(),
                            user_id: user_id.clone(),
                        }).await {
                            Ok(_) => {
                                actions_taken += 1;
                                tracing::info!("LLM Bot {} called ZapZap", user.username);
                            }
                            Err(e) => {
                                tracing::error!("LLM Bot ZapZap error: {}", e);
                            }
                        }
                    } else {
                        // Play cards (async)
                        let cards_to_play = llm_strategy.select_cards_async(&game_state, player_index).await;
                        if cards_to_play.is_empty() {
                            tracing::warn!("LLM Bot {} has no valid plays", user.username);
                            return Err((
                                StatusCode::INTERNAL_SERVER_ERROR,
                                Json(ErrorResponse {
                                    error: "Bot has no valid plays".to_string(),
                                    code: "BOT_NO_PLAYS".to_string(),
                                    details: None,
                                }),
                            ));
                        }

                        tracing::info!("LLM Bot {} playing cards: {:?}", user.username, cards_to_play);

                        let use_case = PlayCards::new(state.party_repo.clone());
                        match use_case.execute(PlayCardsInput {
                            party_id: party_id.clone(),
                            user_id: user_id.clone(),
                            card_ids: cards_to_play.clone(),
                        }).await {
                            Ok(_) => {
                                actions_taken += 1;
                                tracing::info!("LLM Bot {} played {:?}", user.username, cards_to_play);
                            }
                            Err(e) => {
                                tracing::error!("LLM Bot play cards error: {}", e);
                                return Err((
                                    StatusCode::INTERNAL_SERVER_ERROR,
                                    Json(ErrorResponse {
                                        error: format!("Bot play cards failed: {}", e),
                                        code: "BOT_ACTION_ERROR".to_string(),
                                        details: None,
                                    }),
                                ));
                            }
                        }
                    }
                } else {
                    // Non-LLM bots use sync strategy
                    let strategy: Box<dyn BotStrategy> = match user.bot_difficulty {
                        Some(crate::domain::entities::BotDifficulty::Easy) => Box::new(EasyBotStrategy::new()),
                        Some(crate::domain::entities::BotDifficulty::Medium) => Box::new(MediumBotStrategy::new()),
                        Some(crate::domain::entities::BotDifficulty::Thibot) => Box::new(ThibotStrategy::new()),
                        Some(crate::domain::entities::BotDifficulty::HardVince) => Box::new(VinceBotStrategy::new()),
                        _ => Box::new(HardBotStrategy::new()),
                    };

                    // Check if should call ZapZap
                    if strategy.should_call_zapzap(&game_state, player_index) {
                        tracing::info!("Bot {} calling ZapZap", user.username);

                        let use_case = CallZapZap::new(state.party_repo.clone());
                        match use_case.execute(CallZapZapInput {
                            party_id: party_id.clone(),
                            user_id: user_id.clone(),
                        }).await {
                            Ok(_) => {
                                actions_taken += 1;
                                tracing::info!("Bot {} called ZapZap", user.username);
                            }
                            Err(e) => {
                                tracing::error!("Bot ZapZap error: {}", e);
                            }
                        }
                    } else {
                        // Play cards
                        let cards_to_play = strategy.select_cards(&game_state, player_index);
                        if cards_to_play.is_empty() {
                            tracing::warn!("Bot {} has no valid plays", user.username);
                            return Err((
                                StatusCode::INTERNAL_SERVER_ERROR,
                                Json(ErrorResponse {
                                    error: "Bot has no valid plays".to_string(),
                                    code: "BOT_NO_PLAYS".to_string(),
                                    details: None,
                                }),
                            ));
                        }

                        tracing::info!("Bot {} playing cards: {:?}", user.username, cards_to_play);

                        let use_case = PlayCards::new(state.party_repo.clone());
                        match use_case.execute(PlayCardsInput {
                            party_id: party_id.clone(),
                            user_id: user_id.clone(),
                            card_ids: cards_to_play.clone(),
                        }).await {
                            Ok(_) => {
                                actions_taken += 1;
                                tracing::info!("Bot {} played {:?}", user.username, cards_to_play);
                            }
                            Err(e) => {
                                tracing::error!("Bot play cards error: {}", e);
                                return Err((
                                    StatusCode::INTERNAL_SERVER_ERROR,
                                    Json(ErrorResponse {
                                        error: format!("Bot play cards failed: {}", e),
                                        code: "BOT_ACTION_ERROR".to_string(),
                                        details: None,
                                    }),
                                ));
                            }
                        }
                    }
                }
            }
            crate::domain::value_objects::GameAction::Draw => {
                // Handle LLM bots with async strategy
                let (source_str, card_id) = if is_llm_bot {
                    let memory = state.get_llm_memory(&user_id).await;
                    let llm_strategy = LlmBotStrategy::new(state.llm_service.clone(), Some(memory));
                    let draw_source = llm_strategy.decide_draw_source_async(&game_state, player_index).await;
                    match draw_source {
                        DrawSource::Deck => ("deck".to_string(), None),
                        DrawSource::Discard(card) => ("played".to_string(), Some(card)),
                    }
                } else {
                    let strategy: Box<dyn BotStrategy> = match user.bot_difficulty {
                        Some(crate::domain::entities::BotDifficulty::Easy) => Box::new(EasyBotStrategy::new()),
                        Some(crate::domain::entities::BotDifficulty::Medium) => Box::new(MediumBotStrategy::new()),
                        Some(crate::domain::entities::BotDifficulty::Thibot) => Box::new(ThibotStrategy::new()),
                        Some(crate::domain::entities::BotDifficulty::HardVince) => Box::new(VinceBotStrategy::new()),
                        _ => Box::new(HardBotStrategy::new()),
                    };
                    let draw_source = strategy.decide_draw_source(&game_state, player_index);
                    match draw_source {
                        DrawSource::Deck => ("deck".to_string(), None),
                        DrawSource::Discard(card) => ("played".to_string(), Some(card)),
                    }
                };

                tracing::info!("Bot {} drawing from {}", user.username, source_str);

                let use_case = DrawCard::new(state.party_repo.clone());
                match use_case.execute(DrawCardInput {
                    party_id: party_id.clone(),
                    user_id: user_id.clone(),
                    source: source_str.clone(),
                    card_id,
                }).await {
                    Ok(_) => {
                        actions_taken += 1;
                        tracing::info!("Bot {} drew from {}", user.username, source_str);
                    }
                    Err(e) => {
                        tracing::error!("Bot draw error: {}", e);
                        // Try deck if discard failed
                        if source_str == "played" {
                            tracing::info!("Bot {} retrying with deck", user.username);
                            let use_case = DrawCard::new(state.party_repo.clone());
                            match use_case.execute(DrawCardInput {
                                party_id: party_id.clone(),
                                user_id: user_id.clone(),
                                source: "deck".to_string(),
                                card_id: None,
                            }).await {
                                Ok(_) => {
                                    actions_taken += 1;
                                    tracing::info!("Bot {} drew from deck (fallback)", user.username);
                                }
                                Err(e2) => {
                                    return Err((
                                        StatusCode::INTERNAL_SERVER_ERROR,
                                        Json(ErrorResponse {
                                            error: format!("Bot draw failed: {}", e2),
                                            code: "BOT_ACTION_ERROR".to_string(),
                                            details: None,
                                        }),
                                    ));
                                }
                            }
                        } else {
                            return Err((
                                StatusCode::INTERNAL_SERVER_ERROR,
                                Json(ErrorResponse {
                                    error: format!("Bot draw failed: {}", e),
                                    code: "BOT_ACTION_ERROR".to_string(),
                                    details: None,
                                }),
                            ));
                        }
                    }
                }
            }
            crate::domain::value_objects::GameAction::Finished => {
                return Ok(Json(TriggerBotResponse {
                    success: true,
                    message: format!("Round finished. Actions taken: {}", actions_taken),
                }));
            }
            crate::domain::value_objects::GameAction::ZapZap => {
                // ZapZap state - waiting for counter, this shouldn't happen for bots
                tracing::warn!("Bot encountered ZapZap action state, skipping");
                return Ok(Json(TriggerBotResponse {
                    success: true,
                    message: format!("ZapZap state encountered. Actions taken: {}", actions_taken),
                }));
            }
        }

        // Small delay between actions to avoid overwhelming
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    }

    Ok(Json(TriggerBotResponse {
        success: true,
        message: format!("Bot trigger completed. Actions taken: {}", actions_taken),
    }))
}

/// Internal function to trigger bot actions (used by background tasks)
async fn trigger_bot_internal(state: &Arc<AppState>, party_id: &str) -> Result<(), String> {
    use crate::domain::repositories::{PartyRepository, UserRepository};
    use crate::infrastructure::bot::strategies::{BotStrategy, DrawSource, EasyBotStrategy, HardBotStrategy, MediumBotStrategy, LlmBotStrategy, ThibotStrategy, VinceBotStrategy};

    let max_iterations = 50;
    let mut iterations = 0;

    loop {
        iterations += 1;
        if iterations > max_iterations {
            tracing::warn!("Auto bot trigger hit max iterations for party {}", party_id);
            break;
        }

        // Get game state
        let game_state = match state.party_repo.get_game_state(party_id).await {
            Ok(Some(gs)) => gs,
            Ok(None) => return Ok(()),
            Err(e) => return Err(e.to_string()),
        };

        // Check if round is finished
        if game_state.current_action == crate::domain::value_objects::GameAction::Finished {
            return Ok(());
        }

        // Get current player
        let players = match state.party_repo.get_party_players(party_id).await {
            Ok(p) => p,
            Err(e) => return Err(e.to_string()),
        };

        let current_player = match players.iter().find(|p| p.player_index == game_state.current_turn) {
            Some(p) => p,
            None => return Ok(()),
        };

        // Get user info
        let user = match state.user_repo.find_by_id(&current_player.user_id).await {
            Ok(Some(u)) => u,
            Ok(None) => return Ok(()),
            Err(e) => return Err(e.to_string()),
        };

        // If human's turn, stop
        if user.user_type.as_str() != "bot" {
            return Ok(());
        }

        // Skip eliminated bots
        if game_state.is_eliminated(current_player.player_index) {
            let mut next_turn = (game_state.current_turn + 1) % game_state.player_count;
            let mut attempts = 0;
            while game_state.is_eliminated(next_turn) && attempts < game_state.player_count {
                next_turn = (next_turn + 1) % game_state.player_count;
                attempts += 1;
            }
            let mut updated_state = game_state.clone();
            updated_state.current_turn = next_turn;
            if let Err(e) = state.party_repo.save_game_state(party_id, &updated_state).await {
                tracing::error!("Failed to update game state: {}", e);
            }
            continue;
        }

        let player_index = current_player.player_index;
        let user_id = user.id.clone();

        // Check if this is an LLM bot
        let is_llm_bot = matches!(user.bot_difficulty, Some(crate::domain::entities::BotDifficulty::Llm));

        // Execute bot action
        match game_state.current_action {
            crate::domain::value_objects::GameAction::SelectHandSize => {
                let strategy = HardBotStrategy::new();
                let hand_size = strategy.select_hand_size(&game_state, player_index);
                tracing::info!("Auto: Bot {} selecting hand size: {}", user.username, hand_size);
                let use_case = SelectHandSize::new(state.party_repo.clone());
                use_case.execute(SelectHandSizeInput {
                    party_id: party_id.to_string(),
                    user_id: user_id.clone(),
                    hand_size,
                }).await.map_err(|e| e.to_string())?;

                // Broadcast SSE event for bot action
                let event = GameEvent::new("gameUpdate", Some(party_id.to_string()), Some(user_id))
                    .with_action("selectHandSize")
                    .with_data(serde_json::json!({
                        "handSize": hand_size,
                        "isBot": true
                    }));
                state.broadcast_event(event);
            }
            crate::domain::value_objects::GameAction::Play => {
                if is_llm_bot {
                    let memory = state.get_llm_memory(&user_id).await;
                    let llm_strategy = LlmBotStrategy::new(state.llm_service.clone(), Some(memory));

                    let can_zapzap = llm_strategy.should_call_zapzap_async(&game_state, player_index).await;
                    if can_zapzap {
                        tracing::info!("Auto: LLM Bot {} calling ZapZap!", user.username);
                        let use_case = CallZapZap::new(state.party_repo.clone());
                        let zapzap_result = use_case.execute(CallZapZapInput {
                            party_id: party_id.to_string(),
                            user_id: user_id.clone(),
                        }).await.map_err(|e| e.to_string())?;

                        let event = GameEvent::new("gameUpdate", Some(party_id.to_string()), Some(user_id.clone()))
                            .with_action("zapzap")
                            .with_data(serde_json::json!({"isBot": true}));
                        state.broadcast_event(event);

                        // Trigger LLM reflection after round finishes
                        trigger_llm_reflection(
                            state,
                            party_id,
                            game_state.round_number as u32,
                            Some(player_index),
                            zapzap_result.counteracted,
                        ).await;
                    } else {
                        let cards_to_play = llm_strategy.select_cards_async(&game_state, player_index).await;
                        if cards_to_play.is_empty() {
                            return Err("LLM Bot has no valid play".to_string());
                        }
                        tracing::info!("Auto: LLM Bot {} playing cards: {:?}", user.username, cards_to_play);
                        let use_case = PlayCards::new(state.party_repo.clone());
                        use_case.execute(PlayCardsInput {
                            party_id: party_id.to_string(),
                            user_id: user_id.clone(),
                            card_ids: cards_to_play.clone(),
                        }).await.map_err(|e| e.to_string())?;

                        let event = GameEvent::new("gameUpdate", Some(party_id.to_string()), Some(user_id))
                            .with_action("play")
                            .with_data(serde_json::json!({"cardIds": cards_to_play, "isBot": true}));
                        state.broadcast_event(event);
                    }
                } else {
                    let strategy: Box<dyn BotStrategy> = match user.bot_difficulty {
                        Some(crate::domain::entities::BotDifficulty::Easy) => Box::new(EasyBotStrategy::new()),
                        Some(crate::domain::entities::BotDifficulty::Medium) => Box::new(MediumBotStrategy::new()),
                        Some(crate::domain::entities::BotDifficulty::Thibot) => Box::new(ThibotStrategy::new()),
                        Some(crate::domain::entities::BotDifficulty::HardVince) => Box::new(VinceBotStrategy::new()),
                        _ => Box::new(HardBotStrategy::new()),
                    };

                    let can_zapzap = strategy.should_call_zapzap(&game_state, player_index);
                    if can_zapzap {
                        tracing::info!("Auto: Bot {} calling ZapZap!", user.username);
                        let use_case = CallZapZap::new(state.party_repo.clone());
                        let zapzap_result = use_case.execute(CallZapZapInput {
                            party_id: party_id.to_string(),
                            user_id: user_id.clone(),
                        }).await.map_err(|e| e.to_string())?;

                        let event = GameEvent::new("gameUpdate", Some(party_id.to_string()), Some(user_id))
                            .with_action("zapzap")
                            .with_data(serde_json::json!({"isBot": true}));
                        state.broadcast_event(event);

                        // Trigger LLM reflection for any LLM bots in the party
                        trigger_llm_reflection(
                            state,
                            party_id,
                            game_state.round_number as u32,
                            Some(player_index),
                            zapzap_result.counteracted,
                        ).await;
                    } else {
                        let cards_to_play = strategy.select_cards(&game_state, player_index);
                        if cards_to_play.is_empty() {
                            return Err("Bot has no valid play".to_string());
                        }
                        tracing::info!("Auto: Bot {} playing cards: {:?}", user.username, cards_to_play);
                        let use_case = PlayCards::new(state.party_repo.clone());
                        use_case.execute(PlayCardsInput {
                            party_id: party_id.to_string(),
                            user_id: user_id.clone(),
                            card_ids: cards_to_play.clone(),
                        }).await.map_err(|e| e.to_string())?;

                        let event = GameEvent::new("gameUpdate", Some(party_id.to_string()), Some(user_id))
                            .with_action("play")
                            .with_data(serde_json::json!({"cardIds": cards_to_play, "isBot": true}));
                        state.broadcast_event(event);
                    }
                }
            }
            crate::domain::value_objects::GameAction::Draw => {
                let (source_str, card_id) = if is_llm_bot {
                    let memory = state.get_llm_memory(&user_id).await;
                    let llm_strategy = LlmBotStrategy::new(state.llm_service.clone(), Some(memory));
                    let draw_source = llm_strategy.decide_draw_source_async(&game_state, player_index).await;
                    match draw_source {
                        DrawSource::Deck => ("deck".to_string(), None),
                        DrawSource::Discard(card) => ("played".to_string(), Some(card)),
                    }
                } else {
                    let strategy: Box<dyn BotStrategy> = match user.bot_difficulty {
                        Some(crate::domain::entities::BotDifficulty::Easy) => Box::new(EasyBotStrategy::new()),
                        Some(crate::domain::entities::BotDifficulty::Medium) => Box::new(MediumBotStrategy::new()),
                        Some(crate::domain::entities::BotDifficulty::Thibot) => Box::new(ThibotStrategy::new()),
                        Some(crate::domain::entities::BotDifficulty::HardVince) => Box::new(VinceBotStrategy::new()),
                        _ => Box::new(HardBotStrategy::new()),
                    };
                    let draw_source = strategy.decide_draw_source(&game_state, player_index);
                    match draw_source {
                        DrawSource::Deck => ("deck".to_string(), None),
                        DrawSource::Discard(card) => ("played".to_string(), Some(card)),
                    }
                };

                tracing::info!("Auto: Bot {} drawing from {}", user.username, source_str);
                let use_case = DrawCard::new(state.party_repo.clone());
                let draw_result = use_case.execute(DrawCardInput {
                    party_id: party_id.to_string(),
                    user_id: user_id.clone(),
                    source: source_str.clone(),
                    card_id,
                }).await;

                let final_source = if draw_result.is_err() {
                    // Fallback to deck
                    let use_case = DrawCard::new(state.party_repo.clone());
                    use_case.execute(DrawCardInput {
                        party_id: party_id.to_string(),
                        user_id: user_id.clone(),
                        source: "deck".to_string(),
                        card_id: None,
                    }).await.map_err(|e| e.to_string())?;
                    "deck".to_string()
                } else {
                    source_str
                };

                // Broadcast SSE event for bot draw
                let event = GameEvent::new("gameUpdate", Some(party_id.to_string()), Some(user_id))
                    .with_action("draw")
                    .with_data(serde_json::json!({
                        "source": final_source,
                        "isBot": true
                    }));
                state.broadcast_event(event);
            }
            crate::domain::value_objects::GameAction::Finished => return Ok(()),
            crate::domain::value_objects::GameAction::ZapZap => return Ok(()),
        }

        tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;
    }

    Ok(())
}

/// Trigger reflection for all LLM bots in a party after a round finishes
async fn trigger_llm_reflection(
    state: &Arc<AppState>,
    party_id: &str,
    round_number: u32,
    zapzap_caller_idx: Option<u8>,
    was_counteracted: bool,
) {
    use crate::domain::repositories::{PartyRepository, UserRepository};
    use crate::infrastructure::bot::card_analyzer::calculate_hand_value;

    // Skip if no LLM service
    let Some(ref llm_service) = state.llm_service else {
        return;
    };

    // Get game state
    let game_state = match state.party_repo.get_game_state(party_id).await {
        Ok(Some(gs)) => gs,
        Ok(None) | Err(_) => return,
    };

    // Get players
    let players = match state.party_repo.get_party_players(party_id).await {
        Ok(p) => p,
        Err(_) => return,
    };

    // Find LLM bots and trigger reflection for each
    for player in &players {
        let user = match state.user_repo.find_by_id(&player.user_id).await {
            Ok(Some(u)) => u,
            _ => continue,
        };

        // Check if this is an LLM bot
        if !matches!(user.bot_difficulty, Some(crate::domain::entities::BotDifficulty::Llm)) {
            continue;
        }

        // Get bot memory
        let memory = state.get_llm_memory(&player.user_id).await;

        // Determine outcome for this bot
        let hand = game_state.get_hand(player.player_index);
        let hand_value = calculate_hand_value(hand);
        let is_zapzap_caller = zapzap_caller_idx == Some(player.player_index);
        let won = if is_zapzap_caller {
            !was_counteracted
        } else if let Some(lowest_idx) = game_state.lowest_hand_player_index {
            lowest_idx == player.player_index
        } else {
            false
        };

        // Build round outcome
        let outcome = RoundOutcome {
            won,
            counteracted: is_zapzap_caller && was_counteracted,
            score_change: 0, // Would need to calculate this
            hand_points: hand_value,
            final_hand: hand.to_vec(),
            is_golden_score: game_state.is_golden_score,
        };

        // Trigger reflection in background
        let reflect_use_case = ReflectOnRound::new(llm_service.clone());
        let input = ReflectOnRoundInput {
            bot_user_id: player.user_id.clone(),
            party_id: party_id.to_string(),
            round_number,
            outcome,
        };

        let memory_clone = memory.clone();
        tokio::spawn(async move {
            let result = reflect_use_case.execute(input, memory_clone).await;
            if result.success {
                tracing::info!(
                    "LLM reflection completed: {} insights generated",
                    result.insights_generated
                );
            } else if let Some(reason) = result.reason {
                tracing::debug!("LLM reflection skipped: {}", reason);
            }
        });
    }
}
