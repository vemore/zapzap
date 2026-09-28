//! The turn time limit (GAME_RULES.md "Turn Time Limit"): a party that starts with a limit
//! and at least two humans times its humans' turns; a human past the deadline is ejected
//! for good, a bot takes the seat with its hand and score, the others hear of it
//! (`playerReplaced`), the game goes on, and the ejected human's game counts as a loss.
//! The clock is a `ManualClock` moved on by hand: no test waits the 30 seconds.

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
use zapzap_backend::application::bot::BotRunner;
use zapzap_backend::application::game::{enforce_turn_deadlines, spawn_turn_timer};
use zapzap_backend::domain::entities::{BotDifficulty, PartyStatus, User, UserType};
use zapzap_backend::domain::repositories::{PartyRepository, SeatReplacement, UserRepository};
use zapzap_backend::domain::value_objects::{GameAction, GameState};
use zapzap_backend::infrastructure::app_state::AppState;
use zapzap_backend::infrastructure::bot::card_analyzer::calculate_hand_value;
use zapzap_backend::infrastructure::services::{Clock, ManualClock};

/// The application main.rs serves, on a fresh database, its time read from `clock`, and
/// no pause between two bot actions
async fn test_app(clock: &Arc<ManualClock>) -> (Router, Arc<AppState>) {
    std::env::set_var("DATABASE_URL", "sqlite::memory:");
    std::env::set_var("JWT_SECRET", "test-secret-key");
    std::env::set_var("BOT_ACTION_DELAY_MS", "0");
    let mut state = AppState::new().await.expect("app state");
    state.bot_runner = Arc::new(BotRunner::with_action_delay(Duration::ZERO));
    state.use_clock(clock.clone());
    let state = Arc::new(state);
    (api::build_app(state.clone()), state)
}

async fn send(
    app: &mut Router,
    method: &str,
    path: &str,
    body: Value,
    token: Option<&str>,
) -> (StatusCode, Value) {
    let mut request = Request::builder()
        .method(method)
        .uri(path)
        .header("Content-Type", "application/json");
    if let Some(token) = token {
        request = request.header("Authorization", format!("Bearer {token}"));
    }
    let request = request
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

/// A new account: its token and id
async fn register(app: &mut Router, username: &str) -> (String, String) {
    let (status, body) = send(
        app,
        "POST",
        "/api/auth/register",
        json!({"username": username, "password": "password123"}),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    (
        body["token"].as_str().unwrap().to_string(),
        body["user"]["id"].as_str().unwrap().to_string(),
    )
}

/// The humans of a table: tokens and ids, by seat
struct Humans {
    tokens: Vec<String>,
    ids: Vec<String>,
}

/// A started party with `limit` seconds per turn: the owner on seat 0, `humans` more
/// players, then a bot per difficulty of `bots`
async fn timed_party(
    app: &mut Router,
    state: &AppState,
    prefix: &str,
    humans: usize,
    bots: &[BotDifficulty],
    limit: u32,
) -> (String, Humans) {
    let (owner, owner_id) = register(app, &format!("{prefix}_owner")).await;
    let (status, body) = send(
        app,
        "POST",
        "/api/party",
        json!({
            "name": format!("{prefix} party"),
            "settings": {
                "playerCount": (1 + humans + bots.len()).max(3),
                "turnTimeLimit": limit
            }
        }),
        Some(&owner),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(body["party"]["settings"]["turnTimeLimit"], limit);
    let party_id = body["party"]["id"].as_str().unwrap().to_string();

    let mut seated = Humans {
        tokens: vec![owner.clone()],
        ids: vec![owner_id],
    };
    for i in 0..humans {
        let (token, id) = register(app, &format!("{prefix}_h{i}")).await;
        let (status, body) = send(
            app,
            "POST",
            &format!("/api/party/{party_id}/join"),
            json!({}),
            Some(&token),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{body}");
        seated.tokens.push(token);
        seated.ids.push(id);
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
            Some(&owner),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{body}");
    }
    let (status, body) = send(
        app,
        "POST",
        &format!("/api/party/{party_id}/start"),
        json!({}),
        Some(&owner),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    (party_id, seated)
}

async fn get_state(app: &mut Router, party_id: &str, token: &str) -> (StatusCode, Value) {
    send(
        app,
        "GET",
        &format!("/api/game/{party_id}/state"),
        Value::Null,
        Some(token),
    )
    .await
}

async fn post(
    app: &mut Router,
    party_id: &str,
    route: &str,
    body: Value,
    token: &str,
) -> (StatusCode, Value) {
    send(
        app,
        "POST",
        &format!("/api/game/{party_id}/{route}"),
        body,
        Some(token),
    )
    .await
}

async fn stored_state(state: &AppState, party_id: &str) -> GameState {
    state
        .party_repo
        .get_game_state(party_id)
        .await
        .unwrap()
        .expect("game state")
}

async fn seat_user(state: &AppState, party_id: &str, seat: u8) -> User {
    let players = state.party_repo.get_party_players(party_id).await.unwrap();
    let player = players
        .iter()
        .find(|p| p.player_index == seat)
        .expect("seat taken");
    state
        .user_repo
        .find_by_id(&player.user_id)
        .await
        .unwrap()
        .expect("user")
}

async fn party_status(state: &AppState, party_id: &str) -> PartyStatus {
    state
        .party_repo
        .find_by_id(party_id)
        .await
        .unwrap()
        .expect("party")
        .status
}

/// `(finish_position, is_winner, final_score, rounds_played)` of a user's result
async fn result_of(
    state: &AppState,
    party_id: &str,
    user_id: &str,
) -> Option<(i64, i64, i64, i64)> {
    sqlx::query_as(
        "SELECT finish_position, is_winner, final_score, rounds_played \
         FROM player_game_results WHERE party_id = ? AND user_id = ?",
    )
    .bind(party_id)
    .bind(user_id)
    .fetch_optional(&state.db)
    .await
    .unwrap()
}

/// Open the event stream of `token`, once its `connected` event came in
async fn open_sse(app: &mut Router, token: &str) -> Body {
    let request = Request::builder()
        .uri(format!("/suscribeupdate?token={token}"))
        .body(Body::empty())
        .unwrap();
    let response = ServiceExt::<Request<Body>>::ready(app)
        .await
        .unwrap()
        .call(request)
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let mut body = response.into_body();
    read_sse_until(&mut body, "connected").await;
    body
}

/// Read the SSE body until `sentinel` shows up; returns everything read
async fn read_sse_until(body: &mut Body, sentinel: &str) -> String {
    let mut text = String::new();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !text.contains(sentinel) {
        let frame = tokio::time::timeout_at(deadline, body.frame())
            .await
            .unwrap_or_else(|_| panic!("no {sentinel} within 10 s; read: {text}"))
            .expect("the SSE stream ended")
            .unwrap();
        if let Ok(data) = frame.into_data() {
            text.push_str(&String::from_utf8_lossy(&data));
        }
    }
    text
}

/// Wait (at most `within`) for `party_id` to be finished
async fn wait_finished(state: &AppState, party_id: &str, within: Duration) {
    let deadline = tokio::time::Instant::now() + within;
    while party_status(state, party_id).await != PartyStatus::Finished {
        assert!(
            tokio::time::Instant::now() < deadline,
            "the game did not end: {:?}",
            stored_state(state, party_id).await.current_action
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}

#[tokio::test]
async fn test_create_party_offers_off_30_60_and_120_seconds_per_turn() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, _) = test_app(&clock).await;
    let (owner, _) = register(&mut app, "limits").await;
    for limit in [0, 30, 60, 120] {
        let (status, body) = send(
            &mut app,
            "POST",
            "/api/party",
            json!({"name": "Timed", "settings": {"playerCount": 3, "turnTimeLimit": limit}}),
            Some(&owner),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{limit}: {body}");
        assert_eq!(body["party"]["settings"]["turnTimeLimit"], limit);
    }
    for limit in [45, 90, 600] {
        let (status, body) = send(
            &mut app,
            "POST",
            "/api/party",
            json!({"name": "Timed", "settings": {"playerCount": 3, "turnTimeLimit": limit}}),
            Some(&owner),
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{limit}: {body}");
        assert_eq!(body["code"], "VALIDATION_ERROR");
        assert_eq!(
            body["error"],
            "Turn time limit must be 0 (off), 30, 60 or 120 seconds"
        );
    }
}

#[tokio::test]
async fn test_a_late_human_is_replaced_by_a_bot_and_the_game_plays_to_its_end() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    // The owner (seat 0) and Bea (seat 1), humans; a bot on seat 2
    let (party_id, humans) =
        timed_party(&mut app, &state, "late", 1, &[BotDifficulty::Hard], 30).await;
    let (owner, bea) = (&humans.tokens[0], &humans.tokens[1]);
    let owner_id = &humans.ids[0];
    let mut bea_stream = open_sse(&mut app, bea).await;
    let mut owner_stream = open_sse(&mut app, owner).await;

    let (_, body) = get_state(&mut app, &party_id, bea).await;
    assert_eq!(body["gameState"]["turnTimeLimit"], 30, "{body}");
    assert_eq!(body["gameState"]["currentTurn"], 0);
    // Close to 100: the game ends in a round or two
    let mut gs = stored_state(&state, &party_id).await;
    gs.scores[..3].copy_from_slice(&[90, 90, 90]);
    state
        .party_repo
        .save_game_state(&party_id, &gs)
        .await
        .unwrap();

    // 29 s: still in time; 30 s: out of time
    clock.advance(Duration::from_secs(29));
    assert!(enforce_turn_deadlines(&state).await.is_empty());
    assert_eq!(seat_user(&state, &party_id, 0).await.id, *owner_id);
    clock.advance(Duration::from_secs(1));
    let ejections = enforce_turn_deadlines(&state).await;
    assert_eq!(ejections.len(), 1, "{ejections:?}");
    assert_eq!(ejections[0].player_index, 0);
    assert_eq!(ejections[0].human_id, *owner_id);

    // A bot holds the seat, and the party is Bea's now
    let stand_in = seat_user(&state, &party_id, 0).await;
    assert_eq!(stand_in.user_type, UserType::Bot);
    assert_eq!(stand_in.id, ejections[0].bot_id);
    let party = state
        .party_repo
        .find_by_id(&party_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(party.owner_id, humans.ids[1]);

    // Bea hears of it, and so does the ejected owner
    for stream in [&mut bea_stream, &mut owner_stream] {
        let events = read_sse_until(stream, "playerReplaced").await;
        assert!(events.contains(r#""playerIndex":0"#), "{events}");
        assert!(
            events.contains(&format!(r#""replacedUserId":"{owner_id}""#)),
            "{events}"
        );
        assert!(
            events.contains(&format!(r#""botId":"{}""#, stand_in.id)),
            "{events}"
        );
    }

    // The game plays on to its end: the bots play, Bea plays her turns
    let deadline = tokio::time::Instant::now() + Duration::from_secs(60);
    loop {
        assert!(
            tokio::time::Instant::now() < deadline,
            "the game did not end"
        );
        let (status, body) = get_state(&mut app, &party_id, bea).await;
        assert_eq!(status, StatusCode::OK, "{body}");
        if body["party"]["status"] == "finished" {
            break;
        }
        let game = &body["gameState"];
        let action = game["currentAction"].as_str().unwrap_or_default();
        if action == "finished" {
            // Bea deals the next round (the bots do once she is out; a race is harmless)
            post(&mut app, &party_id, "nextRound", json!({}), bea).await;
        } else if game["currentTurn"] == 1 {
            match action {
                "selectHandSize" => {
                    post(
                        &mut app,
                        &party_id,
                        "selectHandSize",
                        json!({"handSize": 4}),
                        bea,
                    )
                    .await;
                }
                "play" => {
                    let hand: Vec<u8> = serde_json::from_value(game["playerHand"].clone()).unwrap();
                    if calculate_hand_value(&hand) <= 5 {
                        post(&mut app, &party_id, "zapzap", json!({}), bea).await;
                    } else {
                        let highest = *hand
                            .iter()
                            .max_by_key(|&&c| calculate_hand_value(&[c]))
                            .unwrap();
                        post(
                            &mut app,
                            &party_id,
                            "play",
                            json!({"cardIds": [highest]}),
                            bea,
                        )
                        .await;
                    }
                }
                "draw" => {
                    post(&mut app, &party_id, "draw", json!({"source": "deck"}), bea).await;
                }
                _ => {}
            }
        }
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    assert_eq!(party_status(&state, &party_id).await, PartyStatus::Finished);
    // Three seats ranked 1-3; the ejected owner after them, a loss
    let (position, is_winner, _, _) = result_of(&state, &party_id, owner_id).await.unwrap();
    assert_eq!((position, is_winner), (4, 0));
    assert!(result_of(&state, &party_id, &stand_in.id).await.is_some());
}

#[tokio::test]
async fn test_an_ejected_human_can_no_longer_play_and_the_game_counts_as_a_loss() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    let (party_id, humans) =
        timed_party(&mut app, &state, "loss", 1, &[BotDifficulty::Hard], 60).await;
    let (owner, owner_id) = (&humans.tokens[0], &humans.ids[0]);

    // The owner is to play, holding the lowest hand there is; the others are near 100
    let mut gs = stored_state(&state, &party_id).await;
    gs.current_action = GameAction::Play;
    for (seat, hand) in [&[0u8][..], &[12, 25], &[11, 24]].iter().enumerate() {
        gs.hands[seat] = smallvec::SmallVec::from_slice(hand);
    }
    gs.scores[..3].copy_from_slice(&[0, 95, 95]);
    state
        .party_repo
        .save_game_state(&party_id, &gs)
        .await
        .unwrap();

    clock.advance(Duration::from_secs(61));
    let ejections = enforce_turn_deadlines(&state).await;
    assert_eq!(ejections.len(), 1);
    // No free bot in this database: one was created to take the seat
    let stand_in = seat_user(&state, &party_id, 0).await;
    assert_eq!(stand_in.bot_difficulty, Some(BotDifficulty::Medium));

    // Every move of the ejected owner is refused, and so is the state
    let (status, body) = get_state(&mut app, &party_id, owner).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "NOT_IN_PARTY");
    let (status, body) = post(&mut app, &party_id, "play", json!({"cardIds": [0]}), owner).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    let (status, _) = post(&mut app, &party_id, "zapzap", json!({}), owner).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = post(&mut app, &party_id, "nextRound", json!({}), owner).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // A loss at once, before the game is over
    let (status, body) = send(&mut app, "GET", "/api/stats/me", Value::Null, Some(owner)).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["stats"]["gamesPlayed"], 1, "{body}");
    assert_eq!(body["stats"]["losses"], 1, "{body}");

    // The bot calls ZapZap with the owner's hand and wins the game with the owner's seat
    wait_finished(&state, &party_id, Duration::from_secs(10)).await;
    let (winner,): (String,) =
        sqlx::query_as("SELECT winner_user_id FROM game_results WHERE party_id = ?")
            .bind(&party_id)
            .fetch_one(&state.db)
            .await
            .unwrap();
    assert_eq!(winner, stand_in.id);
    assert_eq!(
        result_of(&state, &party_id, &stand_in.id).await.unwrap().1,
        1
    );

    // The owner's game is still a loss: after the three seats, the score and the round
    // the owner left with
    assert_eq!(
        result_of(&state, &party_id, owner_id).await,
        Some((4, 0, 0, 1))
    );
    let (_, body) = send(&mut app, "GET", "/api/stats/me", Value::Null, Some(owner)).await;
    assert_eq!(
        (
            &body["stats"]["gamesPlayed"],
            &body["stats"]["wins"],
            &body["stats"]["losses"]
        ),
        (&json!(1), &json!(0), &json!(1)),
        "{body}"
    );
    // The game is in the owner's history
    let (status, body) = send(&mut app, "GET", "/api/history", Value::Null, Some(owner)).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert!(body.to_string().contains(&party_id), "{body}");
}

#[tokio::test]
async fn test_a_party_started_with_one_human_runs_no_clock() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    let (party_id, humans) = timed_party(
        &mut app,
        &state,
        "alone",
        0,
        &[BotDifficulty::Hard, BotDifficulty::Hard],
        30,
    )
    .await;
    let owner = &humans.tokens[0];

    let (_, body) = get_state(&mut app, &party_id, owner).await;
    assert_eq!(body["gameState"]["turnTimeLimit"], 0, "{body}");
    assert_eq!(body["gameState"]["turnDeadline"], Value::Null, "{body}");

    clock.advance(Duration::from_secs(3600));
    assert!(enforce_turn_deadlines(&state).await.is_empty());
    assert_eq!(seat_user(&state, &party_id, 0).await.id, humans.ids[0]);
    let (status, _) = post(
        &mut app,
        &party_id,
        "selectHandSize",
        json!({"handSize": 5}),
        owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn test_the_turn_deadline_is_in_the_state_and_restarts_only_with_the_next_turn() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    let (party_id, humans) =
        timed_party(&mut app, &state, "refresh", 1, &[BotDifficulty::Hard], 30).await;
    let (owner, bea) = (&humans.tokens[0], &humans.tokens[1]);
    let started = clock.now_millis();

    // Server-side: every player reads the same deadline, a refresh reads it again
    let (_, body) = get_state(&mut app, &party_id, owner).await;
    let game = &body["gameState"];
    assert_eq!(game["turnDeadline"], started + 30_000, "{body}");
    assert_eq!(game["serverTime"], started);
    let (_, body) = get_state(&mut app, &party_id, bea).await;
    assert_eq!(
        body["gameState"]["turnDeadline"],
        started + 30_000,
        "{body}"
    );

    // The hand-size choice and the play are the owner's turn: the deadline stands
    clock.advance(Duration::from_secs(10));
    let (status, _) = post(
        &mut app,
        &party_id,
        "selectHandSize",
        json!({"handSize": 5}),
        owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, body) = get_state(&mut app, &party_id, owner).await;
    assert_eq!(
        body["gameState"]["turnDeadline"],
        started + 30_000,
        "{body}"
    );
    let card = body["gameState"]["playerHand"][0].clone();
    clock.advance(Duration::from_secs(2));
    let (status, _) = post(
        &mut app,
        &party_id,
        "play",
        json!({"cardIds": [card]}),
        owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        stored_state(&state, &party_id).await.turn_clock.deadline,
        Some(started + 30_000)
    );

    // The draw ends it: Bea's turn has its own 30 s from then
    clock.advance(Duration::from_secs(2));
    let (status, _) = post(
        &mut app,
        &party_id,
        "draw",
        json!({"source": "deck"}),
        owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, body) = get_state(&mut app, &party_id, bea).await;
    assert_eq!(body["gameState"]["currentTurn"], 1);
    assert_eq!(
        body["gameState"]["turnDeadline"],
        started + 14_000 + 30_000,
        "{body}"
    );
}

#[tokio::test]
async fn test_the_clock_covers_the_whole_turn_hand_size_choice_included() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    let (party_id, humans) =
        timed_party(&mut app, &state, "whole", 1, &[BotDifficulty::Hard], 30).await;
    let owner = &humans.tokens[0];

    clock.advance(Duration::from_secs(15));
    let (status, _) = post(
        &mut app,
        &party_id,
        "selectHandSize",
        json!({"handSize": 5}),
        owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, body) = get_state(&mut app, &party_id, owner).await;
    let card = body["gameState"]["playerHand"][0].clone();
    clock.advance(Duration::from_secs(10));
    let (status, _) = post(
        &mut app,
        &party_id,
        "play",
        json!({"cardIds": [card]}),
        owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // 30 s after the turn began, the draw still to make: out of time
    clock.advance(Duration::from_secs(5));
    let ejections = enforce_turn_deadlines(&state).await;
    assert_eq!(ejections.len(), 1);
    let (status, _) = post(
        &mut app,
        &party_id,
        "draw",
        json!({"source": "deck"}),
        owner,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn test_a_move_read_before_an_ejection_is_refused() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    let (party_id, humans) =
        timed_party(&mut app, &state, "raced", 1, &[BotDifficulty::Hard], 30).await;
    let read = state
        .party_repo
        .get_versioned_game_state(&party_id)
        .await
        .unwrap()
        .unwrap();

    clock.advance(Duration::from_secs(30));
    assert_eq!(enforce_turn_deadlines(&state).await.len(), 1);

    // The owner's move, read before the ejection, loses: the seat stays the bot's
    let err = state
        .party_repo
        .update_game_state(&party_id, &read.state, read.version)
        .await
        .unwrap_err();
    assert!(err.is_conflict(), "{err}");
    let gs = stored_state(&state, &party_id).await;
    assert!(!gs.is_timed(0));
    assert_ne!(seat_user(&state, &party_id, 0).await.id, humans.ids[0]);
}

#[tokio::test]
async fn test_an_ejection_that_loses_the_race_to_a_move_writes_nothing() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    let (party_id, humans) =
        timed_party(&mut app, &state, "intime", 1, &[BotDifficulty::Hard], 30).await;
    let (owner, owner_id) = (&humans.tokens[0], &humans.ids[0]);
    let bot = User::new_bot("standin".into(), "standin".into(), BotDifficulty::Medium);
    state.user_repo.save(&bot).await.unwrap();

    // The ejection read the state; the owner's move came in before it wrote
    let read = state
        .party_repo
        .get_versioned_game_state(&party_id)
        .await
        .unwrap()
        .unwrap();
    let (status, _) = post(
        &mut app,
        &party_id,
        "selectHandSize",
        json!({"handSize": 5}),
        owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let mut untimed = read.state.clone();
    untimed.untime_seat(0);
    let err = state
        .party_repo
        .replace_player(&SeatReplacement {
            party_id: &party_id,
            player_index: 0,
            human_id: owner_id,
            bot_id: &bot.id,
            new_owner_id: Some(&humans.ids[1]),
            state: &untimed,
            expected_version: read.version,
            seat_count: 3,
        })
        .await
        .unwrap_err();
    assert!(err.is_conflict(), "{err}");

    // Nothing of it was written: seat, clock, owner, results
    assert_eq!(seat_user(&state, &party_id, 0).await.id, *owner_id);
    let gs = stored_state(&state, &party_id).await;
    assert!(gs.is_timed(0));
    assert_eq!(gs.current_action, GameAction::Play);
    let party = state
        .party_repo
        .find_by_id(&party_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(party.owner_id, *owner_id);
    assert_eq!(result_of(&state, &party_id, owner_id).await, None);
}

#[tokio::test]
async fn test_the_turn_timer_task_ejects_on_its_own() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    let (party_id, humans) =
        timed_party(&mut app, &state, "task", 1, &[BotDifficulty::Hard], 30).await;
    let timer = spawn_turn_timer(state.clone(), Duration::from_millis(10));

    clock.advance(Duration::from_secs(31));
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while seat_user(&state, &party_id, 0).await.id == humans.ids[0] {
        assert!(tokio::time::Instant::now() < deadline, "nobody was ejected");
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    timer.abort();
    assert_eq!(
        seat_user(&state, &party_id, 0).await.user_type,
        UserType::Bot
    );
}
