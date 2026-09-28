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

mod common;

use common::{After, Interleaved};
use zapzap_backend::api;
use zapzap_backend::application::bot::BotRunner;
use zapzap_backend::application::game::{
    enforce_turn_deadlines, extend_turn_deadlines_after_downtime, spawn_turn_timer, CallZapZap,
    CallZapZapInput, EjectLatePlayer, PlayCards, PlayCardsError, PlayCardsInput,
};
use zapzap_backend::domain::entities::{BotDifficulty, PartyStatus, User, UserType};
use zapzap_backend::domain::repositories::{
    AccountDeletion, PartyRepository, SeatReplacement, UserRepository,
};
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

/// Every seat of `party_id` has its game result written
async fn results_written(state: &AppState, party_id: &str) -> bool {
    let (seats, results): (i64, i64) = sqlx::query_as(
        "SELECT (SELECT COUNT(*) FROM party_players WHERE party_id = ?1), \
                (SELECT COUNT(*) FROM player_game_results pgr JOIN party_players pp \
                 ON pp.party_id = pgr.party_id AND pp.user_id = pgr.user_id \
                 WHERE pgr.party_id = ?1)",
    )
    .bind(party_id)
    .fetch_one(&state.db)
    .await
    .unwrap();
    results == seats
}

/// Wait (at most `within`) for `party_id` to be finished and its results written (the
/// party is finished first, the results just after)
async fn wait_finished(state: &AppState, party_id: &str, within: Duration) {
    let deadline = tokio::time::Instant::now() + within;
    while party_status(state, party_id).await != PartyStatus::Finished
        || !results_written(state, party_id).await
    {
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
    wait_finished(&state, &party_id, Duration::from_secs(10)).await;
    // Three seats ranked 1-3; the ejected owner after them, a loss
    let (position, is_winner, _, _) = result_of(&state, &party_id, owner_id).await.unwrap();
    assert_eq!((position, is_winner), (4, 0));
    assert!(result_of(&state, &party_id, &stand_in.id).await.is_some());
}

#[tokio::test]
async fn test_an_ejected_human_can_no_longer_play() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    let (party_id, humans) =
        timed_party(&mut app, &state, "barred", 1, &[BotDifficulty::Hard], 60).await;
    let (owner, bea) = (&humans.tokens[0], &humans.tokens[1]);

    // The owner played and is to draw; then comes Bea, a human: the game waits on her
    let mut gs = stored_state(&state, &party_id).await;
    gs.current_action = GameAction::Draw;
    state
        .party_repo
        .save_game_state(&party_id, &gs)
        .await
        .unwrap();
    clock.advance(Duration::from_secs(60));
    assert_eq!(enforce_turn_deadlines(&state).await.len(), 1);
    // The bot draws in the owner's place
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while stored_state(&state, &party_id).await.current_turn != 1 {
        assert!(
            tokio::time::Instant::now() < deadline,
            "the bot did not draw"
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
    }

    // Every move of the ejected owner is refused, and so is the state
    let (status, body) = get_state(&mut app, &party_id, owner).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "NOT_IN_PARTY");
    for (route, body) in [
        ("selectHandSize", json!({"handSize": 5})),
        ("play", json!({"cardIds": [0]})),
        ("draw", json!({"source": "deck"})),
        ("zapzap", json!({})),
        ("nextRound", json!({})),
    ] {
        let (status, answer) = post(&mut app, &party_id, route, body, owner).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{route}: {answer}");
        assert_eq!(answer["code"], "NOT_IN_PARTY", "{route}: {answer}");
    }
    // Bea plays on
    let (status, body) = get_state(&mut app, &party_id, bea).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["gameState"]["currentTurn"], 1);
    assert_eq!(body["party"]["status"], "playing");
}

#[tokio::test]
async fn test_an_ejected_humans_game_is_a_loss_whatever_the_bot_does() {
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

    // A loss at once: the game counts before it is over
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
    // No bot is free: the ejection would create this one with the seat
    let bot = User::new_bot("standin".into(), "standin".into(), BotDifficulty::Medium);

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
            new_bot: Some(&bot),
            new_owner_id: Some(&humans.ids[1]),
            state: &untimed,
            expected_version: read.version,
            seat_count: 3,
        })
        .await
        .unwrap_err();
    assert!(err.is_conflict(), "{err}");

    // Nothing of it was written: seat, clock, owner, results, and no bot was created
    assert_eq!(seat_user(&state, &party_id, 0).await.id, *owner_id);
    assert!(state.user_repo.find_by_id(&bot.id).await.unwrap().is_none());
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

    // The server was down ten minutes, past the owner's deadline: once it is up again the
    // owner has the whole 30 s
    clock.advance(Duration::from_secs(600));
    let boot = clock.now_millis();
    let timer = spawn_turn_timer(state.clone(), Duration::from_millis(10));
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while stored_state(&state, &party_id).await.turn_clock.deadline != Some(boot + 30_000) {
        assert!(
            tokio::time::Instant::now() < deadline,
            "the deadline was not moved"
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    // Ticks go by: nobody is ejected before the whole turn is over
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(seat_user(&state, &party_id, 0).await.id, humans.ids[0]);

    clock.advance(Duration::from_secs(30));
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

#[tokio::test]
async fn test_a_restart_does_not_count_the_downtime_against_the_player_on_turn() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    let (party_id, humans) =
        timed_party(&mut app, &state, "reboot", 1, &[BotDifficulty::Hard], 30).await;
    let (owner, bea) = (&humans.tokens[0], &humans.tokens[1]);
    // The owner used 20 s of the turn, then the server went down for a minute
    clock.advance(Duration::from_secs(80));
    let boot = clock.now_millis();

    assert_eq!(extend_turn_deadlines_after_downtime(&state).await, 1);
    assert!(enforce_turn_deadlines(&state).await.is_empty());
    let (_, body) = get_state(&mut app, &party_id, bea).await;
    assert_eq!(body["gameState"]["turnDeadline"], boot + 30_000, "{body}");
    // A second start finds the deadline far enough, and leaves it
    assert_eq!(extend_turn_deadlines_after_downtime(&state).await, 0);

    // The owner's turn is the same turn: the hand-size choice keeps the new deadline
    clock.advance(Duration::from_secs(29));
    let (status, _) = post(
        &mut app,
        &party_id,
        "selectHandSize",
        json!({"handSize": 5}),
        owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(enforce_turn_deadlines(&state).await.is_empty());
    clock.advance(Duration::from_secs(1));
    assert_eq!(enforce_turn_deadlines(&state).await.len(), 1);
}

#[tokio::test]
async fn test_the_last_human_ejected_hands_the_party_to_the_bot_on_their_seat() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    let (party_id, humans) =
        timed_party(&mut app, &state, "lasthuman", 1, &[BotDifficulty::Hard], 30).await;
    let (owner, owner_id) = (&humans.tokens[0], &humans.ids[0]);

    // Bea deletes her account: her seat is forfeited, the owner is the last human, still
    // timed; two seats are left, a Golden Score round
    let (status, body) = send(
        &mut app,
        "DELETE",
        "/api/auth/me",
        json!({"password": "password123"}),
        Some(&humans.tokens[1]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert!(stored_state(&state, &party_id).await.is_timed(0));

    clock.advance(Duration::from_secs(30));
    let ejections = enforce_turn_deadlines(&state).await;
    assert_eq!(ejections.len(), 1);
    // No human left to own the party: the bot on the owner's seat does, a player of it
    let stand_in = seat_user(&state, &party_id, 0).await;
    assert_eq!(
        ejections[0].new_owner_id.as_deref(),
        Some(stand_in.id.as_str())
    );
    let party = state
        .party_repo
        .find_by_id(&party_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(party.owner_id, stand_in.id);
    let (status, _) = get_state(&mut app, &party_id, owner).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // The bots play the game out; the owner's game is a loss after the three seats
    wait_finished(&state, &party_id, Duration::from_secs(20)).await;
    assert_eq!(
        result_of(&state, &party_id, owner_id).await,
        Some((4, 0, 0, 1))
    );
}

/// `game_results.player_count` of `party_id`, and every `finish_position` of its players
/// in order
async fn ranking_of(state: &AppState, party_id: &str) -> (i64, Vec<i64>) {
    let (player_count,): (i64,) =
        sqlx::query_as("SELECT player_count FROM game_results WHERE party_id = ?")
            .bind(party_id)
            .fetch_one(&state.db)
            .await
            .unwrap();
    let positions: Vec<i64> = sqlx::query_scalar(
        "SELECT finish_position FROM player_game_results WHERE party_id = ? \
         ORDER BY finish_position",
    )
    .bind(party_id)
    .fetch_all(&state.db)
    .await
    .unwrap();
    (player_count, positions)
}

/// The entry of `party_id` in the history of `token`'s user
async fn history_entry(app: &mut Router, token: &str, party_id: &str) -> Value {
    let (status, body) = send(app, "GET", "/api/history", Value::Null, Some(token)).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["games"]
        .as_array()
        .unwrap()
        .iter()
        .find(|game| game["partyId"] == party_id)
        .unwrap_or_else(|| panic!("{party_id} not in the history: {body}"))
        .clone()
}

#[tokio::test]
async fn test_two_players_ejected_in_turn_rank_4th_and_5th_of_5() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    // The owner (seat 0) and Bea (seat 1), humans; a bot on seat 2
    let (party_id, humans) =
        timed_party(&mut app, &state, "twice", 1, &[BotDifficulty::Hard], 30).await;
    let (owner_id, bea_id) = (&humans.ids[0], &humans.ids[1]);

    // The owner is to draw; close to 100, the game ends in a round or two
    let mut gs = stored_state(&state, &party_id).await;
    gs.current_action = GameAction::Draw;
    gs.scores[..3].copy_from_slice(&[90, 90, 90]);
    state
        .party_repo
        .save_game_state(&party_id, &gs)
        .await
        .unwrap();

    // The owner runs out of time; the stand-in draws, and Bea is on turn
    clock.advance(Duration::from_secs(30));
    assert_eq!(enforce_turn_deadlines(&state).await.len(), 1);
    assert_eq!(
        result_of(&state, &party_id, owner_id).await,
        Some((4, 0, 90, 1))
    );
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while stored_state(&state, &party_id).await.current_turn != 1 {
        assert!(
            tokio::time::Instant::now() < deadline,
            "the stand-in did not draw"
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
    }

    // Bea runs out of time in her turn: she is 4th, the owner moves down to 5th
    clock.advance(Duration::from_secs(30));
    let ejections = enforce_turn_deadlines(&state).await;
    assert_eq!(ejections.len(), 1, "{ejections:?}");
    assert_eq!(ejections[0].human_id, *bea_id);
    assert_eq!(result_of(&state, &party_id, bea_id).await.unwrap().0, 4);
    assert_eq!(result_of(&state, &party_id, owner_id).await.unwrap().0, 5);

    // The bots play the game out: five players ranked 1 to 5, the ejected last
    wait_finished(&state, &party_id, Duration::from_secs(30)).await;
    assert_eq!(
        ranking_of(&state, &party_id).await,
        (5, vec![1, 2, 3, 4, 5])
    );
    let bea = result_of(&state, &party_id, bea_id).await.unwrap();
    let owner = result_of(&state, &party_id, owner_id).await.unwrap();
    assert_eq!((bea.0, bea.1), (4, 0));
    assert_eq!((owner.0, owner.1), (5, 0));
    // Their history places them within the game's players, a loss each
    for (token, placement) in [(&humans.tokens[1], 4), (&humans.tokens[0], 5)] {
        let entry = history_entry(&mut app, token, &party_id).await;
        assert_eq!(entry["playerCount"], 5, "{entry}");
        assert_eq!(entry["userPlacement"], placement, "{entry}");
        let (_, body) = send(&mut app, "GET", "/api/stats/me", Value::Null, Some(token)).await;
        assert_eq!(
            (&body["stats"]["gamesPlayed"], &body["stats"]["losses"]),
            (&json!(1), &json!(1)),
            "{body}"
        );
    }
}

/// A timed party of three humans whose owner (seat 0) was ejected, then Bea (seat 1)
/// deleted her account, which left the stand-in alone in the game: the forfeit ended it.
/// Cid (seat 2) was out already. Returns the party and its humans.
async fn forfeit_ends_the_game_after_an_ejection(
    app: &mut Router,
    state: &AppState,
    clock: &ManualClock,
    prefix: &str,
) -> (String, Humans) {
    let (party_id, humans) = timed_party(app, state, prefix, 2, &[], 30).await;
    let mut gs = stored_state(state, &party_id).await;
    gs.scores[..3].copy_from_slice(&[10, 20, 105]);
    gs.eliminate_player(2);
    state
        .party_repo
        .save_game_state(&party_id, &gs)
        .await
        .unwrap();

    // The owner is ejected; the stand-in has not played yet
    clock.advance(Duration::from_secs(30));
    let ejection = EjectLatePlayer::new(state.user_repo.clone(), state.party_repo.clone())
        .execute(&party_id, clock.now_millis())
        .await
        .unwrap();
    assert_eq!(ejection.map(|e| e.player_index), Some(0));
    assert_eq!(party_status(state, &party_id).await, PartyStatus::Playing);

    let (status, body) = send(
        app,
        "DELETE",
        "/api/auth/me",
        json!({"password": "password123"}),
        Some(&humans.tokens[1]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(party_status(state, &party_id).await, PartyStatus::Finished);
    (party_id, humans)
}

#[tokio::test]
async fn test_an_ejected_player_ranks_after_every_seat_when_a_forfeit_ends_the_game() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    let (party_id, humans) =
        forfeit_ends_the_game_after_an_ejection(&mut app, &state, &clock, "forfeitend").await;

    // The stand-in wins; Bea (her forfeit) and Cid, out in the same round, by seat; the
    // ejected owner after the three seats
    assert_eq!(ranking_of(&state, &party_id).await, (4, vec![1, 2, 3, 4]));
    let stand_in = seat_user(&state, &party_id, 0).await;
    assert_eq!(
        result_of(&state, &party_id, &stand_in.id).await.unwrap().0,
        1
    );
    assert_eq!(
        result_of(&state, &party_id, &humans.ids[2])
            .await
            .unwrap()
            .0,
        3
    );
    assert_eq!(
        result_of(&state, &party_id, &humans.ids[0]).await,
        Some((4, 0, 10, 1))
    );
    for (token, placement) in [(&humans.tokens[0], 4), (&humans.tokens[2], 3)] {
        let entry = history_entry(&mut app, token, &party_id).await;
        assert_eq!(entry["playerCount"], 4, "{entry}");
        assert_eq!(entry["userPlacement"], placement, "{entry}");
    }
}

#[tokio::test]
async fn test_rewritten_game_results_count_the_ejected_players() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    let (party_id, humans) =
        forfeit_ends_the_game_after_an_ejection(&mut app, &state, &clock, "rewrite").await;

    // A row written before the ejected counted, the party left playing: the nextRound
    // recovery of a game over writes the results again, and the count follows the players
    sqlx::query("UPDATE game_results SET player_count = 3 WHERE party_id = ?")
        .bind(&party_id)
        .execute(&state.db)
        .await
        .unwrap();
    sqlx::query("UPDATE parties SET status = 'playing' WHERE id = ?")
        .bind(&party_id)
        .execute(&state.db)
        .await
        .unwrap();
    // Cid, out of the game but still seated, asks for the next round
    let (status, body) = post(
        &mut app,
        &party_id,
        "nextRound",
        json!({}),
        &humans.tokens[2],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["gameFinished"], json!(true), "{body}");
    assert_eq!(party_status(&state, &party_id).await, PartyStatus::Finished);
    assert_eq!(ranking_of(&state, &party_id).await, (4, vec![1, 2, 3, 4]));
}

#[tokio::test]
async fn test_a_move_whose_seat_is_given_away_after_its_seat_check_is_refused() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    let (party_id, humans) =
        timed_party(&mut app, &state, "seatcheck", 1, &[BotDifficulty::Hard], 30).await;
    let (owner, owner_id) = (&humans.tokens[0], &humans.ids[0]);
    let (status, _) = post(
        &mut app,
        &party_id,
        "selectHandSize",
        json!({"handSize": 5}),
        owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let card = stored_state(&state, &party_id).await.hands[0][0];
    clock.advance(Duration::from_secs(30));

    // The owner's play has checked the seat, still the owner's; the turn timer then gives
    // it to a bot (seat and version in one transaction, the turn unchanged); the play goes
    // on with the state read after that
    let ejection = {
        let (user_repo, party_repo, party_id) = (
            state.user_repo.clone(),
            state.party_repo.clone(),
            party_id.clone(),
        );
        let now = clock.now_millis();
        async move {
            let ejected = EjectLatePlayer::new(user_repo, party_repo)
                .execute(&party_id, now)
                .await
                .unwrap();
            assert!(ejected.is_some(), "the timer ejected nobody");
        }
    };
    let repo = Interleaved::new(state.party_repo.clone(), After::SeatCheck, ejection);
    let err = PlayCards::new(repo)
        .execute(PlayCardsInput {
            party_id: party_id.clone(),
            user_id: owner_id.clone(),
            card_ids: vec![card],
        })
        .await
        .err()
        .expect("the play went through on the bot's seat");
    assert!(
        matches!(&err, PlayCardsError::Repository(e) if e.is_conflict()),
        "{err}"
    );
    assert_eq!(
        zapzap_backend::api::error::ApiError::from(err).status,
        StatusCode::CONFLICT
    );

    // Nothing of the play was applied: the card is still in the seat's hand, the bot to play
    let gs = stored_state(&state, &party_id).await;
    assert!(gs.hands[0].contains(&card));
    assert_eq!(gs.current_action, GameAction::Play);
    assert_eq!(gs.current_turn, 0);
    assert_eq!(
        seat_user(&state, &party_id, 0).await.user_type,
        UserType::Bot
    );
}

#[tokio::test]
async fn test_an_ejected_players_account_deleted_as_the_game_ends_is_ranked_under_its_new_id() {
    let clock = Arc::new(ManualClock::new());
    let (mut app, state) = test_app(&clock).await;
    // The owner (seat 0) and Bea (seat 1), humans; a bot on seat 2
    let (party_id, humans) =
        timed_party(&mut app, &state, "deletend", 1, &[BotDifficulty::Hard], 30).await;
    let (owner_id, bea_id) = (humans.ids[0].clone(), humans.ids[1].clone());

    // The owner is ejected; the stand-in has not played yet
    clock.advance(Duration::from_secs(30));
    let ejection = EjectLatePlayer::new(state.user_repo.clone(), state.party_repo.clone())
        .execute(&party_id, clock.now_millis())
        .await
        .unwrap();
    assert_eq!(ejection.map(|e| e.player_index), Some(0));
    assert!(result_of(&state, &party_id, &owner_id).await.is_some());

    // Bea to play, her hand low enough for a ZapZap that sends both others past 100
    let mut gs = stored_state(&state, &party_id).await;
    gs.scores[..3].copy_from_slice(&[95, 10, 98]);
    for (seat, hand) in [&[12u8, 25][..], &[0, 13], &[11, 24]].iter().enumerate() {
        gs.hands[seat] = smallvec::SmallVec::from_slice(hand);
    }
    gs.current_turn = 1;
    gs.current_action = GameAction::Play;
    state
        .party_repo
        .save_game_state(&party_id, &gs)
        .await
        .unwrap();

    // Her ZapZap reads the state; the ejected owner then deletes their account, which
    // renames their result to an anonymous user and deletes theirs; the ZapZap writes the
    // end of the game after it. The game's end reads the ejected players in its own
    // transaction: it ranks the anonymous row, and cannot write under the deleted id.
    let deletion = {
        let (users, owner_id) = (state.user_repo.clone(), owner_id.clone());
        async move {
            let deletion = users.delete_account(&owner_id).await.unwrap();
            assert!(
                matches!(deletion, AccountDeletion::Deleted { anonymised_as: Some(_), ref forfeits } if forfeits.is_empty()),
                "{deletion:?}"
            );
        }
    };
    let repo = Interleaved::new(state.party_repo.clone(), After::StateRead, deletion);
    let zapzap = CallZapZap::new(repo.clone())
        .execute(CallZapZapInput {
            party_id: party_id.clone(),
            user_id: bea_id.clone(),
        })
        .await
        .unwrap_or_else(|e| panic!("the ZapZap that ends the game: {e}"));
    assert!(repo.stepped().await);
    assert!(zapzap.game_finished);
    assert_eq!(zapzap.winner_user_id.as_deref(), Some(bea_id.as_str()));

    // Four players ranked 1 to 4, the ejected owner last under their anonymous id
    assert_eq!(party_status(&state, &party_id).await, PartyStatus::Finished);
    assert_eq!(ranking_of(&state, &party_id).await, (4, vec![1, 2, 3, 4]));
    assert_eq!(
        result_of(&state, &party_id, &bea_id)
            .await
            .map(|r| (r.0, r.1)),
        Some((1, 1))
    );
    assert_eq!(result_of(&state, &party_id, &owner_id).await, None);
    let (last,): (String,) = sqlx::query_as(
        "SELECT user_id FROM player_game_results WHERE party_id = ? AND finish_position = 4",
    )
    .bind(&party_id)
    .fetch_one(&state.db)
    .await
    .unwrap();
    assert!(last.starts_with("deleted-"), "{last}");
}
