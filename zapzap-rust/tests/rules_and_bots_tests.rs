//! GAME_RULES.md where the Rust code used to disagree (eliminated starter, tied lowest
//! hands, a card named twice in a play), and the bot loop: one at a time per party, one
//! strategy per bot for the whole game.

use std::sync::Arc;
use std::time::Duration;

use axum::{
    body::Body,
    http::{Request, StatusCode},
    Router,
};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use tower::{Service, ServiceExt};

use zapzap_backend::api;
use zapzap_backend::application::bot::{trigger_bot_turns, BotBrain, Roster};
use zapzap_backend::domain::entities::{BotDifficulty, User};
use zapzap_backend::domain::repositories::{PartyRepository, UserRepository};
use zapzap_backend::domain::value_objects::{GameAction, GameState};
use zapzap_backend::infrastructure::app_state::AppState;

async fn test_app() -> (Router, Arc<AppState>) {
    std::env::set_var("DATABASE_URL", "sqlite::memory:");
    std::env::set_var("JWT_SECRET", "test-secret-key");
    // LLM bot memories land in a scratch directory, not in the repository's data/
    std::env::set_var(
        "BOT_STRATEGIES_DIR",
        std::env::temp_dir().join("zapzap-test-bot-strategies"),
    );
    let state = Arc::new(AppState::new().await.expect("app state"));
    let app = Router::new()
        .nest("/api", api::routes::create_api_router(state.clone()))
        .with_state(state.clone());
    (app, state)
}

async fn send(
    app: &mut Router,
    method: &str,
    path: &str,
    body: Value,
    token: &str,
) -> (StatusCode, Value) {
    let request = Request::builder()
        .method(method)
        .uri(path)
        .header("Content-Type", "application/json")
        .header("Authorization", format!("Bearer {token}"))
        .body(if method == "GET" {
            Body::empty()
        } else {
            Body::from(body.to_string())
        })
        .unwrap();
    let response = ServiceExt::<Request<Body>>::ready(app)
        .await
        .unwrap()
        .call(request)
        .await
        .unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

async fn register(app: &mut Router, username: &str) -> String {
    let request = Request::builder()
        .method("POST")
        .uri("/api/auth/register")
        .header("Content-Type", "application/json")
        .body(Body::from(
            json!({"username": username, "password": "password123"}).to_string(),
        ))
        .unwrap();
    let response = ServiceExt::<Request<Body>>::ready(app)
        .await
        .unwrap()
        .call(request)
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::CREATED);
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let body: Value = serde_json::from_slice(&bytes).unwrap();
    body["token"].as_str().unwrap().to_string()
}

/// A started party: the owner, then `humans` more players, then `bots`; returns the
/// party id and the humans' tokens by seat
async fn started_party(
    app: &mut Router,
    state: &AppState,
    prefix: &str,
    humans: usize,
    bots: &[BotDifficulty],
) -> (String, Vec<String>) {
    let owner = register(app, &format!("{prefix}_owner")).await;
    let (status, body) = send(
        app,
        "POST",
        "/api/party",
        json!({"name": format!("{prefix} party")}),
        &owner,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let party_id = body["party"]["id"].as_str().unwrap().to_string();

    let mut tokens = vec![owner.clone()];
    for i in 0..humans {
        let token = register(app, &format!("{prefix}_h{i}")).await;
        let (status, body) = send(
            app,
            "POST",
            &format!("/api/party/{party_id}/join"),
            json!({}),
            &token,
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{body}");
        tokens.push(token);
    }
    for (i, difficulty) in bots.iter().enumerate() {
        let id = uuid::Uuid::new_v4().to_string();
        let bot = User::new_bot(id.clone(), format!("{prefix}_bot{i}"), *difficulty);
        state.user_repo.save(&bot).await.unwrap();
        let (status, body) = send(
            app,
            "POST",
            &format!("/api/party/{party_id}/bots"),
            json!({"botId": id}),
            &owner,
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{body}");
    }
    let (status, body) = send(
        app,
        "POST",
        &format!("/api/party/{party_id}/start"),
        json!({}),
        &owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    (party_id, tokens)
}

async fn game_state(state: &AppState, party_id: &str) -> GameState {
    state
        .party_repo
        .get_game_state(party_id)
        .await
        .unwrap()
        .expect("game state")
}

async fn save_game_state(state: &AppState, party_id: &str, gs: &GameState) {
    state
        .party_repo
        .save_game_state(party_id, gs)
        .await
        .unwrap();
}

fn set_hands(gs: &mut GameState, hands: &[&[u8]]) {
    for (i, hand) in hands.iter().enumerate() {
        gs.hands[i] = smallvec::SmallVec::from_slice(hand);
    }
}

// ============================================================================
// Rules
// ============================================================================

#[tokio::test]
async fn test_play_naming_a_card_twice_is_refused_and_plays_nothing() {
    let (mut app, state) = test_app().await;
    let (party_id, tokens) = started_party(&mut app, &state, "twice", 2, &[]).await;

    let mut gs = game_state(&state, &party_id).await;
    set_hands(&mut gs, &[&[5, 18, 30], &[1, 2, 3], &[40, 41, 42]]);
    gs.current_turn = 0;
    gs.current_action = GameAction::Play;
    save_game_state(&state, &party_id, &gs).await;
    let before = game_state(&state, &party_id).await;

    for cards in [json!([5, 5]), json!([5, 5, 5]), json!([5, 18, 5])] {
        let (status, body) = send(
            &mut app,
            "POST",
            &format!("/api/game/{party_id}/play"),
            json!({ "cardIds": cards }),
            &tokens[0],
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{cards}: {body}");
        assert_eq!(body["code"], "INVALID_CARDS", "{cards}: {body}");
    }

    // Nothing was played: same hand, same piles, still the play phase
    let after = game_state(&state, &party_id).await;
    assert_eq!(after.hands[0].as_slice(), before.hands[0].as_slice());
    assert_eq!(after.cards_played, before.cards_played);
    assert_eq!(after.last_cards_played, before.last_cards_played);
    assert_eq!(after.current_action, GameAction::Play);
    assert_eq!(after.current_turn, 0);
}

/// End the round with `eliminated` out of the game and `starter` having started it,
/// call nextRound, and return the new round's starter as the response gives it
async fn next_starter(starter: u8, eliminated: &[u8]) -> (u8, Value) {
    let (mut app, state) = test_app().await;
    let (party_id, tokens) =
        started_party(&mut app, &state, &format!("rot{starter}"), 3, &[]).await;

    let mut gs = game_state(&state, &party_id).await;
    for &p in eliminated {
        gs.scores[p as usize] = 120;
        gs.eliminate_player(p);
    }
    gs.starting_player = starter;
    gs.current_turn = starter;
    gs.current_action = GameAction::Finished;
    save_game_state(&state, &party_id, &gs).await;

    let (status, body) = send(
        &mut app,
        "POST",
        &format!("/api/game/{party_id}/nextRound"),
        json!({}),
        &tokens[0],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let starting = body["startingPlayer"].as_u64().unwrap() as u8;

    let gs = game_state(&state, &party_id).await;
    assert_eq!(gs.starting_player, starting);
    assert_eq!(gs.current_turn, starting, "the starter picks the hand size");
    assert_eq!(gs.current_action, GameAction::SelectHandSize);
    for &p in eliminated {
        assert!(
            gs.hands[p as usize].is_empty(),
            "eliminated {p} gets no cards"
        );
    }
    (starting, body)
}

#[tokio::test]
async fn test_eliminated_player_never_starts_a_round() {
    // Seat 1 is next in line after seat 0 but eliminated: seat 2 starts
    let (starter, body) = next_starter(0, &[1]).await;
    assert_eq!(starter, 2, "{body}");
    // Several eliminated seats in a row are all skipped
    let (starter, body) = next_starter(0, &[1, 2]).await;
    assert_eq!(starter, 3, "{body}");
}

#[tokio::test]
async fn test_starter_rotation_wraps_to_seat_zero() {
    // From the last seat the rotation wraps to seat 0 …
    let (starter, body) = next_starter(3, &[]).await;
    assert_eq!(starter, 0, "{body}");
    // … and past it when seat 0 is out
    let (starter, body) = next_starter(3, &[0]).await;
    assert_eq!(starter, 1, "{body}");
}

#[tokio::test]
async fn test_tied_lowest_hands_all_score_zero() {
    let (mut app, state) = test_app().await;
    let (party_id, tokens) = started_party(&mut app, &state, "tie", 3, &[]).await;

    // Caller 0 holds 4 (2♠ 2♥); players 1 (A♠ A♥) and 2 (A♣ Joker A♦) tie at 2 points,
    // the lowest; player 3 holds K♠ = 13
    let mut gs = game_state(&state, &party_id).await;
    set_hands(&mut gs, &[&[1, 14], &[0, 13], &[26, 52, 39], &[12]]);
    gs.current_turn = 0;
    gs.current_action = GameAction::Play;
    save_game_state(&state, &party_id, &gs).await;

    let (status, body) = send(
        &mut app,
        "POST",
        &format!("/api/game/{party_id}/zapzap"),
        json!({}),
        &tokens[0],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["counteracted"], true);
    // Both tied players score 0 (the Joker of a lowest hand counts 0); the caller takes
    // 4 + (4 − 1) × 5
    assert_eq!(
        body["roundScores"],
        json!({"0": 19, "1": 0, "2": 0, "3": 13}),
        "{body}"
    );
}

// ============================================================================
// Bots
// ============================================================================

#[tokio::test]
async fn test_concurrent_triggers_run_one_bot_loop() {
    let (mut app, state) = test_app().await;
    let (party_id, tokens) = started_party(
        &mut app,
        &state,
        "conc",
        0,
        &[BotDifficulty::Easy, BotDifficulty::Easy],
    )
    .await;

    // Bot 1 is to play; no hand is low enough for an Easy ZapZap
    let mut gs = game_state(&state, &party_id).await;
    set_hands(
        &mut gs,
        &[&[9, 10, 11, 12], &[22, 23, 24, 25], &[35, 36, 37, 38]],
    );
    gs.current_turn = 1;
    gs.current_action = GameAction::Play;
    save_game_state(&state, &party_id, &gs).await;
    let mut events = state.event_sender.new_receiver();

    // Several state polls and direct triggers at once
    let mut polls = Vec::new();
    for _ in 0..6 {
        let mut app = app.clone();
        let (path, token) = (format!("/api/game/{party_id}/state"), tokens[0].clone());
        polls.push(tokio::spawn(async move {
            send(&mut app, "GET", &path, json!({}), &token).await.0
        }));
    }
    let triggers: Vec<_> = (0..6)
        .map(|_| {
            let (state, party_id) = (state.clone(), party_id.clone());
            tokio::spawn(async move { trigger_bot_turns(&state, &party_id).await })
        })
        .collect();
    for poll in polls {
        assert_eq!(poll.await.unwrap(), StatusCode::OK);
    }
    for trigger in triggers {
        trigger.await.unwrap().expect("bot loop");
    }

    // Wait for the human's turn, then for the polls' delayed triggers to settle
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        let gs = game_state(&state, &party_id).await;
        if gs.current_turn == 0 && gs.current_action == GameAction::Play {
            break;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "bots never handed over"
        );
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    tokio::time::sleep(Duration::from_millis(600)).await;

    // Exactly one play and one draw per bot, in turn order
    let mut bot_actions = Vec::new();
    while let Ok(event) = events.try_recv() {
        if event.data.get("isBot") == Some(&json!(true)) {
            bot_actions.push(event.action.unwrap_or_default());
        }
    }
    assert_eq!(bot_actions, ["play", "draw", "play", "draw"]);
}

fn same_brain(a: &BotBrain, b: &BotBrain) -> bool {
    match (a, b) {
        (BotBrain::Rules(a), BotBrain::Rules(b)) => Arc::ptr_eq(a, b),
        (BotBrain::Llm(a), BotBrain::Llm(b)) => Arc::ptr_eq(a, b),
        _ => false,
    }
}

#[tokio::test]
async fn test_a_bot_keeps_its_strategy_for_the_game() {
    let (_, state) = test_app().await;
    let mut party_a = Roster::default();
    let mut party_b = Roster::default();

    let play = party_a
        .brain(&state, "thibot", Some(BotDifficulty::Thibot))
        .await;
    let draw = party_a
        .brain(&state, "thibot", Some(BotDifficulty::Thibot))
        .await;
    // The instance that chose the play is the one asked for the draw (and the next turns)
    assert!(same_brain(&play, &draw));

    // Another bot, or the same bot in another party, has its own
    let vince = party_a
        .brain(&state, "vince", Some(BotDifficulty::HardVince))
        .await;
    assert!(!same_brain(&play, &vince));
    let elsewhere = party_b
        .brain(&state, "thibot", Some(BotDifficulty::Thibot))
        .await;
    assert!(!same_brain(&play, &elsewhere));

    let llm = party_a.brain(&state, "llm", Some(BotDifficulty::Llm)).await;
    let llm_again = party_a.brain(&state, "llm", Some(BotDifficulty::Llm)).await;
    assert!(same_brain(&llm, &llm_again));
}
