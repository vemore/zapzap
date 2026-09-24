//! API Integration Tests for ZapZap Backend
//!
//! Tests the HTTP API endpoints to ensure they match the JS backend behavior exactly.

use axum::{
    body::Body,
    http::{Request, StatusCode},
    Router,
};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use std::sync::Arc;
use tower::{Service, ServiceExt};

use zapzap_backend::api;
use zapzap_backend::infrastructure::app_state::AppState;

/// Helper to create a test application
async fn create_test_app() -> Router {
    create_test_app_with_state().await.0
}

/// The test application and its state, for tests that set up a game state or read events
async fn create_test_app_with_state() -> (Router, Arc<AppState>) {
    // Set test environment
    std::env::set_var("DATABASE_URL", "sqlite::memory:");
    std::env::set_var("JWT_SECRET", "test-secret-key");

    let state = AppState::new().await.expect("Failed to create app state");
    let state = Arc::new(state);

    let app = Router::new()
        .nest("/api", api::routes::create_api_router(state.clone()))
        .with_state(state.clone());
    (app, state)
}

/// Helper to send a raw request: any method, raw body, optional content type and token
async fn send_raw(
    app: &mut Router,
    method: &str,
    path: &str,
    body: &str,
    content_type: Option<&str>,
    token: Option<&str>,
) -> (StatusCode, Value) {
    let mut builder = Request::builder().method(method).uri(path);
    if let Some(ct) = content_type {
        builder = builder.header("Content-Type", ct);
    }
    if let Some(token) = token {
        builder = builder.header("Authorization", format!("Bearer {}", token));
    }
    let request = builder.body(Body::from(body.to_string())).unwrap();

    let response = ServiceExt::<Request<Body>>::ready(app)
        .await
        .unwrap()
        .call(request)
        .await
        .unwrap();

    let status = response.status();
    let body_bytes = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body_bytes).unwrap_or(Value::Null);

    (status, json)
}

/// Helper to make a POST request with JSON body
async fn post_json(app: &mut Router, path: &str, body: Value) -> (StatusCode, Value) {
    let request = Request::builder()
        .method("POST")
        .uri(path)
        .header("Content-Type", "application/json")
        .body(Body::from(serde_json::to_string(&body).unwrap()))
        .unwrap();

    let response = ServiceExt::<Request<Body>>::ready(app)
        .await
        .unwrap()
        .call(request)
        .await
        .unwrap();

    let status = response.status();
    let body_bytes = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body_bytes).unwrap_or(Value::Null);

    (status, json)
}

/// Helper to make a POST request with auth header
async fn post_json_auth(
    app: &mut Router,
    path: &str,
    body: Value,
    token: &str,
) -> (StatusCode, Value) {
    let request = Request::builder()
        .method("POST")
        .uri(path)
        .header("Content-Type", "application/json")
        .header("Authorization", format!("Bearer {}", token))
        .body(Body::from(serde_json::to_string(&body).unwrap()))
        .unwrap();

    let response = ServiceExt::<Request<Body>>::ready(app)
        .await
        .unwrap()
        .call(request)
        .await
        .unwrap();

    let status = response.status();
    let body_bytes = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body_bytes).unwrap_or(Value::Null);

    (status, json)
}

/// Helper to make a GET request with auth header
async fn get_auth(app: &mut Router, path: &str, token: &str) -> (StatusCode, Value) {
    let request = Request::builder()
        .method("GET")
        .uri(path)
        .header("Authorization", format!("Bearer {}", token))
        .body(Body::empty())
        .unwrap();

    let response = ServiceExt::<Request<Body>>::ready(app)
        .await
        .unwrap()
        .call(request)
        .await
        .unwrap();

    let status = response.status();
    let body_bytes = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body_bytes).unwrap_or(Value::Null);

    (status, json)
}

// ============================================================================
// Auth Tests
// ============================================================================

#[tokio::test]
async fn test_register_missing_credentials() {
    let mut app = create_test_app().await;

    // Test with empty body
    let (status, body) = post_json(&mut app, "/api/auth/register", json!({})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "MISSING_CREDENTIALS");
    assert_eq!(body["error"], "Username and password are required");

    // Test with only username
    let (status, body) =
        post_json(&mut app, "/api/auth/register", json!({"username": "test"})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "MISSING_CREDENTIALS");

    // Test with only password
    let (status, body) = post_json(
        &mut app,
        "/api/auth/register",
        json!({"password": "test123"}),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "MISSING_CREDENTIALS");
}

#[tokio::test]
async fn test_register_success() {
    let mut app = create_test_app().await;

    let (status, body) = post_json(
        &mut app,
        "/api/auth/register",
        json!({
            "username": "testuser",
            "password": "password123"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(body["success"], true);
    assert!(body["user"]["id"].is_string());
    assert_eq!(body["user"]["username"], "testuser");
    assert!(body["user"]["createdAt"].is_string());
    assert!(body["token"].is_string());
}

#[tokio::test]
async fn test_register_duplicate_username() {
    let mut app = create_test_app().await;

    // First registration
    let (status, _) = post_json(
        &mut app,
        "/api/auth/register",
        json!({
            "username": "duplicate",
            "password": "password123"
        }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    // Second registration with same username
    let (status, body) = post_json(
        &mut app,
        "/api/auth/register",
        json!({
            "username": "duplicate",
            "password": "password456"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "USERNAME_EXISTS");
    assert_eq!(body["error"], "Username already exists");
}

#[tokio::test]
async fn test_login_missing_credentials() {
    let mut app = create_test_app().await;

    let (status, body) = post_json(&mut app, "/api/auth/login", json!({})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "MISSING_CREDENTIALS");
    assert_eq!(body["error"], "Username and password are required");
}

#[tokio::test]
async fn test_login_invalid_credentials() {
    let mut app = create_test_app().await;

    let (status, body) = post_json(
        &mut app,
        "/api/auth/login",
        json!({
            "username": "nonexistent",
            "password": "wrongpassword"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(body["code"], "INVALID_CREDENTIALS");
    assert_eq!(body["error"], "Invalid username or password");
}

#[tokio::test]
async fn test_login_success() {
    let mut app = create_test_app().await;

    // First register
    let (_, _) = post_json(
        &mut app,
        "/api/auth/register",
        json!({
            "username": "logintest",
            "password": "password123"
        }),
    )
    .await;

    // Then login
    let (status, body) = post_json(
        &mut app,
        "/api/auth/login",
        json!({
            "username": "logintest",
            "password": "password123"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["success"], true);
    assert!(body["user"]["id"].is_string());
    assert_eq!(body["user"]["username"], "logintest");
    assert!(body["user"]["isAdmin"].is_boolean());
    assert!(body["token"].is_string());
}

// ============================================================================
// Party Tests
// ============================================================================

#[tokio::test]
async fn test_create_party_requires_auth() {
    let mut app = create_test_app().await;

    let (status, _) = post_json(
        &mut app,
        "/api/party",
        json!({
            "name": "Test Party"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_create_party_missing_name() {
    let mut app = create_test_app().await;

    // Register and get token
    let (_, register_resp) = post_json(
        &mut app,
        "/api/auth/register",
        json!({
            "username": "partytest",
            "password": "password123"
        }),
    )
    .await;
    let token = register_resp["token"].as_str().unwrap();

    // Try to create party without name
    let (status, body) = post_json_auth(&mut app, "/api/party", json!({}), token).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "MISSING_PARTY_NAME");
}

#[tokio::test]
async fn test_create_party_success() {
    let mut app = create_test_app().await;

    // Register and get token
    let (_, register_resp) = post_json(
        &mut app,
        "/api/auth/register",
        json!({
            "username": "partycreator",
            "password": "password123"
        }),
    )
    .await;
    let token = register_resp["token"].as_str().unwrap();
    let user_id = register_resp["user"]["id"].as_str().unwrap();

    // Create party
    let (status, body) = post_json_auth(
        &mut app,
        "/api/party",
        json!({
            "name": "My Test Party",
            "visibility": "public",
            "settings": {
                "handSize": 5,
                "maxScore": 100,
                "enableGoldenScore": true,
                "goldenScoreThreshold": 100
            }
        }),
        token,
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(body["success"], true);
    assert!(body["party"]["id"].is_string());
    assert_eq!(body["party"]["name"], "My Test Party");
    assert_eq!(body["party"]["ownerId"], user_id);
    assert!(body["party"]["inviteCode"].is_string());
    assert_eq!(body["party"]["visibility"], "public");
    assert_eq!(body["party"]["status"], "waiting");
    assert_eq!(body["party"]["settings"]["handSize"], 5);
    assert_eq!(body["party"]["settings"]["maxScore"], 100);
    assert!(body["party"]["createdAt"].is_string());
    assert!(body["botsJoined"].is_number());
}

#[tokio::test]
async fn test_list_parties() {
    let mut app = create_test_app().await;

    // Register and get token
    let (_, register_resp) = post_json(
        &mut app,
        "/api/auth/register",
        json!({
            "username": "listtest",
            "password": "password123"
        }),
    )
    .await;
    let token = register_resp["token"].as_str().unwrap();

    // Create a party
    let (_, _) = post_json_auth(
        &mut app,
        "/api/party",
        json!({
            "name": "List Test Party"
        }),
        token,
    )
    .await;

    // List parties
    let (status, body) = get_auth(&mut app, "/api/party", token).await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["success"], true);
    assert!(body["parties"].is_array());
    assert!(body["total"].is_number());
    assert!(body["limit"].is_number());
    assert!(body["offset"].is_number());
}

// ============================================================================
// Shared setup for the error-contract tests
// ============================================================================

use zapzap_backend::domain::entities::{BotDifficulty, User};
use zapzap_backend::domain::repositories::{PartyRepository, UserRepository};
use zapzap_backend::domain::value_objects::GameAction;

/// Register a user; returns (token, user id)
async fn register(app: &mut Router, username: &str) -> (String, String) {
    let (status, body) = post_json(
        app,
        "/api/auth/register",
        json!({"username": username, "password": "password123"}),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "register {username}: {body}");
    (
        body["token"].as_str().unwrap().to_string(),
        body["user"]["id"].as_str().unwrap().to_string(),
    )
}

/// Create a public party owned by `token`; returns its id
async fn create_party(app: &mut Router, token: &str, name: &str) -> String {
    let (status, body) = post_json_auth(app, "/api/party", json!({"name": name}), token).await;
    assert_eq!(status, StatusCode::CREATED, "create party: {body}");
    body["party"]["id"].as_str().unwrap().to_string()
}

/// Save a bot user straight into the repository; returns its id
async fn create_bot(state: &AppState, username: &str) -> String {
    let id = uuid::Uuid::new_v4().to_string();
    let bot = User::new_bot(id.clone(), username.to_string(), BotDifficulty::Easy);
    state.user_repo.save(&bot).await.unwrap();
    id
}

/// Three humans in a started party; returns (party id, tokens by player index)
async fn started_party(app: &mut Router, prefix: &str) -> (String, Vec<String>) {
    let (owner, _) = register(app, &format!("{prefix}_a")).await;
    let (second, _) = register(app, &format!("{prefix}_b")).await;
    let (third, _) = register(app, &format!("{prefix}_c")).await;
    let party_id = create_party(app, &owner, &format!("{prefix} party")).await;
    for token in [&second, &third] {
        let (status, body) = post_json_auth(
            app,
            &format!("/api/party/{party_id}/join"),
            json!({}),
            token,
        )
        .await;
        assert_eq!(status, StatusCode::OK, "join: {body}");
    }
    let (status, body) = post_json_auth(
        app,
        &format!("/api/party/{party_id}/start"),
        json!({}),
        &owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "start: {body}");
    (party_id, vec![owner, second, third])
}

/// Replace the stored game state: hands, scores, current turn and action
async fn set_game_state(
    state: &AppState,
    party_id: &str,
    hands: &[&[u8]],
    scores: &[u16],
    turn: u8,
    action: GameAction,
) {
    let mut gs = state
        .party_repo
        .get_game_state(party_id)
        .await
        .unwrap()
        .expect("game state");
    for (i, hand) in hands.iter().enumerate() {
        gs.hands[i] = smallvec::SmallVec::from_slice(hand);
    }
    for (i, score) in scores.iter().enumerate() {
        gs.scores[i] = *score;
    }
    gs.current_turn = turn;
    gs.current_action = action;
    state
        .party_repo
        .save_game_state(party_id, &gs)
        .await
        .unwrap();
}

/// Replace the played pile; `empty_deck` also empties the deck and the discard pile
async fn set_piles(state: &AppState, party_id: &str, played: &[u8], empty_deck: bool) {
    let mut gs = state
        .party_repo
        .get_game_state(party_id)
        .await
        .unwrap()
        .expect("game state");
    gs.last_cards_played = smallvec::SmallVec::from_slice(played);
    if empty_deck {
        gs.deck.clear();
        gs.discard_pile.clear();
    }
    state
        .party_repo
        .save_game_state(party_id, &gs)
        .await
        .unwrap();
}

/// Assert a Node-shaped error: the status, the code, a string `error`
fn assert_error(status: StatusCode, body: &Value, want_status: StatusCode, want_code: &str) {
    assert_eq!(status, want_status, "body: {body}");
    assert_eq!(body["code"], want_code, "body: {body}");
    assert!(body["error"].is_string(), "body: {body}");
}

// ============================================================================
// Party route family: client errors answer Node's status and code, never 500
// ============================================================================

#[tokio::test]
async fn test_join_party_errors() {
    let mut app = create_test_app().await;
    let (owner, _) = register(&mut app, "join_owner").await;
    let (other, _) = register(&mut app, "join_other").await;
    let party_id = create_party(&mut app, &owner, "Join errors").await;

    let (status, body) = post_json_auth(&mut app, "/api/party/nope/join", json!({}), &other).await;
    assert_error(status, &body, StatusCode::NOT_FOUND, "PARTY_NOT_FOUND");

    // The owner is already seated: 409, not the 500 of the old message matching
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/join"),
        json!({}),
        &owner,
    )
    .await;
    assert_error(status, &body, StatusCode::CONFLICT, "ALREADY_IN_PARTY");

    // A second human still joins: the errors above left the party intact
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/join"),
        json!({}),
        &other,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "join: {body}");
}

#[tokio::test]
async fn test_join_started_party_is_409() {
    let mut app = create_test_app().await;
    let (party_id, _) = started_party(&mut app, "late").await;
    let (late, _) = register(&mut app, "late_d").await;

    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/join"),
        json!({}),
        &late,
    )
    .await;
    assert_error(status, &body, StatusCode::CONFLICT, "PARTY_STARTED");
}

#[tokio::test]
async fn test_join_full_party_is_409() {
    let (mut app, state) = create_test_app_with_state().await;
    let (owner, _) = register(&mut app, "full_owner").await;
    let (late, _) = register(&mut app, "full_late").await;
    let party_id = create_party(&mut app, &owner, "Full party").await;
    for i in 0..7 {
        let bot_id = create_bot(&state, &format!("full_bot_{i}")).await;
        let (status, body) = post_json_auth(
            &mut app,
            &format!("/api/party/{party_id}/bots"),
            json!({"botId": bot_id}),
            &owner,
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "add bot {i}: {body}");
    }

    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/join"),
        json!({}),
        &late,
    )
    .await;
    assert_error(status, &body, StatusCode::CONFLICT, "PARTY_FULL");
}

#[tokio::test]
async fn test_leave_party_errors() {
    let mut app = create_test_app().await;
    let (owner, _) = register(&mut app, "leave_owner").await;
    let (outsider, _) = register(&mut app, "leave_outsider").await;
    let party_id = create_party(&mut app, &owner, "Leave errors").await;

    let (status, body) = post_json_auth(&mut app, "/api/party/nope/leave", json!({}), &owner).await;
    assert_error(status, &body, StatusCode::NOT_FOUND, "PARTY_NOT_FOUND");

    // Not a member: 403 NOT_IN_PARTY, not the 500 of the old exact-message match
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/leave"),
        json!({}),
        &outsider,
    )
    .await;
    assert_error(status, &body, StatusCode::FORBIDDEN, "NOT_IN_PARTY");

    // During a game: 409 (Node answers 500 here)
    let (started_id, tokens) = started_party(&mut app, "leave_game").await;
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{started_id}/leave"),
        json!({}),
        &tokens[1],
    )
    .await;
    assert_error(status, &body, StatusCode::CONFLICT, "PARTY_PLAYING");
}

#[tokio::test]
async fn test_start_party_errors() {
    let mut app = create_test_app().await;
    let (owner, _) = register(&mut app, "start_owner").await;
    let (member, _) = register(&mut app, "start_member").await;
    let party_id = create_party(&mut app, &owner, "Start errors").await;
    post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/join"),
        json!({}),
        &member,
    )
    .await;

    let (status, body) = post_json_auth(&mut app, "/api/party/nope/start", json!({}), &owner).await;
    assert_error(status, &body, StatusCode::NOT_FOUND, "PARTY_NOT_FOUND");

    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/start"),
        json!({}),
        &member,
    )
    .await;
    assert_error(status, &body, StatusCode::FORBIDDEN, "NOT_OWNER");

    // Two players: 400 (Node answers 500 here)
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/start"),
        json!({}),
        &owner,
    )
    .await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "NOT_ENOUGH_PLAYERS");

    let (started_id, tokens) = started_party(&mut app, "restart").await;
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{started_id}/start"),
        json!({}),
        &tokens[0],
    )
    .await;
    assert_error(status, &body, StatusCode::CONFLICT, "PARTY_ALREADY_PLAYING");
}

#[tokio::test]
async fn test_delete_party_errors() {
    let mut app = create_test_app().await;
    let (owner, _) = register(&mut app, "del_owner").await;
    let (member, _) = register(&mut app, "del_member").await;
    let party_id = create_party(&mut app, &owner, "Delete errors").await;
    post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/join"),
        json!({}),
        &member,
    )
    .await;

    let (status, body) = send_raw(
        &mut app,
        "DELETE",
        "/api/party/nope",
        "",
        None,
        Some(&owner),
    )
    .await;
    assert_error(status, &body, StatusCode::NOT_FOUND, "PARTY_NOT_FOUND");

    let (status, body) = send_raw(
        &mut app,
        "DELETE",
        &format!("/api/party/{party_id}"),
        "",
        None,
        Some(&member),
    )
    .await;
    assert_error(status, &body, StatusCode::FORBIDDEN, "NOT_AUTHORIZED");

    // During a game: 409, not the 500 of the old "active game" match
    let (started_id, tokens) = started_party(&mut app, "del_game").await;
    let (status, body) = send_raw(
        &mut app,
        "DELETE",
        &format!("/api/party/{started_id}"),
        "",
        None,
        Some(&tokens[0]),
    )
    .await;
    assert_error(status, &body, StatusCode::CONFLICT, "PARTY_PLAYING");
}

#[tokio::test]
async fn test_get_party_details_not_found() {
    let mut app = create_test_app().await;
    let (token, _) = register(&mut app, "details_user").await;

    let (status, body) = get_auth(&mut app, "/api/party/nope", &token).await;
    assert_error(status, &body, StatusCode::NOT_FOUND, "PARTY_NOT_FOUND");
}

#[tokio::test]
async fn test_create_party_unreadable_body_is_400_json() {
    let mut app = create_test_app().await;
    let (token, _) = register(&mut app, "body_creator").await;

    // Malformed JSON: 400 with a JSON body, not axum's 422 plain text
    let (status, body) = send_raw(
        &mut app,
        "POST",
        "/api/party",
        "{\"name\": ",
        Some("application/json"),
        Some(&token),
    )
    .await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "VALIDATION_ERROR");

    // A mistyped field
    let (status, body) = post_json_auth(
        &mut app,
        "/api/party",
        json!({"name": "Typed", "settings": {"handSize": "five"}}),
        &token,
    )
    .await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "VALIDATION_ERROR");

    // No JSON content type reads as an empty body, as on Express: the name is missing
    let (status, body) = send_raw(
        &mut app,
        "POST",
        "/api/party",
        "name=Plain",
        Some("text/plain"),
        Some(&token),
    )
    .await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "MISSING_PARTY_NAME");
}

// ============================================================================
// partyCreated event, isMyTurn, adding a bot
// ============================================================================

#[tokio::test]
async fn test_create_party_emits_party_created() {
    let (mut app, state) = create_test_app_with_state().await;
    let (token, user_id) = register(&mut app, "event_creator").await;
    let mut receiver = state.event_sender.new_receiver();

    let party_id = create_party(&mut app, &token, "Evented party").await;

    let mut created = Vec::new();
    while let Ok(event) = receiver.try_recv() {
        if event.action.as_deref() == Some("partyCreated") {
            created.push(event);
        }
    }
    assert_eq!(created.len(), 1, "one partyCreated event");
    let event = serde_json::to_value(&created[0]).unwrap();
    assert_eq!(event["type"], "partyUpdate");
    assert_eq!(event["partyId"], party_id);
    assert_eq!(event["userId"], user_id);
    assert_eq!(event["action"], "partyCreated");
}

#[tokio::test]
async fn test_list_parties_is_my_turn() {
    let (mut app, state) = create_test_app_with_state().await;
    let (party_id, tokens) = started_party(&mut app, "turn").await;
    let (outsider, _) = register(&mut app, "turn_outsider").await;
    let waiting_id = create_party(&mut app, &tokens[0], "Turn waiting").await;

    set_game_state(&state, &party_id, &[], &[], 1, GameAction::Play).await;

    let is_my_turn = |body: &Value, id: &str| {
        body["parties"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["id"] == id)
            .map(|p| p["isMyTurn"].clone())
            .unwrap_or(Value::Null)
    };
    for (index, token) in tokens.iter().enumerate() {
        let (status, body) = get_auth(&mut app, "/api/party", token).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(
            is_my_turn(&body, &party_id),
            json!(index == 1),
            "player {index}"
        );
        assert_eq!(is_my_turn(&body, &waiting_id), json!(false));
    }
    let (_, body) = get_auth(&mut app, "/api/party", &outsider).await;
    assert_eq!(is_my_turn(&body, &party_id), json!(false), "non-member");

    // A finished round is nobody's turn
    set_game_state(&state, &party_id, &[], &[], 1, GameAction::Finished).await;
    let (_, body) = get_auth(&mut app, "/api/party", &tokens[1]).await;
    assert_eq!(is_my_turn(&body, &party_id), json!(false), "finished round");
}

#[tokio::test]
async fn test_add_bot_to_waiting_party() {
    let (mut app, state) = create_test_app_with_state().await;
    let (owner, _) = register(&mut app, "bot_owner").await;
    let party_id = create_party(&mut app, &owner, "Bot seats").await;
    let bot_id = create_bot(&state, "seat_bot").await;
    let mut receiver = state.event_sender.new_receiver();

    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/bots"),
        json!({"botId": bot_id}),
        &owner,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {body}");
    assert_eq!(body["success"], true);
    assert_eq!(body["playerIndex"], 1);
    assert_eq!(body["bot"]["id"], bot_id);
    assert_eq!(body["bot"]["botDifficulty"], "easy");

    let event = receiver.try_recv().expect("playerJoined event");
    assert_eq!(event.action.as_deref(), Some("playerJoined"));
    assert_eq!(event.party_id.as_deref(), Some(party_id.as_str()));
    assert_eq!(event.user_id.as_deref(), Some(bot_id.as_str()));

    let (_, details) = get_auth(&mut app, &format!("/api/party/{party_id}"), &owner).await;
    assert_eq!(details["players"].as_array().unwrap().len(), 2);
}

#[tokio::test]
async fn test_add_bot_errors() {
    let (mut app, state) = create_test_app_with_state().await;
    let (owner, _) = register(&mut app, "bote_owner").await;
    let (member, member_id) = register(&mut app, "bote_member").await;
    let party_id = create_party(&mut app, &owner, "Bot errors").await;
    post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/join"),
        json!({}),
        &member,
    )
    .await;
    let bot_id = create_bot(&state, "bote_bot").await;
    let path = format!("/api/party/{party_id}/bots");

    let (status, body) = post_json_auth(&mut app, &path, json!({}), &owner).await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "MISSING_BOT_ID");

    let (status, body) = post_json_auth(&mut app, &path, json!({"botId": 7}), &owner).await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "MISSING_BOT_ID");

    let (status, body) = post_json_auth(&mut app, &path, json!({"botId": bot_id}), &member).await;
    assert_error(status, &body, StatusCode::FORBIDDEN, "NOT_OWNER");

    let (status, body) = post_json_auth(&mut app, &path, json!({"botId": "nobody"}), &owner).await;
    assert_error(status, &body, StatusCode::NOT_FOUND, "BOT_NOT_FOUND");

    let (status, body) = post_json_auth(&mut app, &path, json!({"botId": member_id}), &owner).await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "NOT_A_BOT");

    let (status, _) = post_json_auth(&mut app, &path, json!({"botId": bot_id}), &owner).await;
    assert_eq!(status, StatusCode::CREATED);
    let (status, body) = post_json_auth(&mut app, &path, json!({"botId": bot_id}), &owner).await;
    assert_error(status, &body, StatusCode::CONFLICT, "ALREADY_IN_PARTY");

    let (status, body) = post_json_auth(
        &mut app,
        "/api/party/nope/bots",
        json!({"botId": bot_id}),
        &owner,
    )
    .await;
    assert_error(status, &body, StatusCode::NOT_FOUND, "PARTY_NOT_FOUND");

    // A full party: 5 more bots make 8 players
    for i in 0..5 {
        let id = create_bot(&state, &format!("bote_fill_{i}")).await;
        let (status, _) = post_json_auth(&mut app, &path, json!({"botId": id}), &owner).await;
        assert_eq!(status, StatusCode::CREATED);
    }
    let extra = create_bot(&state, "bote_extra").await;
    let (status, body) = post_json_auth(&mut app, &path, json!({"botId": extra}), &owner).await;
    assert_error(status, &body, StatusCode::CONFLICT, "PARTY_FULL");

    // A started party
    let (started_id, tokens) = started_party(&mut app, "bote_started").await;
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{started_id}/bots"),
        json!({"botId": extra}),
        &tokens[0],
    )
    .await;
    assert_error(status, &body, StatusCode::CONFLICT, "PARTY_STARTED");
}

// ============================================================================
// Game route family: client errors answer Node's status and code, never 500
// ============================================================================

#[tokio::test]
async fn test_game_actions_on_missing_or_waiting_party() {
    let mut app = create_test_app().await;
    let (owner, _) = register(&mut app, "gw_owner").await;
    let party_id = create_party(&mut app, &owner, "Waiting game").await;

    let actions = [
        ("selectHandSize", json!({"handSize": 5})),
        ("play", json!({"cardIds": [1]})),
        ("draw", json!({"source": "deck"})),
        ("zapzap", json!({})),
        ("nextRound", json!({})),
    ];
    for (action, body) in &actions {
        let (status, resp) = post_json_auth(
            &mut app,
            &format!("/api/game/nope/{action}"),
            body.clone(),
            &owner,
        )
        .await;
        assert_error(status, &resp, StatusCode::NOT_FOUND, "PARTY_NOT_FOUND");

        // Node answers 500 for these on a party that is not playing, except nextRound
        let (status, resp) = post_json_auth(
            &mut app,
            &format!("/api/game/{party_id}/{action}"),
            body.clone(),
            &owner,
        )
        .await;
        assert_error(
            status,
            &resp,
            StatusCode::BAD_REQUEST,
            "INVALID_PARTY_STATE",
        );
    }

    let (status, body) = get_auth(&mut app, "/api/game/nope/state", &owner).await;
    assert_error(status, &body, StatusCode::NOT_FOUND, "PARTY_NOT_FOUND");
}

#[tokio::test]
async fn test_game_action_errors() {
    let (mut app, state) = create_test_app_with_state().await;
    let (party_id, tokens) = started_party(&mut app, "ga").await;
    let (outsider, _) = register(&mut app, "ga_outsider").await;
    let path = |action: &str| format!("/api/game/{party_id}/{action}");

    // Not a member: 403 NOT_IN_PARTY on every action (was 500)
    for (action, body) in [
        ("selectHandSize", json!({"handSize": 5})),
        ("play", json!({"cardIds": [1]})),
        ("draw", json!({"source": "deck"})),
        ("zapzap", json!({})),
    ] {
        let (status, resp) = post_json_auth(&mut app, &path(action), body, &outsider).await;
        assert_error(status, &resp, StatusCode::FORBIDDEN, "NOT_IN_PARTY");
    }

    // Hand size phase, player 0's turn
    set_game_state(&state, &party_id, &[], &[], 0, GameAction::SelectHandSize).await;
    let (status, body) = post_json_auth(
        &mut app,
        &path("selectHandSize"),
        json!({"handSize": 5}),
        &tokens[1],
    )
    .await;
    assert_error(status, &body, StatusCode::FORBIDDEN, "NOT_YOUR_TURN");
    let (status, body) = post_json_auth(
        &mut app,
        &path("selectHandSize"),
        json!({"handSize": 3}),
        &tokens[0],
    )
    .await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "INVALID_HAND_SIZE");
    let (status, body) =
        post_json_auth(&mut app, &path("play"), json!({"cardIds": [1]}), &tokens[0]).await;
    assert_error(
        status,
        &body,
        StatusCode::BAD_REQUEST,
        "INVALID_ACTION_STATE",
    );
    let (status, body) = post_json_auth(&mut app, &path("nextRound"), json!({}), &tokens[0]).await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "ROUND_NOT_FINISHED");

    // Play phase, player 0 holds A♠ 2♠ 3♠ K♠ (1 + 2 + 3 + 13 points)
    let hands: [&[u8]; 3] = [&[0, 1, 2, 12], &[13, 14, 15], &[26, 27, 28]];
    set_game_state(&state, &party_id, &hands, &[], 0, GameAction::Play).await;
    let (status, body) =
        post_json_auth(&mut app, &path("play"), json!({"cardIds": [1]}), &tokens[2]).await;
    assert_error(status, &body, StatusCode::FORBIDDEN, "NOT_YOUR_TURN");
    let (status, body) = post_json_auth(
        &mut app,
        &path("play"),
        json!({"cardIds": [40]}),
        &tokens[0],
    )
    .await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "INVALID_CARDS");
    let (status, body) = post_json_auth(
        &mut app,
        &path("play"),
        json!({"cardIds": [0, 12]}),
        &tokens[0],
    )
    .await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "INVALID_PLAY");
    let (status, body) =
        post_json_auth(&mut app, &path("play"), json!({"cardIds": []}), &tokens[0]).await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "MISSING_CARDS");
    let (status, body) = post_json_auth(
        &mut app,
        &path("draw"),
        json!({"source": "deck"}),
        &tokens[0],
    )
    .await;
    assert_error(
        status,
        &body,
        StatusCode::BAD_REQUEST,
        "INVALID_ACTION_STATE",
    );
    let (status, body) = post_json_auth(
        &mut app,
        &path("draw"),
        json!({"source": "hand"}),
        &tokens[0],
    )
    .await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "INVALID_SOURCE");
    let (status, body) = post_json_auth(&mut app, &path("zapzap"), json!({}), &tokens[0]).await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "HAND_TOO_HIGH");

    // Draw phase, one played card (5♠) on the pile
    set_game_state(&state, &party_id, &hands, &[], 0, GameAction::Draw).await;
    set_piles(&state, &party_id, &[4], false).await;
    let (status, body) = post_json_auth(
        &mut app,
        &path("draw"),
        json!({"source": "played", "cardId": 51}),
        &tokens[0],
    )
    .await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "CARD_NOT_AVAILABLE");

    // No played card left, then no deck nor discard to reshuffle
    set_piles(&state, &party_id, &[], true).await;
    let (status, body) = post_json_auth(
        &mut app,
        &path("draw"),
        json!({"source": "played"}),
        &tokens[0],
    )
    .await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "NO_CARDS_AVAILABLE");
    let (status, body) = post_json_auth(
        &mut app,
        &path("draw"),
        json!({"source": "deck"}),
        &tokens[0],
    )
    .await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "DECK_EMPTY");
    let (status, body) = post_json_auth(&mut app, &path("zapzap"), json!({}), &tokens[0]).await;
    assert_error(
        status,
        &body,
        StatusCode::BAD_REQUEST,
        "INVALID_ACTION_STATE",
    );
}

#[tokio::test]
async fn test_game_bodies_missing_field_are_400_json() {
    let mut app = create_test_app().await;
    let (party_id, tokens) = started_party(&mut app, "gb").await;
    let token = Some(tokens[0].as_str());
    let path = |action: &str| format!("/api/game/{party_id}/{action}");
    let json_ct = Some("application/json");

    let cases = [
        ("play", "{}", "MISSING_CARDS"),
        ("play", "{\"cardIds\": \"1\"}", "MISSING_CARDS"),
        ("play", "{\"cardIds\": [", "MISSING_CARDS"),
        ("draw", "{}", "INVALID_SOURCE"),
        ("draw", "{\"source\": 3}", "INVALID_SOURCE"),
        ("draw", "not json", "INVALID_SOURCE"),
        ("selectHandSize", "{}", "INVALID_HAND_SIZE"),
        (
            "selectHandSize",
            "{\"handSize\": \"5\"}",
            "INVALID_HAND_SIZE",
        ),
        ("selectHandSize", "{\"handSize\": 5.5}", "INVALID_HAND_SIZE"),
    ];
    for (action, raw, code) in cases {
        let (status, body) = send_raw(&mut app, "POST", &path(action), raw, json_ct, token).await;
        assert_error(status, &body, StatusCode::BAD_REQUEST, code);
    }

    // No JSON content type: read as `{}`, which misses the field
    let (status, body) = send_raw(&mut app, "POST", &path("play"), "", None, token).await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "MISSING_CARDS");
}

// ============================================================================
// zapzap response: `scores` are running totals, round points under `roundScores`
// ============================================================================

#[tokio::test]
async fn test_zapzap_scores_are_running_totals() {
    let (mut app, state) = create_test_app_with_state().await;
    let (party_id, tokens) = started_party(&mut app, "zz").await;

    // Player 0: A♠ 2♠ = 3 points; players 1 and 2: A 2 3 = 6 points each
    let hands: [&[u8]; 3] = [&[0, 1], &[13, 14, 15], &[26, 27, 28]];
    set_game_state(
        &state,
        &party_id,
        &hands,
        &[10, 20, 30],
        0,
        GameAction::Play,
    )
    .await;

    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/game/{party_id}/zapzap"),
        json!({}),
        &tokens[0],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["zapzapSuccess"], true);
    assert_eq!(body["counteracted"], false);
    assert_eq!(body["counteractedBy"], Value::Null);
    assert_eq!(body["scores"], json!({"0": 10, "1": 26, "2": 36}));
    assert_eq!(body["roundScores"], json!({"0": 0, "1": 6, "2": 6}));
    assert_eq!(body["handPoints"], json!({"0": 3, "1": 6, "2": 6}));
    assert_eq!(body["callerPoints"], 3);
    assert!(body.get("gameFinished").is_none());

    // The totals match what /state reports
    let (_, state_body) =
        get_auth(&mut app, &format!("/api/game/{party_id}/state"), &tokens[0]).await;
    assert_eq!(state_body["gameState"]["scores"], body["scores"]);
    assert_eq!(state_body["gameState"]["roundScores"], body["roundScores"]);
}

#[tokio::test]
async fn test_zapzap_counteracted_scores() {
    let (mut app, state) = create_test_app_with_state().await;
    let (party_id, tokens) = started_party(&mut app, "zc").await;

    // Player 1 ties the caller at 3 points: counteracted, caller gets 3 + (3 - 1) × 5
    let hands: [&[u8]; 3] = [&[0, 1], &[13, 14], &[26, 27, 28]];
    set_game_state(
        &state,
        &party_id,
        &hands,
        &[10, 20, 30],
        0,
        GameAction::Play,
    )
    .await;

    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/game/{party_id}/zapzap"),
        json!({}),
        &tokens[0],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["zapzapSuccess"], false);
    assert_eq!(body["counteracted"], true);
    assert_eq!(body["counteractedBy"], 1);
    assert_eq!(body["roundScores"], json!({"0": 13, "1": 0, "2": 6}));
    assert_eq!(body["scores"], json!({"0": 23, "1": 20, "2": 36}));
}
