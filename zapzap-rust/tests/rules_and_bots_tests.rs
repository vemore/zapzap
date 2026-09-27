//! GAME_RULES.md where the Rust code used to disagree (eliminated starter, tied lowest
//! hands, a card named twice in a play), the bot loop: one at a time per party, one
//! strategy per bot for the whole game, and concurrent writes of a game state: a write
//! based on a stale read is refused (409 for a human, a retry for the bot loop).

use std::str::FromStr;
use std::sync::Arc;
use std::time::Duration;

use axum::{
    body::Body,
    http::{Request, StatusCode},
    Router,
};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use tower::{Service, ServiceExt};

use zapzap_backend::api;
use zapzap_backend::application::bot::{
    run_bot_turns_now, trigger_bot_turns, BotBrain, BotRunner, Roster,
};
use zapzap_backend::domain::entities::{BotDifficulty, User};
use zapzap_backend::domain::repositories::{AccountDeletion, PartyRepository, UserRepository};
use zapzap_backend::domain::services::{execute_play, forfeit_seat};
use zapzap_backend::domain::value_objects::{GameAction, GameState};
use zapzap_backend::infrastructure::app_state::AppState;
use zapzap_backend::infrastructure::database::repositories::{
    SqlitePartyRepository, SqliteUserRepository,
};
use zapzap_backend::infrastructure::database::schema::ensure_schema;

async fn test_app() -> (Router, Arc<AppState>) {
    test_app_with(|_| {}).await
}

/// The test application, its state first changed by `setup`
async fn test_app_with(setup: impl FnOnce(&mut AppState)) -> (Router, Arc<AppState>) {
    std::env::set_var("DATABASE_URL", "sqlite::memory:");
    std::env::set_var("JWT_SECRET", "test-secret-key");
    // Bots pause 200 ms between actions, not production's seconds
    std::env::set_var("BOT_ACTION_DELAY_MS", "200");
    // LLM bot memories land in a scratch directory, not in the repository's data/
    std::env::set_var(
        "BOT_STRATEGIES_DIR",
        std::env::temp_dir().join("zapzap-test-bot-strategies"),
    );
    let mut state = AppState::new().await.expect("app state");
    setup(&mut state);
    let state = Arc::new(state);
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
        // As many seats as players (settings.playerCount, 3 at least)
        json!({
            "name": format!("{prefix} party"),
            "settings": {"playerCount": (1 + humans + bots.len()).max(3)}
        }),
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

/// The seats of a finished party by finish position, from its saved results
async fn finish_order(state: &AppState, party_id: &str) -> Vec<i64> {
    sqlx::query_scalar(
        "SELECT pp.player_index FROM player_game_results r \
         JOIN party_players pp ON pp.party_id = r.party_id AND pp.user_id = r.user_id \
         WHERE r.party_id = ? ORDER BY r.finish_position",
    )
    .bind(party_id)
    .fetch_all(&state.db)
    .await
    .unwrap()
}

/// Three seats in round 1: seat 1 calls ZapZap with 3 points, seat `2 - leaver` goes past
/// 100 (95 + 15) and seat `leaver` deletes their account, before the ZapZap when
/// `forfeit_first` (the ZapZap ends the game), after it otherwise (the forfeit, between
/// the rounds, ends it). Returns the seats by finish position.
async fn forfeit_and_knockout_in_one_round(leaver: u8, forfeit_first: bool) -> Vec<i64> {
    let (mut app, state) = test_app().await;
    let prefix = format!("rank{leaver}{}", if forfeit_first { "f" } else { "z" });
    let (party_id, tokens) = started_party(&mut app, &state, &prefix, 2, &[]).await;
    let out = 2 - leaver;
    let mut gs = game_state(&state, &party_id).await;
    gs.hands[1] = smallvec::SmallVec::from_slice(&[0, 1]);
    gs.hands[out as usize] = smallvec::SmallVec::from_slice(&[13, 14, 15, 16, 17]);
    gs.hands[leaver as usize] = smallvec::SmallVec::from_slice(&[39, 40, 41]);
    gs.scores[1] = 10;
    gs.scores[out as usize] = 95;
    gs.scores[leaver as usize] = 20;
    gs.current_turn = 1;
    gs.current_action = GameAction::Play;
    save_game_state(&state, &party_id, &gs).await;

    let leaver_id = user_at(&state, &party_id, leaver).await;
    let forfeit = || async {
        let deletion = state.user_repo.delete_account(&leaver_id).await.unwrap();
        assert!(
            matches!(deletion, AccountDeletion::Deleted { ref forfeits, .. } if forfeits.len() == 1),
            "{deletion:?}"
        );
    };
    if forfeit_first {
        forfeit().await;
    }
    let (status, body) = send(
        &mut app,
        "POST",
        &format!("/api/game/{party_id}/zapzap"),
        json!({}),
        &tokens[1],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    // `gameFinished` is only sent when the game is over
    assert_eq!(
        body["gameFinished"].as_bool().unwrap_or(false),
        forfeit_first,
        "{body}"
    );
    if !forfeit_first {
        forfeit().await;
    }

    let gs = game_state(&state, &party_id).await;
    assert!(gs.is_eliminated(0) && gs.is_eliminated(2));
    assert_eq!(gs.round_number, 1, "both are out in round 1");
    finish_order(&state, &party_id).await
}

#[tokio::test]
async fn test_a_forfeit_and_a_knockout_in_one_round_rank_by_seat() {
    // GAME_RULES.md "Final Ranking": out in the same round, they rank by seat, whichever
    // left the game first and whether the forfeit or the ZapZap ended it
    for leaver in [0, 2] {
        for forfeit_first in [true, false] {
            assert_eq!(
                forfeit_and_knockout_in_one_round(leaver, forfeit_first).await,
                [1, 0, 2],
                "leaver at seat {leaver}, forfeit first: {forfeit_first}"
            );
        }
    }
}

#[tokio::test]
async fn test_a_forfeit_between_rounds_counts_in_the_next_round_played() {
    let (mut app, state) = test_app().await;
    let (party_id, tokens) = started_party(&mut app, &state, "betweenrounds", 3, &[]).await;

    // Round 1: seat 1 calls with 3 points and seat 0 goes past 100 (95 + 15)
    let mut gs = game_state(&state, &party_id).await;
    set_hands(
        &mut gs,
        &[
            &[13, 14, 15, 16, 17],
            &[0, 1],
            &[26, 27, 28],
            &[39, 40, 41, 42],
        ],
    );
    gs.scores[..4].copy_from_slice(&[95, 10, 20, 30]);
    gs.current_turn = 1;
    gs.current_action = GameAction::Play;
    save_game_state(&state, &party_id, &gs).await;
    let zapzap = format!("/api/game/{party_id}/zapzap");
    let (status, body) = send(&mut app, "POST", &zapzap, json!({}), &tokens[1]).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert!(body["gameFinished"].is_null(), "{body}");

    // Between rounds 1 and 2, seat 2 leaves: seats 1 and 3 play on
    let leaver = user_at(&state, &party_id, 2).await;
    let deletion = state.user_repo.delete_account(&leaver).await.unwrap();
    assert!(
        matches!(deletion, AccountDeletion::Deleted { ref forfeits, .. } if forfeits.len() == 1),
        "{deletion:?}"
    );
    let (status, body) = send(
        &mut app,
        "POST",
        &format!("/api/game/{party_id}/nextRound"),
        json!({}),
        &tokens[1],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    // Round 2, a Golden Score: seat 1's lower hand wins the game
    let mut gs = game_state(&state, &party_id).await;
    assert_eq!(gs.round_number, 2);
    set_hands(&mut gs, &[&[], &[0, 1], &[], &[39, 40, 41]]);
    gs.current_turn = 1;
    gs.current_action = GameAction::Play;
    save_game_state(&state, &party_id, &gs).await;
    let (status, body) = send(&mut app, "POST", &zapzap, json!({}), &tokens[1]).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["gameFinished"], true, "{body}");

    // GAME_RULES.md "Final Ranking": the game went on, so the leaver is out in round 2,
    // after seat 0 (round 1), and ranks above it despite the higher seat
    assert_eq!(finish_order(&state, &party_id).await, [1, 3, 2, 0]);
}

#[tokio::test]
async fn test_a_zapzap_ending_the_game_saves_its_results() {
    let (mut app, state) = test_app().await;
    let (party_id, tokens) = started_party(&mut app, &state, "results", 2, &[]).await;
    // Seat 0 calls with 3 points; seats 1 (99 + 15) and 2 (95 + 10) both go past 100
    let mut gs = game_state(&state, &party_id).await;
    set_hands(
        &mut gs,
        &[&[0, 1], &[13, 14, 15, 16, 17], &[26, 27, 28, 29]],
    );
    gs.scores[..3].copy_from_slice(&[10, 99, 95]);
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
    assert_eq!(body["gameFinished"], true, "{body}");

    let (winner, winner_score, rounds, golden): (String, i64, i64, bool) = sqlx::query_as(
        "SELECT winner_user_id, winner_final_score, total_rounds, was_golden_score \
         FROM game_results WHERE party_id = ?",
    )
    .bind(&party_id)
    .fetch_one(&state.db)
    .await
    .unwrap();
    assert_eq!(winner, user_at(&state, &party_id, 0).await);
    assert_eq!((winner_score, rounds, golden), (10, 1, false));
    // Out in the same round, seat 1 ranks above seat 2 by seat, its higher score aside
    let rows: Vec<(i64, i64, i64, i64, bool)> = sqlx::query_as(
        "SELECT pp.player_index, r.finish_position, r.final_score, r.rounds_played, \
         r.is_winner FROM player_game_results r \
         JOIN party_players pp ON pp.party_id = r.party_id AND pp.user_id = r.user_id \
         WHERE r.party_id = ? ORDER BY r.finish_position",
    )
    .bind(&party_id)
    .fetch_all(&state.db)
    .await
    .unwrap();
    assert_eq!(
        rows,
        [
            (0, 1, 10, 1, true),
            (1, 2, 114, 1, false),
            (2, 3, 105, 1, false)
        ]
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
        .brain(&state, "party", "thibot", Some(BotDifficulty::Thibot))
        .await;
    let draw = party_a
        .brain(&state, "party", "thibot", Some(BotDifficulty::Thibot))
        .await;
    // The instance that chose the play is the one asked for the draw (and the next turns)
    assert!(same_brain(&play, &draw));

    // Another bot, or the same bot in another party, has its own
    let vince = party_a
        .brain(&state, "party", "vince", Some(BotDifficulty::HardVince))
        .await;
    assert!(!same_brain(&play, &vince));
    let elsewhere = party_b
        .brain(&state, "other", "thibot", Some(BotDifficulty::Thibot))
        .await;
    assert!(!same_brain(&play, &elsewhere));

    let llm = party_a
        .brain(&state, "party", "llm", Some(BotDifficulty::Llm))
        .await;
    let llm_again = party_a
        .brain(&state, "party", "llm", Some(BotDifficulty::Llm))
        .await;
    assert!(same_brain(&llm, &llm_again));
}

#[tokio::test]
async fn test_trigger_during_a_manual_loop_is_served_after_it() {
    let (mut app, state) = test_app().await;
    let (party_id, _) = started_party(
        &mut app,
        &state,
        "lost",
        0,
        &[BotDifficulty::Easy, BotDifficulty::Easy],
    )
    .await;
    let mut gs = game_state(&state, &party_id).await;
    set_hands(
        &mut gs,
        &[&[9, 10, 11, 12], &[22, 23, 24, 25], &[35, 36, 37, 38]],
    );
    gs.current_turn = 1;
    gs.current_action = GameAction::Play;
    save_game_state(&state, &party_id, &gs).await;

    // The manual trigger-bot loop runs the two bots' turns ...
    let manual = tokio::spawn({
        let (state, party_id) = (state.clone(), party_id.clone());
        async move { run_bot_turns_now(&state, &party_id).await }
    });
    tokio::time::sleep(Duration::from_millis(50)).await;

    // ... while a poll's trigger comes: the lock is taken, the trigger waits as pending
    trigger_bot_turns(&state, &party_id).await.unwrap();
    assert!(state.bot_runner.has_pending_trigger(&party_id));

    assert_eq!(manual.await.unwrap().expect("manual loop"), 4);

    // Once the manual loop lets go, the pending trigger is served, not dropped
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    while state.bot_runner.has_pending_trigger(&party_id) {
        assert!(
            tokio::time::Instant::now() < deadline,
            "the trigger that came during the manual loop was lost"
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

#[tokio::test]
async fn test_hand_size_fits_the_deck_with_eight_players() {
    let (mut app, state) = test_app().await;
    let (party_id, tokens) = started_party(&mut app, &state, "eight", 7, &[]).await;
    let path = format!("/api/game/{party_id}/selectHandSize");

    // 8 x 7 = 56 cards: more than the deck holds
    let (status, body) = send(&mut app, "POST", &path, json!({"handSize": 7}), &tokens[0]).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
    assert_eq!(body["code"], "INVALID_HAND_SIZE");
    assert_eq!(
        game_state(&state, &party_id).await.current_action,
        GameAction::SelectHandSize
    );

    // 8 x 6 + the flipped card = 49: dealt
    let (status, body) = send(&mut app, "POST", &path, json!({"handSize": 6}), &tokens[0]).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let gs = game_state(&state, &party_id).await;
    assert!((0..8).all(|p| gs.hands[p].len() == 6));
    assert_eq!(gs.last_cards_played.len(), 1);
}

/// A party of the owner and two bots of `difficulty`, bot 1 to play, no hand low enough
/// for a ZapZap: the bots' turns are four actions (a play and a draw each)
async fn two_bot_turns_ahead(
    app: &mut Router,
    state: &AppState,
    prefix: &str,
    difficulty: BotDifficulty,
) -> String {
    let (party_id, _) = started_party(app, state, prefix, 0, &[difficulty, difficulty]).await;
    let mut gs = game_state(state, &party_id).await;
    set_hands(
        &mut gs,
        &[&[9, 10, 11, 12], &[22, 23, 24, 25], &[35, 36, 37, 38]],
    );
    gs.current_turn = 1;
    gs.current_action = GameAction::Play;
    save_game_state(state, &party_id, &gs).await;
    party_id
}

#[tokio::test]
async fn test_bot_actions_pause_for_bot_action_delay_ms() {
    // The server's runner reads BOT_ACTION_DELAY_MS (200 in test_app)
    let (_, state) = test_app().await;
    assert_eq!(state.bot_runner.action_delay(), Duration::from_millis(200));

    // A runner with a 300 ms pause takes at least 4 x 300 ms for four actions
    let (mut app, state) = test_app_with(|s| {
        s.bot_runner = Arc::new(BotRunner::with_action_delay(Duration::from_millis(300)));
    })
    .await;
    let party_id = two_bot_turns_ahead(&mut app, &state, "delay", BotDifficulty::Easy).await;
    let started = tokio::time::Instant::now();
    assert_eq!(run_bot_turns_now(&state, &party_id).await.unwrap(), 4);
    let elapsed = started.elapsed();
    assert!(
        elapsed >= Duration::from_millis(1200),
        "four actions took {elapsed:?}"
    );
}

#[cfg(unix)]
#[tokio::test]
async fn test_llm_bots_play_on_when_the_strategies_dir_is_not_writable() {
    use std::os::unix::fs::PermissionsExt;

    // A root-owned data/ seen from the uid-1000 container: read-only, so its
    // bot-strategies subdirectory cannot be created nor written
    let dir = std::env::temp_dir().join(format!("zapzap-ro-bots-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o555)).unwrap();
    let strategies = dir.join("bot-strategies");

    let (mut app, state) = test_app_with(|s| s.bot_strategies_dir = strategies.clone()).await;
    let party_id = two_bot_turns_ahead(&mut app, &state, "rollm", BotDifficulty::Llm).await;

    // The LLM bots load their (empty) memories, warn, and play their turns
    let played = run_bot_turns_now(&state, &party_id).await;
    let memory = state.get_llm_memory("some-llm-bot").await;
    std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o755)).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(played.expect("the bots' turns"), 4);
    let gs = game_state(&state, &party_id).await;
    assert_eq!((gs.current_turn, gs.current_action), (0, GameAction::Play));
    assert!(!memory.read().await.has_strategies());
}

// ============================================================================
// Concurrent writes of the game state
// ============================================================================

/// The user seated at `seat`
async fn user_at(state: &AppState, party_id: &str, seat: u8) -> String {
    state
        .party_repo
        .get_party_players(party_id)
        .await
        .unwrap()
        .into_iter()
        .find(|p| p.player_index == seat)
        .expect("seat")
        .user_id
}

/// Seat 0 to play `hands[0]`, the others holding the rest; returns the stored version
async fn seat_zero_to_play(state: &AppState, party_id: &str, hands: &[&[u8]]) -> i64 {
    let mut gs = game_state(state, party_id).await;
    set_hands(&mut gs, hands);
    gs.current_turn = 0;
    gs.current_action = GameAction::Play;
    save_game_state(state, party_id, &gs).await;
    stored_version(state, party_id).await
}

async fn stored_version(state: &AppState, party_id: &str) -> i64 {
    state
        .party_repo
        .get_versioned_game_state(party_id)
        .await
        .unwrap()
        .expect("game state")
        .version
}

#[tokio::test]
async fn test_a_move_read_before_a_forfeit_is_refused_and_the_seat_stays_out() {
    let (mut app, state) = test_app().await;
    let (party_id, _) = started_party(&mut app, &state, "stale", 2, &[]).await;
    let version = seat_zero_to_play(&state, &party_id, &[&[0, 1, 2], &[13, 14], &[26, 27]]).await;

    // Seat 0's move reads the state …
    let read = state
        .party_repo
        .get_versioned_game_state(&party_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(read.version, version);

    // … seat 2's account is deleted meanwhile, which forfeits the seat …
    let leaver = user_at(&state, &party_id, 2).await;
    let deletion = state.user_repo.delete_account(&leaver).await.unwrap();
    assert!(
        matches!(deletion, AccountDeletion::Deleted { ref forfeits, .. } if forfeits.len() == 1),
        "{deletion:?}"
    );
    assert_eq!(stored_version(&state, &party_id).await, version + 1);

    // … and the move's write, based on the read before the forfeit, is refused
    let mut moved = read.state.clone();
    execute_play(&mut moved, &[0]).unwrap();
    let err = state
        .party_repo
        .update_game_state(&party_id, &moved, read.version)
        .await
        .expect_err("a write based on a stale read");
    assert!(err.is_conflict(), "{err}");

    // The forfeit stands: the seat is out, its hand gone; seat 0 still holds its card
    let gs = game_state(&state, &party_id).await;
    assert!(gs.is_eliminated(2));
    assert!(gs.hands[2].is_empty());
    assert_eq!(gs.hands[0].as_slice(), &[0, 1, 2]);
    assert_eq!(stored_version(&state, &party_id).await, version + 1);
}

#[tokio::test]
async fn test_two_writes_from_one_read_keep_the_first_and_refuse_the_second() {
    let (mut app, state) = test_app().await;
    let (party_id, _) = started_party(&mut app, &state, "twowrites", 2, &[]).await;
    let version = seat_zero_to_play(&state, &party_id, &[&[0, 1, 2], &[13, 14], &[26, 27]]).await;
    let read = state
        .party_repo
        .get_versioned_game_state(&party_id)
        .await
        .unwrap()
        .unwrap();

    let mut first = read.state.clone();
    execute_play(&mut first, &[0]).unwrap();
    state
        .party_repo
        .update_game_state(&party_id, &first, read.version)
        .await
        .expect("the first write");
    let mut second = read.state.clone();
    execute_play(&mut second, &[1]).unwrap();
    let err = state
        .party_repo
        .update_game_state(&party_id, &second, read.version)
        .await
        .expect_err("the second write from the same read");
    assert!(err.is_conflict(), "{err}");

    let gs = game_state(&state, &party_id).await;
    assert_eq!(gs.hands[0].as_slice(), &[1, 2], "the first play stands");
    assert_eq!(stored_version(&state, &party_id).await, version + 1);
}

/// The test application on a database file. The in-memory database the other tests use
/// is a shared cache, which makes a reader wait for a writer's whole transaction; a file
/// locks as production's does, so a request reads the last committed state while
/// another connection holds the write lock.
async fn test_app_on_file(name: &str) -> (Router, Arc<AppState>, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!(
        "zapzap-race-{name}-{}-{}.db",
        std::process::id(),
        uuid::Uuid::new_v4()
    ));
    let db = SqlitePoolOptions::new()
        .connect_with(
            SqliteConnectOptions::from_str(&format!("sqlite:{}", path.display()))
                .unwrap()
                .create_if_missing(true),
        )
        .await
        .unwrap();
    ensure_schema(&db).await.unwrap();
    let (app, state) = test_app_with(move |state| {
        state.user_repo = Arc::new(SqliteUserRepository::new(db.clone()));
        state.party_repo = Arc::new(SqlitePartyRepository::new(db.clone()));
        state.db = db;
    })
    .await;
    (app, state, path)
}

/// Open a write transaction that forfeits `seat` the way an account deletion does
/// (`forfeit_playing_seats`: `forfeit_seat`, then the new version), and keep it open:
/// until it commits, every other connection reads the state from before the forfeit and
/// waits to write.
async fn forfeit_held_open(
    state: &AppState,
    party_id: &str,
    seat: u8,
) -> sqlx::Transaction<'static, sqlx::Sqlite> {
    let mut tx = state.db.begin_with("BEGIN IMMEDIATE").await.unwrap();
    let json: String = sqlx::query_scalar("SELECT state_json FROM game_state WHERE party_id = ?")
        .bind(party_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    let mut gs = GameState::from_json(&json).unwrap();
    assert_eq!(forfeit_seat(&mut gs, seat), None, "the game goes on");
    sqlx::query("UPDATE game_state SET state_json = ?, version = version + 1 WHERE party_id = ?")
        .bind(gs.to_json())
        .bind(party_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    tx
}

/// Long enough for a request started now to read the state and reach its write, which
/// then waits for the lock (SQLite's busy timeout, 5 s by default)
const TO_REACH_THE_WRITE: Duration = Duration::from_millis(1000);

#[tokio::test]
async fn test_a_human_move_that_loses_the_race_to_a_forfeit_is_409() {
    let (mut app, state, path) = test_app_on_file("human").await;
    let (party_id, tokens) = started_party(&mut app, &state, "race409", 2, &[]).await;
    seat_zero_to_play(&state, &party_id, &[&[0, 1, 2], &[13, 14], &[26, 27]]).await;

    // Seat 2 forfeits while seat 0's play is under way: the play reads the state from
    // before the forfeit, and writes after it
    let tx = forfeit_held_open(&state, &party_id, 2).await;
    let play = {
        let (mut app, token) = (app.clone(), tokens[0].clone());
        let path = format!("/api/game/{party_id}/play");
        tokio::spawn(
            async move { send(&mut app, "POST", &path, json!({"cardIds": [0]}), &token).await },
        )
    };
    tokio::time::sleep(TO_REACH_THE_WRITE).await;
    tx.commit().await.unwrap();
    let (status, body) = play.await.unwrap();

    // The play is refused and played nothing; the client reloads
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
    assert_eq!(body["code"], "GAME_STATE_CONFLICT", "{body}");
    let (status, body) = send(
        &mut app,
        "GET",
        &format!("/api/game/{party_id}/state"),
        json!({}),
        &tokens[0],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["gameState"]["eliminatedPlayers"], json!([2]), "{body}");
    assert_eq!(body["gameState"]["currentAction"], "play", "{body}");
    assert_eq!(body["gameState"]["currentTurn"], 0, "{body}");

    // Played again on the reloaded table, the move goes through; the seat stays out
    let (status, body) = send(
        &mut app,
        "POST",
        &format!("/api/game/{party_id}/play"),
        json!({"cardIds": [0]}),
        &tokens[0],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let gs = game_state(&state, &party_id).await;
    assert!(gs.is_eliminated(2));
    assert_eq!(gs.hands[0].as_slice(), &[1, 2]);

    state.db.close().await;
    let _ = std::fs::remove_file(&path);
}

#[tokio::test]
async fn test_the_same_move_sent_twice_at_once_is_played_once() {
    let (mut app, state, path) = test_app_on_file("twice").await;
    let (party_id, tokens) = started_party(&mut app, &state, "doublesend", 2, &[]).await;
    let version = seat_zero_to_play(&state, &party_id, &[&[0, 1, 2], &[13, 14], &[26, 27]]).await;

    // Both requests read the same state while the lock is held, then race to write
    let lock = state.db.begin_with("BEGIN IMMEDIATE").await.unwrap();
    let plays: Vec<_> = (0..2)
        .map(|_| {
            let (mut app, token) = (app.clone(), tokens[0].clone());
            let path = format!("/api/game/{party_id}/play");
            tokio::spawn(async move {
                send(&mut app, "POST", &path, json!({"cardIds": [0]}), &token).await
            })
        })
        .collect();
    tokio::time::sleep(TO_REACH_THE_WRITE).await;
    lock.commit().await.unwrap();
    let mut statuses = Vec::new();
    for play in plays {
        let (status, body) = play.await.unwrap();
        if status == StatusCode::CONFLICT {
            assert_eq!(body["code"], "GAME_STATE_CONFLICT", "{body}");
        }
        statuses.push(status);
    }
    statuses.sort();
    assert_eq!(statuses, [StatusCode::OK, StatusCode::CONFLICT]);

    // One card left the hand, once
    let gs = game_state(&state, &party_id).await;
    assert_eq!(gs.hands[0].as_slice(), &[1, 2]);
    assert_eq!(gs.current_action, GameAction::Draw);
    assert_eq!(stored_version(&state, &party_id).await, version + 1);

    state.db.close().await;
    let _ = std::fs::remove_file(&path);
}

#[tokio::test]
async fn test_a_bot_move_that_loses_the_race_to_a_forfeit_is_played_again() {
    let (mut app, state, path) = test_app_on_file("bot").await;
    // Seats: the owner 0, a human 1, an Easy bot 2
    let (party_id, _) = started_party(&mut app, &state, "racebot", 1, &[BotDifficulty::Easy]).await;
    // The bot is to play, singles only (four ranks, four suits); no hand is low enough
    // for an Easy ZapZap
    let mut gs = game_state(&state, &party_id).await;
    set_hands(
        &mut gs,
        &[&[1, 2, 3, 4], &[14, 15, 16, 17], &[9, 23, 37, 51]],
    );
    gs.current_turn = 2;
    gs.current_action = GameAction::Play;
    save_game_state(&state, &party_id, &gs).await;

    // Seat 1 forfeits while the bot's loop runs: its play reads the state from before
    // the forfeit, and writes after it
    let tx = forfeit_held_open(&state, &party_id, 1).await;
    let bots = {
        let (state, party_id) = (state.clone(), party_id.clone());
        tokio::spawn(async move { run_bot_turns_now(&state, &party_id).await })
    };
    tokio::time::sleep(TO_REACH_THE_WRITE).await;
    tx.commit().await.unwrap();

    // The loop read the state again and played its turn on it: a play and a draw, then
    // the owner is to move, with seat 1 still out
    let actions = bots
        .await
        .unwrap()
        .expect("the bot loop goes on after the conflict");
    assert_eq!(actions, 2);
    let gs = game_state(&state, &party_id).await;
    assert!(gs.is_eliminated(1), "the forfeit stands");
    assert!(gs.hands[1].is_empty());
    assert_eq!((gs.current_turn, gs.current_action), (0, GameAction::Play));
    assert_eq!(gs.hands[2].len(), 4, "the bot played one card and drew one");

    state.db.close().await;
    let _ = std::fs::remove_file(&path);
}

#[tokio::test]
async fn test_next_round_asked_twice_at_once_starts_one_round() {
    let (mut app, state, path) = test_app_on_file("nextround").await;
    let (party_id, tokens) = started_party(&mut app, &state, "twonext", 2, &[]).await;
    let mut gs = game_state(&state, &party_id).await;
    gs.current_action = GameAction::Finished;
    save_game_state(&state, &party_id, &gs).await;

    // Two players ask for the next round at once: both read the finished round
    let lock = state.db.begin_with("BEGIN IMMEDIATE").await.unwrap();
    let asks: Vec<_> = tokens[..2]
        .iter()
        .map(|token| {
            let (mut app, token) = (app.clone(), token.clone());
            let path = format!("/api/game/{party_id}/nextRound");
            tokio::spawn(async move { send(&mut app, "POST", &path, json!({}), &token).await })
        })
        .collect();
    tokio::time::sleep(TO_REACH_THE_WRITE).await;
    lock.commit().await.unwrap();
    let mut statuses = Vec::new();
    for ask in asks {
        let (status, body) = ask.await.unwrap();
        if status == StatusCode::CONFLICT {
            assert_eq!(body["code"], "GAME_STATE_CONFLICT", "{body}");
        }
        statuses.push(status);
    }
    statuses.sort();
    assert_eq!(statuses, [StatusCode::OK, StatusCode::CONFLICT]);

    // One round 2, and the state is its hand-size choice
    let rounds: Vec<i64> =
        sqlx::query_scalar("SELECT round_number FROM rounds WHERE party_id = ? ORDER BY 1")
            .bind(&party_id)
            .fetch_all(&state.db)
            .await
            .unwrap();
    assert_eq!(rounds, [1, 2]);
    let gs = game_state(&state, &party_id).await;
    assert_eq!(gs.round_number, 2);
    assert_eq!(gs.current_action, GameAction::SelectHandSize);

    state.db.close().await;
    let _ = std::fs::remove_file(&path);
}
