use std::sync::Arc;
use std::time::Duration;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    Extension,
};
use serde::{Deserialize, Serialize};

use crate::api::error::{ApiBody, ApiError, ApiJson};
use crate::api::middleware::Claims;
use crate::api::AppState;
use crate::application::bot::{run_bot_turns_now, spawn_bot_turns, trigger_llm_reflection};
use crate::application::game::{
    CallZapZap, CallZapZapInput, DrawCard, DrawCardInput, GetGameState, GetGameStateInput,
    NextRound, NextRoundInput, PlayCards, PlayCardsInput, SelectHandSize, SelectHandSizeInput,
};
use crate::infrastructure::app_state::GameEvent;

// ============================================================================
// Request/Response DTOs
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct PlayCardsRequest {
    /// Raw values: an id out of the card range is INVALID_CARDS, not an unreadable body
    #[serde(rename = "cardIds")]
    pub card_ids: Option<Vec<serde_json::Value>>,
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

impl ApiBody for PlayCardsRequest {
    const INVALID_CODE: &'static str = "MISSING_CARDS";
    const INVALID_MESSAGE: &'static str = "Card IDs are required";
}

impl ApiBody for DrawCardRequest {
    const INVALID_CODE: &'static str = "INVALID_SOURCE";
    const INVALID_MESSAGE: &'static str = "Source must be \"deck\" or \"played\"";
}

impl ApiBody for SelectHandSizeRequest {
    const INVALID_CODE: &'static str = "INVALID_HAND_SIZE";
    const INVALID_MESSAGE: &'static str = "Hand size must be an integer";
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

/// Node's zapzap contract: `scores` are the running totals after the round, keyed by
/// player index; this round's points go under `roundScores`, the key `/state` uses.
#[derive(Debug, Serialize)]
pub struct ZapZapResponse {
    pub success: bool,
    #[serde(rename = "zapzapSuccess")]
    pub zapzap_success: bool,
    pub counteracted: bool,
    /// Player index of the counteracting player, `null` when none
    #[serde(rename = "counteractedBy")]
    pub counteracted_by: Option<u8>,
    pub scores: std::collections::BTreeMap<String, u16>,
    #[serde(rename = "roundScores")]
    pub round_scores: std::collections::BTreeMap<String, u16>,
    #[serde(rename = "handPoints")]
    pub hand_points: std::collections::BTreeMap<String, u16>,
    #[serde(rename = "callerPoints")]
    pub caller_points: u16,
    #[serde(rename = "gameFinished")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub game_finished: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub winner: Option<ZapZapWinner>,
}

#[derive(Debug, Serialize)]
pub struct ZapZapWinner {
    #[serde(rename = "userId")]
    pub user_id: String,
    #[serde(rename = "playerIndex")]
    pub player_index: u8,
    pub score: u16,
}

/// `[(index, value)]` as a JSON object keyed by the index, like Node's maps
fn index_map(entries: &[(u8, u16)]) -> std::collections::BTreeMap<String, u16> {
    entries.iter().map(|(i, v)| (i.to_string(), *v)).collect()
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
) -> Result<Json<GameStateResponse>, ApiError> {
    let use_case = GetGameState::new(state.user_repo.clone(), state.party_repo.clone());
    let result = use_case
        .execute(GetGameStateInput {
            user_id: claims.user_id.clone(),
            party_id,
        })
        .await?;

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
        let eliminated_players: Vec<u8> = gs
            .scores
            .iter()
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

    // Let the bots play if one is to move (one loop per party)
    spawn_bot_turns(&state, result.party.id.clone(), Duration::from_millis(100));

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
    ApiJson(body): ApiJson<SelectHandSizeRequest>,
) -> Result<Json<SelectHandSizeResponse>, ApiError> {
    let party_id_for_event = party_id.clone();
    let party_id_for_bot = party_id.clone();
    let use_case = SelectHandSize::new(state.party_repo.clone());
    let result = use_case
        .execute(SelectHandSizeInput {
            party_id,
            user_id: claims.user_id.clone(),
            hand_size: body.hand_size,
        })
        .await?;

    // Emit SSE event
    let event = GameEvent::new(
        "gameUpdate",
        Some(party_id_for_event),
        Some(claims.user_id.clone()),
    )
    .with_action("selectHandSize")
    .with_data(serde_json::json!({
        "handSize": body.hand_size
    }));
    state.broadcast_event(event);

    // Let the bots play if one is to move (one loop per party)
    spawn_bot_turns(&state, party_id_for_bot, Duration::from_millis(300));

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
    ApiJson(body): ApiJson<PlayCardsRequest>,
) -> Result<Json<PlayCardsResponse>, ApiError> {
    let raw_ids = body.card_ids.unwrap_or_default();
    if raw_ids.is_empty() {
        return Err(ApiError::bad_request(
            "MISSING_CARDS",
            "Card IDs are required",
        ));
    }
    // An id that is no card id (300, -1, "a") is in no hand: Node's INVALID_CARDS
    let mut card_ids = Vec::with_capacity(raw_ids.len());
    for raw in &raw_ids {
        match raw.as_u64().and_then(|id| u8::try_from(id).ok()) {
            Some(id) => card_ids.push(id),
            None => {
                return Err(ApiError::bad_request(
                    "INVALID_CARDS",
                    format!("Card {raw} not in hand"),
                ))
            }
        }
    }

    let party_id_for_bot = party_id.clone();
    let use_case = PlayCards::new(state.party_repo.clone());
    let result = use_case
        .execute(PlayCardsInput {
            party_id,
            user_id: claims.user_id.clone(),
            card_ids: card_ids.clone(),
        })
        .await?;

    // Emit SSE event
    let event = GameEvent::new(
        "gameUpdate",
        Some(party_id_for_bot.clone()),
        Some(claims.user_id.clone()),
    )
    .with_action("play")
    .with_data(serde_json::json!({
        "cardIds": card_ids
    }));
    state.broadcast_event(event);

    // Let the bots play if one is to move (one loop per party)
    spawn_bot_turns(&state, party_id_for_bot, Duration::from_millis(300));

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
    ApiJson(body): ApiJson<DrawCardRequest>,
) -> Result<Json<DrawCardResponse>, ApiError> {
    if body.source != "deck" && body.source != "played" {
        return Err(ApiError::bad_request(
            DrawCardRequest::INVALID_CODE,
            DrawCardRequest::INVALID_MESSAGE,
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
        .await?;

    // Emit SSE event
    let event = GameEvent::new(
        "gameUpdate",
        Some(party_id_for_bot.clone()),
        Some(claims.user_id.clone()),
    )
    .with_action("draw")
    .with_data(serde_json::json!({
        "source": body.source
    }));
    state.broadcast_event(event);

    // Let the bots play if one is to move (one loop per party)
    spawn_bot_turns(&state, party_id_for_bot, Duration::from_millis(300));

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
) -> Result<Json<ZapZapResponse>, ApiError> {
    let party_id_for_event = party_id.clone();
    let use_case = CallZapZap::new(state.party_repo.clone());
    let result = use_case
        .execute(CallZapZapInput {
            party_id,
            user_id: claims.user_id.clone(),
        })
        .await?;

    // Emit SSE event
    let event = GameEvent::new(
        "gameUpdate",
        Some(party_id_for_event.clone()),
        Some(claims.user_id.clone()),
    )
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
            let game_state = match state_for_reflection
                .party_repo
                .get_game_state(&party_id_for_reflection)
                .await
            {
                Ok(Some(gs)) => gs,
                _ => return,
            };

            // Get players to find caller's index
            let players = match state_for_reflection
                .party_repo
                .get_party_players(&party_id_for_reflection)
                .await
            {
                Ok(p) => p,
                _ => return,
            };

            let caller_idx = players
                .iter()
                .find(|p| p.user_id == user_id_for_reflection)
                .map(|p| p.player_index);

            trigger_llm_reflection(
                &state_for_reflection,
                &party_id_for_reflection,
                game_state.round_number as u32,
                caller_idx,
                counteracted,
            )
            .await;
        });
    }

    let winner = match (result.winner, result.winner_user_id) {
        (Some(player_index), Some(user_id)) => Some(ZapZapWinner {
            user_id,
            player_index,
            score: result
                .total_scores
                .iter()
                .find(|(i, _)| *i == player_index)
                .map(|(_, s)| *s)
                .unwrap_or(0),
        }),
        _ => None,
    };

    Ok(Json(ZapZapResponse {
        success: true,
        zapzap_success: result.success,
        counteracted: result.counteracted,
        counteracted_by: result.counteracted_by,
        scores: index_map(&result.total_scores),
        round_scores: index_map(&result.round_scores),
        hand_points: index_map(&result.hand_points),
        caller_points: result.caller_hand_points,
        game_finished: result.game_finished.then_some(true),
        winner,
    }))
}

/// POST /api/game/:partyId/nextRound - Start next round
pub async fn next_round(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
) -> Result<Json<NextRoundResponse>, ApiError> {
    crate::api::access::require_party_member(&state, &party_id, &claims.user_id).await?;
    let party_id_for_event = party_id.clone();
    let party_id_for_bot = party_id.clone();
    let use_case = NextRound::new(state.party_repo.clone());
    let result = use_case
        .execute(NextRoundInput {
            party_id,
            user_id: claims.user_id.clone(),
        })
        .await?;

    // Emit SSE event
    let action = if result.game_finished {
        "gameFinished"
    } else {
        "roundStarted"
    };
    let event = GameEvent::new(
        "gameUpdate",
        Some(party_id_for_event),
        Some(claims.user_id.clone()),
    )
    .with_action(action)
    .with_data(serde_json::json!({
        "gameFinished": result.game_finished
    }));
    state.broadcast_event(event);

    // starting_player is stored in GameState, not in Round
    let starting_player = result.starting_player;

    // Spawn background task to trigger bot if starting player is a bot
    if !result.game_finished {
        spawn_bot_turns(&state, party_id_for_bot, Duration::from_millis(300));
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
    Extension(claims): Extension<Claims>,
    Path(party_id): Path<String>,
) -> Result<Json<TriggerBotResponse>, (StatusCode, Json<ErrorResponse>)> {
    if let Err(e) =
        crate::api::access::require_party_member(&state, &party_id, &claims.user_id).await
    {
        let (code, details) = (e.code.to_string(), None);
        let body = ErrorResponse {
            error: e.message,
            code,
            details,
        };
        return Err((e.status, Json(body)));
    }
    match run_bot_turns_now(&state, &party_id).await {
        Ok(actions) => Ok(Json(TriggerBotResponse {
            success: true,
            message: format!("Bot trigger completed. Actions taken: {}", actions),
        })),
        Err(error) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                error,
                code: "BOT_ACTION_ERROR".to_string(),
                details: None,
            }),
        )),
    }
}
