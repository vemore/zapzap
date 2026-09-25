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
    // Bots pause 200 ms between actions, not production's seconds
    std::env::set_var("BOT_ACTION_DELAY_MS", "200");

    let state = AppState::new().await.expect("Failed to create app state");
    let state = Arc::new(state);

    // The application main.rs serves, fallbacks and root routes included
    let app = api::build_app(state.clone());
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
    assert!(
        body["user"]["createdAt"].is_i64(),
        "Unix seconds as Node: {body}"
    );
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

/// The stored password hash of `username`
async fn stored_hash(state: &AppState, username: &str) -> String {
    state
        .user_repo
        .find_by_username(username)
        .await
        .unwrap()
        .expect("user saved")
        .password_hash
        .expect("password user")
}

#[tokio::test]
async fn test_register_stores_node_compatible_bcrypt() {
    use zapzap_backend::infrastructure::auth::PasswordService;
    let (mut app, state) = create_test_app_with_state().await;

    register(&mut app, "bcryptreg").await;

    // Node verifies with bcryptjs only: the hash must be bcrypt at Node's cost
    let hash = stored_hash(&state, "bcryptreg").await;
    assert!(
        hash.starts_with("$2b$10$"),
        "not a Node bcrypt hash: {hash}"
    );
    assert!(PasswordService::verify("password123", &hash).unwrap());
}

#[tokio::test]
async fn test_login_leaves_the_bcrypt_hash_unchanged() {
    let (mut app, state) = create_test_app_with_state().await;

    // A user as Node wrote it: a bcryptjs 2.x `$2a$` hash of "demo123"
    let node_hash = bcrypt::hash("demo123", 10)
        .unwrap()
        .replacen("$2b$", "$2a$", 1);
    let user = User::new_human(
        uuid::Uuid::new_v4().to_string(),
        "nodeuser".to_string(),
        node_hash.clone(),
    );
    state.user_repo.save(&user).await.unwrap();

    let (status, body) = post_json(
        &mut app,
        "/api/auth/login",
        json!({"username": "nodeuser", "password": "demo123"}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "login: {body}");

    assert_eq!(stored_hash(&state, "nodeuser").await, node_hash);
}

#[tokio::test]
async fn test_login_with_an_unreadable_hash_is_401() {
    let (mut app, state) = create_test_app_with_state().await;

    // An unknown format, and a bcrypt prefix over a truncated hash
    for (username, hash) in [("badhash1", "not-a-hash"), ("badhash2", "$2b$10$short")] {
        let user = User::new_human(
            uuid::Uuid::new_v4().to_string(),
            username.to_string(),
            hash.to_string(),
        );
        state.user_repo.save(&user).await.unwrap();

        let (status, body) = post_json(
            &mut app,
            "/api/auth/login",
            json!({"username": username, "password": "demo123"}),
        )
        .await;

        assert_eq!(status, StatusCode::UNAUTHORIZED, "{username}: {body}");
        assert_eq!(body["code"], "INVALID_CREDENTIALS");
    }
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
                "playerCount": 4,
                "allowSpectators": true,
                "roundTimeLimit": 90
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
    // Node's settings keys, and only them
    assert_eq!(
        body["party"]["settings"],
        json!({"playerCount": 4, "allowSpectators": true, "roundTimeLimit": 90})
    );
    assert!(
        body["party"]["createdAt"].is_i64(),
        "Unix seconds as Node: {body}"
    );
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

/// Create a public party of `seats` (settings.playerCount) owned by `token`; returns its id
async fn create_party_with_seats(app: &mut Router, token: &str, name: &str, seats: u8) -> String {
    let (status, body) = post_json_auth(
        app,
        "/api/party",
        json!({"name": name, "settings": {"playerCount": seats}}),
        token,
    )
    .await;
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
    let party_id = create_party_with_seats(&mut app, &owner, "Full party", 8).await;
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
        json!({"name": "Typed", "settings": {"playerCount": "five"}}),
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
    let party_id = create_party_with_seats(&mut app, &owner, "Bot errors", 8).await;
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

// ============================================================================
// Review follow-ups: private parties, finished parties, seats, body limits
// ============================================================================

/// Mark a party finished, as the last zapzap of a game does
async fn finish_party(state: &AppState, party_id: &str) {
    let mut party = state
        .party_repo
        .find_by_id(party_id)
        .await
        .unwrap()
        .expect("party");
    party.finish();
    state.party_repo.save(&party).await.unwrap();
}

#[tokio::test]
async fn test_create_private_party_emits_no_event() {
    let (mut app, state) = create_test_app_with_state().await;
    let (token, _) = register(&mut app, "private_creator").await;
    let mut receiver = state.event_sender.new_receiver();

    let (status, body) = post_json_auth(
        &mut app,
        "/api/party",
        json!({"name": "Hidden party", "visibility": "private"}),
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {body}");

    while let Ok(event) = receiver.try_recv() {
        assert_ne!(
            event.action.as_deref(),
            Some("partyCreated"),
            "a private party is not announced"
        );
    }
}

#[tokio::test]
async fn test_leave_finished_party_is_200() {
    let (mut app, state) = create_test_app_with_state().await;
    let (party_id, tokens) = started_party(&mut app, "leave_fin").await;
    finish_party(&state, &party_id).await;

    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/leave"),
        json!({}),
        &tokens[1],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["success"], true);
}

#[tokio::test]
async fn test_start_finished_party_is_409() {
    let (mut app, state) = create_test_app_with_state().await;
    let (party_id, tokens) = started_party(&mut app, "start_fin").await;
    finish_party(&state, &party_id).await;

    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/start"),
        json!({}),
        &tokens[0],
    )
    .await;
    assert_error(status, &body, StatusCode::CONFLICT, "PARTY_ALREADY_PLAYING");
    assert_eq!(body["error"], "Party has finished");
}

/// The seats of a party, from its details
async fn seats(app: &mut Router, party_id: &str, token: &str) -> Vec<u64> {
    let (_, details) = get_auth(app, &format!("/api/party/{party_id}"), token).await;
    let mut seats: Vec<u64> = details["players"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["playerIndex"].as_u64().unwrap())
        .collect();
    seats.sort();
    seats
}

#[tokio::test]
async fn test_join_after_leave_takes_the_free_seat() {
    let mut app = create_test_app().await;
    let (a, _) = register(&mut app, "seat_a").await;
    let (b, _) = register(&mut app, "seat_b").await;
    let (c, _) = register(&mut app, "seat_c").await;
    let (d, _) = register(&mut app, "seat_d").await;
    let party_id = create_party(&mut app, &a, "Seats").await;
    let path = |action: &str| format!("/api/party/{party_id}/{action}");

    for token in [&b, &c] {
        let (status, _) = post_json_auth(&mut app, &path("join"), json!({}), token).await;
        assert_eq!(status, StatusCode::OK);
    }
    let (status, _) = post_json_auth(&mut app, &path("leave"), json!({}), &b).await;
    assert_eq!(status, StatusCode::OK);

    // Seats 0 and 2 are held: `players.len()` = 2 would collide, the free seat is 1
    let (status, body) = post_json_auth(&mut app, &path("join"), json!({}), &d).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["playerIndex"], 1);
    assert_eq!(seats(&mut app, &party_id, &a).await, vec![0, 1, 2]);

    let (status, body) = post_json_auth(&mut app, &path("start"), json!({}), &a).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    for token in [&a, &c, &d] {
        let (status, body) =
            get_auth(&mut app, &format!("/api/game/{party_id}/state"), token).await;
        assert_eq!(status, StatusCode::OK, "body: {body}");
        assert!(!body["gameState"]["playerHand"]
            .as_array()
            .unwrap()
            .is_empty());
    }
}

#[tokio::test]
async fn test_start_renumbers_seats_left_with_a_gap() {
    let mut app = create_test_app().await;
    let (a, _) = register(&mut app, "gap_a").await;
    let (b, _) = register(&mut app, "gap_b").await;
    let (c, _) = register(&mut app, "gap_c").await;
    let (d, _) = register(&mut app, "gap_d").await;
    let party_id = create_party(&mut app, &a, "Gap").await;
    let path = |action: &str| format!("/api/party/{party_id}/{action}");
    for token in [&b, &c, &d] {
        post_json_auth(&mut app, &path("join"), json!({}), token).await;
    }
    post_json_auth(&mut app, &path("leave"), json!({}), &b).await;
    assert_eq!(seats(&mut app, &party_id, &a).await, vec![0, 2, 3]);

    // The game state knows seats 0..n-1 only: start closes the gap
    let (status, body) = post_json_auth(&mut app, &path("start"), json!({}), &a).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(seats(&mut app, &party_id, &a).await, vec![0, 1, 2]);
    for token in [&a, &c, &d] {
        let (status, body) =
            get_auth(&mut app, &format!("/api/game/{party_id}/state"), token).await;
        assert_eq!(status, StatusCode::OK, "body: {body}");
        assert!(!body["gameState"]["playerHand"]
            .as_array()
            .unwrap()
            .is_empty());
    }
}

#[tokio::test]
async fn test_add_party_player_twice_is_already_exists() {
    let (mut app, state) = create_test_app_with_state().await;
    let (token, user_id) = register(&mut app, "twice_owner").await;
    let party_id = create_party(&mut app, &token, "Twice").await;

    // A second seat for the same user: what a concurrent join or add-bot runs into
    let err = state
        .party_repo
        .add_party_player(&party_id, &user_id, 5)
        .await
        .unwrap_err();
    assert!(
        matches!(
            err,
            zapzap_backend::domain::repositories::RepositoryError::AlreadyExists(_)
        ),
        "{err:?}"
    );
}

#[tokio::test]
async fn test_play_card_ids_out_of_range_are_invalid_cards() {
    let mut app = create_test_app().await;
    let (party_id, tokens) = started_party(&mut app, "range").await;
    let path = format!("/api/game/{party_id}/play");

    for ids in [json!([300]), json!([-1]), json!(["a"]), json!([1, 999])] {
        let (status, body) =
            post_json_auth(&mut app, &path, json!({ "cardIds": ids }), &tokens[0]).await;
        assert_error(status, &body, StatusCode::BAD_REQUEST, "INVALID_CARDS");
    }
    // Missing or not an array stays the route's missing-field code
    for body in [json!({}), json!({"cardIds": null}), json!({"cardIds": 3})] {
        let (status, resp) = post_json_auth(&mut app, &path, body, &tokens[0]).await;
        assert_error(status, &resp, StatusCode::BAD_REQUEST, "MISSING_CARDS");
    }
}

#[tokio::test]
async fn test_body_too_large_is_413() {
    let mut app = create_test_app().await;
    let (token, _) = register(&mut app, "big_body").await;

    // Past axum's 2 MB default body limit
    let big = format!("{{\"name\": \"{}\"}}", "x".repeat(3 * 1024 * 1024));
    let (status, body) = send_raw(
        &mut app,
        "POST",
        "/api/party",
        &big,
        Some("application/json"),
        Some(&token),
    )
    .await;
    assert_error(
        status,
        &body,
        StatusCode::PAYLOAD_TOO_LARGE,
        "PAYLOAD_TOO_LARGE",
    );
}

// ============================================================================
// Security: JWT secret, authorization, SSE filtering
// ============================================================================

/// Create a party owned by the token's user; returns its id and invite code.
async fn create_party_visible(app: &mut Router, token: &str, visibility: &str) -> (String, String) {
    let (status, body) = post_json_auth(
        app,
        "/api/party",
        json!({ "name": "Table", "visibility": visibility }),
        token,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "create party: {body}");
    (
        body["party"]["id"].as_str().unwrap().to_string(),
        body["party"]["inviteCode"].as_str().unwrap().to_string(),
    )
}

/// A request without any Authorization header.
async fn request_no_auth(app: &mut Router, method: &str, path: &str) -> (StatusCode, Value) {
    let request = Request::builder()
        .method(method)
        .uri(path)
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
    (
        status,
        serde_json::from_slice(&body_bytes).unwrap_or(Value::Null),
    )
}

/// Run the server binary with `jwt_secret` (None: unset) and return its exit status and
/// stderr; a server still running after 20 s is killed and reported as such.
fn run_server_binary(jwt_secret: Option<&str>) -> (Option<std::process::ExitStatus>, String) {
    use std::io::Read;
    use std::process::{Command, Stdio};

    // An empty working directory with no .env in it or above it (dotenvy looks upwards)
    let dir = std::env::temp_dir().join(format!(
        "zapzap-jwt-test-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&dir).unwrap();

    let mut cmd = Command::new(env!("CARGO_BIN_EXE_zapzap-backend"));
    cmd.current_dir(&dir)
        .env_clear()
        .env("DATABASE_URL", "sqlite::memory:")
        .env("PORT", "0")
        .env("RUST_LOG", "off")
        .stdout(Stdio::null())
        .stderr(Stdio::piped());
    if let Some(secret) = jwt_secret {
        cmd.env("JWT_SECRET", secret);
    }
    let mut child = cmd.spawn().expect("start the server binary");

    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(20);
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            break Some(status);
        }
        if std::time::Instant::now() > deadline {
            let _ = child.kill();
            let _ = child.wait();
            break None;
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    };
    let mut stderr = String::new();
    child
        .stderr
        .take()
        .unwrap()
        .read_to_string(&mut stderr)
        .unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    (status, stderr)
}

#[test]
fn test_server_refuses_to_start_without_jwt_secret() {
    let (status, stderr) = run_server_binary(None);
    let status = status.expect("the server kept running without JWT_SECRET");
    assert!(!status.success());
    assert!(stderr.contains("JWT_SECRET is not set"), "stderr: {stderr}");

    // The default the code and the compose file used to carry is public: refused too
    let (status, stderr) = run_server_binary(Some("zapzap-secret-key-change-in-production"));
    let status = status.expect("the server kept running with the public default secret");
    assert!(!status.success());
    assert!(stderr.contains("placeholder"), "stderr: {stderr}");
}

#[test]
fn test_rust_compose_takes_jwt_secret_from_the_environment_without_default() {
    let compose = include_str!("../docker-compose.yml");
    let line = compose
        .lines()
        .find(|l| l.trim_start().starts_with("- JWT_SECRET="))
        .expect("JWT_SECRET in zapzap-rust/docker-compose.yml");
    assert!(
        line.contains("${JWT_SECRET:?"),
        "compose must refuse to start without JWT_SECRET: {line}"
    );
    assert!(!line.contains(":-"), "no default for JWT_SECRET: {line}");
}

#[tokio::test]
async fn test_join_private_party_requires_its_invite_code() {
    let (mut app, _) = create_test_app_with_state().await;
    let (owner, _) = register(&mut app, "privowner").await;
    let (guest, _) = register(&mut app, "privguest").await;
    let (party_id, invite_code) = create_party_visible(&mut app, &owner, "private").await;
    let path = format!("/api/party/{party_id}/join");

    // Node answers 500 here (its messages have no branch): a Node bug, Rust says 403
    let (status, body) = post_json_auth(&mut app, &path, json!({}), &guest).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "PRIVATE_PARTY");
    assert_eq!(body["error"], "Party is private. Use invite code to join.");

    let (status, body) =
        post_json_auth(&mut app, &path, json!({ "inviteCode": "WRONG1" }), &guest).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "INVALID_INVITE_CODE");
    assert_eq!(body["error"], "Invalid invite code");

    let (status, body) = post_json_auth(
        &mut app,
        &path,
        json!({ "inviteCode": invite_code }),
        &guest,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["success"], true);
}

#[tokio::test]
async fn test_private_party_details_refused_to_non_member() {
    let (mut app, _) = create_test_app_with_state().await;
    let (owner, _) = register(&mut app, "detowner").await;
    let (stranger, _) = register(&mut app, "detstranger").await;
    let (party_id, invite_code) = create_party_visible(&mut app, &owner, "private").await;
    let path = format!("/api/party/{party_id}");

    let (status, body) = get_auth(&mut app, &path, &stranger).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "NOT_IN_PARTY");
    assert!(
        !body.to_string().contains(&invite_code),
        "the invite code leaked: {body}"
    );

    let (status, body) = get_auth(&mut app, &path, &owner).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["party"]["inviteCode"], invite_code.as_str());
}

#[tokio::test]
async fn test_game_state_refused_to_non_member() {
    let (mut app, _) = create_test_app_with_state().await;
    let (owner, _) = register(&mut app, "stateowner").await;
    let (stranger, _) = register(&mut app, "statestranger").await;
    let (party_id, _) = create_party_visible(&mut app, &owner, "public").await;

    let path = format!("/api/game/{party_id}/state");
    let (status, body) = get_auth(&mut app, &path, &stranger).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "NOT_IN_PARTY");
    assert_eq!(body["error"], "User is not in this party");

    let (status, _) = get_auth(&mut app, &path, &owner).await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn test_next_round_refused_to_non_member() {
    let (mut app, _) = create_test_app_with_state().await;
    let (owner, _) = register(&mut app, "nrowner").await;
    let (stranger, _) = register(&mut app, "nrstranger").await;
    let (party_id, _) = create_party_visible(&mut app, &owner, "public").await;

    let path = format!("/api/game/{party_id}/nextRound");
    let (status, body) = post_json_auth(&mut app, &path, json!({}), &stranger).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "NOT_IN_PARTY");

    let (status, body) = post_json_auth(
        &mut app,
        "/api/game/no-such-party/nextRound",
        json!({}),
        &owner,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "PARTY_NOT_FOUND");
}

#[tokio::test]
async fn test_trigger_bot_refused_to_non_member() {
    let (mut app, _) = create_test_app_with_state().await;
    let (owner, _) = register(&mut app, "tbowner").await;
    let (stranger, _) = register(&mut app, "tbstranger").await;
    let (party_id, _) = create_party_visible(&mut app, &owner, "public").await;

    let path = format!("/api/game/{party_id}/trigger-bot");
    let (status, body) = post_json_auth(&mut app, &path, json!({}), &stranger).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "NOT_IN_PARTY");

    // A member still triggers (no game state yet: nothing to do)
    let (status, body) = post_json_auth(&mut app, &path, json!({}), &owner).await;
    assert_eq!(status, StatusCode::OK, "{body}");
}

#[tokio::test]
async fn test_private_history_refused_to_non_member() {
    let (mut app, state) = create_test_app_with_state().await;
    let (owner, owner_id) = register(&mut app, "histowner").await;
    let (stranger, _) = register(&mut app, "histstranger").await;
    let (private_id, _) = create_party_visible(&mut app, &owner, "private").await;
    let (public_id, _) = create_party_visible(&mut app, &owner, "public").await;

    // Both games finished, won by the owner
    for party_id in [&private_id, &public_id] {
        sqlx::query(
            "INSERT INTO game_results (party_id, winner_user_id, winner_final_score, total_rounds,
                                       was_golden_score, player_count, finished_at, created_at)
             VALUES (?, ?, 12, 3, 0, 1, 1700000500, 1700000500)",
        )
        .bind(party_id)
        .bind(&owner_id)
        .execute(&state.db)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO player_game_results (party_id, user_id, final_score, finish_position,
                                              rounds_played, is_winner, created_at)
             VALUES (?, ?, 12, 1, 3, 1, 1700000500)",
        )
        .bind(party_id)
        .bind(&owner_id)
        .execute(&state.db)
        .await
        .unwrap();
    }

    let (status, body) = get_auth(&mut app, &format!("/api/history/{private_id}"), &stranger).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["error"], "Access denied. Party is private.");

    let (status, body) = get_auth(&mut app, &format!("/api/history/{private_id}"), &owner).await;
    assert_eq!(status, StatusCode::OK, "{body}");

    // A public game's history stays readable by anyone signed in, as in Node
    let (status, body) = get_auth(&mut app, &format!("/api/history/{public_id}"), &stranger).await;
    assert_eq!(status, StatusCode::OK, "{body}");
}

#[tokio::test]
async fn test_admin_routes_require_a_token_and_an_admin() {
    let (mut app, state) = create_test_app_with_state().await;
    let (user, _) = register(&mut app, "plainuser").await;
    let (admin, admin_id) = register(&mut app, "theadmin").await;

    let routes = [
        ("GET", "/api/admin/users"),
        ("DELETE", "/api/admin/users/someone"),
        ("POST", "/api/admin/users/someone/admin"),
        ("GET", "/api/admin/parties"),
        ("POST", "/api/admin/parties/some-party/stop"),
        ("DELETE", "/api/admin/parties/some-party"),
        ("GET", "/api/admin/statistics"),
    ];
    for (method, path) in routes {
        let (status, _) = request_no_auth(&mut app, method, path).await;
        assert_eq!(
            status,
            StatusCode::UNAUTHORIZED,
            "{method} {path} without a token"
        );
    }

    let (status, body) = get_auth(&mut app, "/api/admin/users", &user).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "ADMIN_REQUIRED");
    assert_eq!(body["error"], "Admin access required");

    // Made admin in the database: gets in at once, with the token it already had (the
    // middleware reads the flag from the database, the handlers no longer check the token)
    sqlx::query("UPDATE users SET is_admin = 1 WHERE id = ?")
        .bind(&admin_id)
        .execute(&state.db)
        .await
        .unwrap();
    let (status, body) = get_auth(&mut app, "/api/admin/statistics", &admin).await;
    assert_eq!(status, StatusCode::OK, "{body}");

    // Revoked in the database: refused at once
    sqlx::query("UPDATE users SET is_admin = 0 WHERE id = ?")
        .bind(&admin_id)
        .execute(&state.db)
        .await
        .unwrap();
    let (status, body) = get_auth(&mut app, "/api/admin/statistics", &admin).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "ADMIN_REQUIRED");
}

/// Open `/suscribeupdate` (with `token` if any); returns the response headers and body.
async fn open_sse(app: &mut Router, token: Option<&str>) -> (axum::http::HeaderMap, Body) {
    let uri = match token {
        Some(t) => format!("/suscribeupdate?token={t}"),
        None => "/suscribeupdate".to_string(),
    };
    let request = Request::builder().uri(uri).body(Body::empty()).unwrap();
    let response = ServiceExt::<Request<Body>>::ready(app)
        .await
        .unwrap()
        .call(request)
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let headers = response.headers().clone();
    (headers, response.into_body())
}

/// Read the SSE body until `sentinel` shows up; returns everything read.
async fn read_sse_until(body: &mut Body, sentinel: &str) -> String {
    let mut text = String::new();
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(10);
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

#[tokio::test]
async fn test_sse_client_receives_only_its_parties_events() {
    use zapzap_backend::infrastructure::app_state::GameEvent;

    let (mut app, state) = create_test_app_with_state().await;
    let (alice, alice_id) = register(&mut app, "ssealice").await;
    let (bob, bob_id) = register(&mut app, "ssebob").await;
    let (alice_party, _) = create_party_visible(&mut app, &alice, "public").await;
    let (bob_party, _) = create_party_visible(&mut app, &bob, "public").await;

    let (headers, mut alice_stream) = open_sse(&mut app, Some(&alice)).await;
    assert_eq!(headers["x-accel-buffering"], "no");
    let (_, mut anonymous_stream) = open_sse(&mut app, None).await;

    let party_event = |party: &str, user: &str, marker: &str| {
        GameEvent::new(
            "gameUpdate",
            Some(party.to_string()),
            Some(user.to_string()),
        )
        .with_action("play")
        .with_data(json!({ "marker": marker }))
    };
    state.broadcast_event(party_event(&bob_party, &bob_id, "bob-party-event"));
    state.broadcast_event(party_event(&alice_party, &alice_id, "alice-party-event"));
    // A global event (no party), as Node sends userConnected/userStatusChanged to everyone
    state.broadcast_event(
        GameEvent::new("userStatusChanged", None, Some(bob_id.clone()))
            .with_data(json!({ "marker": "global-sentinel" })),
    );

    let alice_saw = read_sse_until(&mut alice_stream, "global-sentinel").await;
    assert!(alice_saw.contains("alice-party-event"), "{alice_saw}");
    assert!(!alice_saw.contains("bob-party-event"), "{alice_saw}");

    let anonymous_saw = read_sse_until(&mut anonymous_stream, "global-sentinel").await;
    assert!(!anonymous_saw.contains("party-event"), "{anonymous_saw}");
}

#[tokio::test]
async fn test_sse_public_party_lifecycle_reaches_every_stream() {
    use zapzap_backend::infrastructure::app_state::GameEvent;

    let (mut app, state) = create_test_app_with_state().await;
    let (alice, _) = register(&mut app, "lifealice").await;
    let (bob, bob_id) = register(&mut app, "lifebob").await;
    let (public_party, _) = create_party_visible(&mut app, &bob, "public").await;
    let (private_party, _) = create_party_visible(&mut app, &bob, "private").await;

    // Alice plays in neither party
    let (_, mut alice_stream) = open_sse(&mut app, Some(&alice)).await;
    let (_, mut anonymous_stream) = open_sse(&mut app, None).await;

    let event = |event_type: &str, party: &str, action: &str, data: Value| {
        GameEvent::new(event_type, Some(party.to_string()), Some(bob_id.clone()))
            .with_action(action)
            .with_data(data)
    };
    state.broadcast_event(event(
        "partyUpdate",
        &public_party,
        "playerJoined",
        json!({ "marker": "public-joined" }),
    ));
    state.broadcast_event(event(
        "partyUpdate",
        &public_party,
        "partyCreated",
        json!({ "marker": "public-created" }),
    ));
    state.broadcast_event(event(
        "gameUpdate",
        &public_party,
        "play",
        json!({ "marker": "public-move" }),
    ));
    state.broadcast_event(event(
        "partyUpdate",
        &private_party,
        "playerJoined",
        json!({ "marker": "private-joined" }),
    ));
    state.broadcast_event(event(
        "partyUpdate",
        "gone-public",
        "partyDeleted",
        json!({ "marker": "public-deleted", "visibility": "public" }),
    ));
    state.broadcast_event(event(
        "partyUpdate",
        "gone-private",
        "partyDeleted",
        json!({ "marker": "private-deleted", "visibility": "private" }),
    ));
    state.broadcast_event(
        GameEvent::new("userStatusChanged", None, None)
            .with_data(json!({ "marker": "global-sentinel" })),
    );

    for saw in [
        read_sse_until(&mut alice_stream, "global-sentinel").await,
        read_sse_until(&mut anonymous_stream, "global-sentinel").await,
    ] {
        assert!(saw.contains("public-joined"), "{saw}");
        assert!(saw.contains("public-created"), "{saw}");
        assert!(saw.contains("public-deleted"), "{saw}");
        assert!(!saw.contains("public-move"), "{saw}");
        assert!(!saw.contains("private-joined"), "{saw}");
        assert!(!saw.contains("private-deleted"), "{saw}");
    }
}

#[tokio::test]
async fn test_public_history_lists_public_games_only() {
    let (mut app, state) = create_test_app_with_state().await;
    let (owner, owner_id) = register(&mut app, "pubhistowner").await;
    let (private_id, _) = create_party_visible(&mut app, &owner, "private").await;
    let (public_id, _) = create_party_visible(&mut app, &owner, "public").await;
    for party_id in [&private_id, &public_id] {
        sqlx::query(
            "INSERT INTO game_results (party_id, winner_user_id, winner_final_score, total_rounds,
                                       was_golden_score, player_count, finished_at, created_at)
             VALUES (?, ?, 12, 3, 0, 1, 1700000500, 1700000500)",
        )
        .bind(party_id)
        .bind(&owner_id)
        .execute(&state.db)
        .await
        .unwrap();
    }

    let (status, body) = request_no_auth(&mut app, "GET", "/api/history/public").await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let ids: Vec<&str> = body["games"]
        .as_array()
        .unwrap()
        .iter()
        .map(|g| g["partyId"].as_str().unwrap())
        .collect();
    assert_eq!(ids, [public_id.as_str()], "{body}");
    assert_eq!(body["pagination"]["hasMore"], false, "{body}");
}

#[tokio::test]
async fn test_deleted_users_token_is_refused() {
    use zapzap_backend::infrastructure::app_state::GameEvent;

    let (mut app, state) = create_test_app_with_state().await;
    let (token, user_id) = register(&mut app, "goneuser").await;
    let (other, _) = register(&mut app, "stayinguser").await;
    let (private_party, _) = create_party_visible(&mut app, &other, "private").await;

    sqlx::query("DELETE FROM users WHERE id = ?")
        .bind(&user_id)
        .execute(&state.db)
        .await
        .unwrap();

    let (status, _) =
        post_json_auth(&mut app, "/api/party", json!({ "name": "Table" }), &token).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    // SSE: the token names nobody, so not even the user's own private-party action reaches
    // the stream, and the user is not marked online
    let (_, mut stream) = open_sse(&mut app, Some(&token)).await;
    state.broadcast_event(
        GameEvent::new("partyUpdate", Some(private_party), Some(user_id.clone()))
            .with_action("playerLeft")
            .with_data(json!({ "marker": "own-action" })),
    );
    state.broadcast_event(
        GameEvent::new("userStatusChanged", None, None)
            .with_data(json!({ "marker": "global-sentinel" })),
    );
    let saw = read_sse_until(&mut stream, "global-sentinel").await;
    assert!(!saw.contains("own-action"), "{saw}");
    assert!(!saw.contains("userConnected"), "{saw}");
}

/// Record a finished game won by `winner_id`, with each player's (id, score, position, won)
async fn record_finished_game(
    state: &AppState,
    party_id: &str,
    winner_id: &str,
    results: &[(&str, i32, i32, bool)],
    golden: bool,
    finished_at: i64,
) {
    sqlx::query(
        "INSERT INTO game_results (party_id, winner_user_id, winner_final_score, total_rounds,
                                   was_golden_score, player_count, finished_at, created_at)
         VALUES (?, ?, 12, 7, ?, ?, ?, ?)",
    )
    .bind(party_id)
    .bind(winner_id)
    .bind(golden)
    .bind(results.len() as i32)
    .bind(finished_at)
    .bind(finished_at)
    .execute(&state.db)
    .await
    .unwrap();
    for (user_id, score, position, winner) in results {
        sqlx::query(
            "INSERT INTO player_game_results (party_id, user_id, final_score, finish_position,
                                              rounds_played, is_winner, created_at)
             VALUES (?, ?, ?, ?, 7, ?, ?)",
        )
        .bind(party_id)
        .bind(user_id)
        .bind(score)
        .bind(position)
        .bind(winner)
        .bind(finished_at)
        .execute(&state.db)
        .await
        .unwrap();
    }
}

#[tokio::test]
async fn test_history_listings_carry_nodes_keys() {
    let (mut app, state) = create_test_app_with_state().await;
    let (owner, owner_id) = register(&mut app, "keyhistowner").await;
    let (_, rival_id) = register(&mut app, "keyhistrival").await;
    let (older, _) = create_party_visible(&mut app, &owner, "public").await;
    let (newer, _) = create_party_visible(&mut app, &owner, "public").await;
    let results = [
        (owner_id.as_str(), 12, 1, true),
        (rival_id.as_str(), 80, 2, false),
    ];
    record_finished_game(&state, &older, &owner_id, &results, false, 1700000100).await;
    record_finished_game(&state, &newer, &owner_id, &results, true, 1700000200).await;

    // Mine, one per page: the newest game, with Node's keys and the caller's own result
    let (status, body) = get_auth(&mut app, "/api/history?limit=1", &owner).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let game = &body["games"][0];
    assert!(game["id"].is_i64(), "{body}");
    assert_eq!(game["partyId"], newer.as_str());
    assert_eq!(game["winnerUserId"], owner_id.as_str());
    assert_eq!(game["winnerUsername"], "keyhistowner");
    assert_eq!(game["winnerFinalScore"], 12);
    assert_eq!(game["totalRounds"], 7);
    assert_eq!(game["wasGoldenScore"], true);
    assert_eq!(game["playerCount"], 2);
    assert_eq!(game["visibility"], "public");
    assert_eq!(game["userPlacement"], 1);
    assert_eq!(game["userScore"], 12);
    assert!(game.get("roundsPlayed").is_none(), "{body}");
    assert!(body.get("total").is_none(), "{body}");
    assert_eq!(
        body["pagination"],
        json!({ "limit": 1, "offset": 0, "hasMore": true })
    );

    let (_, body) = get_auth(&mut app, "/api/history?limit=1&offset=1", &owner).await;
    assert_eq!(body["games"][0]["partyId"], older.as_str());
    assert_eq!(body["games"][0]["wasGoldenScore"], false);

    // Public: the same entry, without visibility or a caller's result
    let (status, body) = request_no_auth(&mut app, "GET", "/api/history/public").await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let game = &body["games"][0];
    assert!(game["id"].is_i64(), "{body}");
    assert_eq!(game["winnerUserId"], owner_id.as_str());
    for absent in ["visibility", "userPlacement", "userScore", "roundsPlayed"] {
        assert!(game.get(absent).is_none(), "{absent}: {body}");
    }
    assert_eq!(
        body["pagination"],
        json!({ "limit": 20, "offset": 0, "hasMore": false })
    );
}

#[tokio::test]
async fn test_leaderboard_carries_average_score_criteria_and_pagination() {
    let (mut app, state) = create_test_app_with_state().await;
    let (owner, owner_id) = register(&mut app, "boardowner").await;
    let (_, rival_id) = register(&mut app, "boardrival").await;
    for (i, finished_at) in [1700000100, 1700000200].into_iter().enumerate() {
        let (party, _) = create_party_visible(&mut app, &owner, "public").await;
        let rival_score = 40 + 20 * i as i32;
        let results = [
            (owner_id.as_str(), 10, 1, true),
            (rival_id.as_str(), rival_score, 2, false),
        ];
        record_finished_game(&state, &party, &owner_id, &results, false, finished_at).await;
    }

    let (status, body) =
        request_no_auth(&mut app, "GET", "/api/stats/leaderboard?minGames=2&limit=1").await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let first = &body["leaderboard"][0];
    assert_eq!(first["userId"], owner_id.as_str());
    assert_eq!(first["winRate"], 1.0);
    assert_eq!(first["averageScore"], 10.0);
    assert_eq!(
        body["criteria"],
        json!({ "minGames": 2, "sortBy": "winRate" })
    );
    assert_eq!(
        body["pagination"],
        json!({ "limit": 1, "offset": 0, "hasMore": true })
    );
    assert!(body.get("total").is_none(), "{body}");

    let (_, body) = request_no_auth(
        &mut app,
        "GET",
        "/api/stats/leaderboard?minGames=2&offset=1",
    )
    .await;
    assert_eq!(body["leaderboard"][0]["userId"], rival_id.as_str());
    assert_eq!(body["leaderboard"][0]["rank"], 2);
    assert_eq!(body["leaderboard"][0]["averageScore"], 50.0);
    assert_eq!(body["pagination"]["hasMore"], false);
}

/// An admin: registered, then made admin in the database; returns (token, user id)
async fn register_admin(app: &mut Router, state: &AppState, username: &str) -> (String, String) {
    let (token, user_id) = register(app, username).await;
    sqlx::query("UPDATE users SET is_admin = 1 WHERE id = ?")
        .bind(&user_id)
        .execute(&state.db)
        .await
        .unwrap();
    (token, user_id)
}

#[tokio::test]
async fn test_admin_parties_carry_nodes_fields() {
    let (mut app, state) = create_test_app_with_state().await;
    let (admin, _) = register_admin(&mut app, &state, "partyadmin").await;
    let (owner, owner_id) = register(&mut app, "listedowner").await;
    let (party_id, invite_code) = create_party_visible(&mut app, &owner, "private").await;

    let (status, body) = get_auth(&mut app, "/api/admin/parties", &admin).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let party = &body["parties"][0];
    assert_eq!(party["id"], party_id.as_str());
    assert_eq!(party["ownerId"], owner_id.as_str());
    assert_eq!(party["ownerUsername"], "listedowner");
    assert_eq!(party["inviteCode"], invite_code.as_str());
    assert_eq!(party["visibility"], "private");
    assert_eq!(party["status"], "waiting");
    // JSON-encoded, as Node sends it and the React admin parses it
    let settings: Value = serde_json::from_str(party["settings"].as_str().unwrap()).unwrap();
    assert!(settings.is_object(), "{body}");
    assert!(party["currentRoundId"].is_null(), "{body}");
    assert_eq!(party["playerCount"], 1);
    assert!(party["createdAt"].is_i64(), "{body}");
    assert!(party["updatedAt"].is_i64(), "{body}");
    assert_eq!(body["pagination"]["total"], 1);
}

#[tokio::test]
async fn test_admin_set_admin_answers_the_user_and_the_new_right() {
    let (mut app, state) = create_test_app_with_state().await;
    let (admin, _) = register_admin(&mut app, &state, "grantadmin").await;
    let (_, user_id) = register(&mut app, "granted").await;
    let path = format!("/api/admin/users/{user_id}/admin");

    for is_admin in [true, false] {
        let (status, body) =
            post_json_auth(&mut app, &path, json!({ "isAdmin": is_admin }), &admin).await;
        assert_eq!(status, StatusCode::OK, "{body}");
        assert_eq!(
            body,
            json!({ "success": true, "userId": user_id, "username": "granted", "isAdmin": is_admin })
        );
    }
}

#[tokio::test]
async fn test_admin_delete_user_answers_who_was_deleted() {
    let (mut app, state) = create_test_app_with_state().await;
    let (admin, _) = register_admin(&mut app, &state, "deleteadmin").await;
    let (_, user_id) = register(&mut app, "deleted").await;

    let path = format!("/api/admin/users/{user_id}");
    let (status, body) = send_raw(&mut app, "DELETE", &path, "", None, Some(&admin)).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(
        body,
        json!({ "success": true, "deletedUserId": user_id, "deletedUsername": "deleted" })
    );
}

#[tokio::test]
async fn test_admin_stop_and_delete_party_answer_the_party() {
    let (mut app, state) = create_test_app_with_state().await;
    let (admin, _) = register_admin(&mut app, &state, "stopadmin").await;
    let (owner, _) = register(&mut app, "stoppedowner").await;
    let party_id = create_party(&mut app, &owner, "Stopped table").await;

    let path = format!("/api/admin/parties/{party_id}/stop");
    let (status, body) = post_json_auth(&mut app, &path, json!({}), &admin).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(
        body,
        json!({ "success": true, "partyId": party_id, "partyName": "Stopped table", "stopped": true })
    );

    let path = format!("/api/admin/parties/{party_id}");
    let (status, body) = send_raw(&mut app, "DELETE", &path, "", None, Some(&admin)).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(
        body,
        json!({ "success": true, "partyId": party_id, "partyName": "Stopped table", "deleted": true })
    );
}

// ============================================================================
// Google login and bot administration
// ============================================================================

mod google_and_bot_admin {
    use super::*;
    use jsonwebtoken::jwk::JwkSet;
    use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
    use zapzap_backend::infrastructure::services::GoogleOAuthService;

    /// Test-only RSA key; its public half is the JWK below. No network: the service gets
    /// this key set instead of Google's certs.
    const TEST_KEY_PEM: &str = include_str!("fixtures/google_oauth_test_rsa.pem");
    const TEST_KEY_N: &str = "ru3qPMAYvaU0HR8RHvqgNiQlq-XRKFtj5IkfTZaIfdiU5r_RyjSXi4Jx826eUZt38mjTFKgVd_apxmwjPxY-Odal5arEXdNuxxkHUI6_lJiZOv2qJrTRiylyipOobKWmQUrGamIT6F4tSx4wggUL7jST-EVUrI4jmdZqbx9BtYZoOUXBVK0QxEjNG4Zj7InwYEup64F7gC4nKyiFrfOQI3rsL85P7fFPttxFaZuyurMCSditw_VkAul88pIRmpf6ZvKjP6aMrTdxAuy4iaUbWyUOmPKRgG9fAWYwHptvHjyH8rjFJH2Q6SFE38Mup51QeVakOVGILMg8ZzFsl4k0Sw";
    const CLIENT_ID: &str = "api-test.apps.googleusercontent.com";

    /// The test app, with its state, and a Google verifier when `google` is true
    async fn app_with_state(google: bool) -> (Router, Arc<AppState>) {
        std::env::set_var("DATABASE_URL", "sqlite::memory:");
        std::env::set_var("JWT_SECRET", "test-secret-key");
        let mut state = AppState::new().await.expect("Failed to create app state");
        state.google_oauth = if google {
            let keys: JwkSet = serde_json::from_value(json!({
                "keys": [{"kty": "RSA", "alg": "RS256", "kid": "k1", "n": TEST_KEY_N, "e": "AQAB"}]
            }))
            .unwrap();
            Some(Arc::new(GoogleOAuthService::with_keys(
                CLIENT_ID.to_string(),
                keys,
            )))
        } else {
            None
        };
        let state = Arc::new(state);
        let app = Router::new()
            .nest("/api", api::routes::create_api_router(state.clone()))
            .with_state(state.clone());
        (app, state)
    }

    fn google_token(sub: &str, aud: &str) -> String {
        let now = chrono::Utc::now().timestamp();
        let mut header = Header::new(Algorithm::RS256);
        header.kid = Some("k1".to_string());
        encode(
            &header,
            &json!({
                "iss": "accounts.google.com", "aud": aud, "sub": sub,
                "email": "ada@example.com", "email_verified": true, "name": "Ada Lovelace",
                "iat": now, "exp": now + 600
            }),
            &EncodingKey::from_rsa_pem(TEST_KEY_PEM.as_bytes()).unwrap(),
        )
        .unwrap()
    }

    async fn delete_auth(app: &mut Router, path: &str, token: Option<&str>) -> (StatusCode, Value) {
        send_raw(app, "DELETE", path, "", None, token).await
    }

    /// Register a human and return (id, token); `admin` makes it an admin (read from the
    /// database by admin_middleware)
    async fn user_token(
        app: &mut Router,
        state: &AppState,
        name: &str,
        admin: bool,
    ) -> (String, String) {
        let (token, id) = register(app, name).await;
        if admin {
            state.user_repo.set_admin(&id, true).await.unwrap();
        }
        (id, token)
    }

    #[tokio::test]
    async fn test_google_missing_credential() {
        let (mut app, _) = app_with_state(true).await;
        for body in [
            json!({}),
            json!({"credential": ""}),
            json!({"credential": null}),
        ] {
            let (status, body) = post_json(&mut app, "/api/auth/google", body).await;
            assert_eq!(status, StatusCode::BAD_REQUEST);
            assert_eq!(body["code"], "MISSING_CREDENTIAL");
            assert_eq!(body["error"], "Token Google requis");
        }
    }

    #[tokio::test]
    async fn test_google_forged_token_is_refused() {
        let (mut app, state) = app_with_state(true).await;
        for credential in [
            "forged.token.value".to_string(),
            google_token("g-1", "another-client"),
        ] {
            let (status, body) = post_json(
                &mut app,
                "/api/auth/google",
                json!({"credential": credential}),
            )
            .await;
            assert_eq!(status, StatusCode::UNAUTHORIZED, "{body}");
            assert_eq!(body["code"], "GOOGLE_AUTH_FAILED");
        }
        assert!(state
            .user_repo
            .find_by_google_id("g-1")
            .await
            .unwrap()
            .is_none());
    }

    #[tokio::test]
    async fn test_google_not_configured() {
        // Node without GOOGLE_OAUTH_CLIENT_ID: the placeholder use case throws
        // "Google OAuth non configuré sur ce serveur", which its route answers with 401
        let (mut app, _) = app_with_state(false).await;
        let (status, body) = post_json(
            &mut app,
            "/api/auth/google",
            json!({"credential": google_token("g-1", CLIENT_ID)}),
        )
        .await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
        assert_eq!(body["code"], "GOOGLE_AUTH_FAILED");
        assert_eq!(body["error"], "Google OAuth non configuré sur ce serveur");
    }

    #[tokio::test]
    async fn test_google_login_creates_then_logs_in() {
        let (mut app, _) = app_with_state(true).await;
        let credential = google_token("g-42", CLIENT_ID);

        let (status, first) = post_json(
            &mut app,
            "/api/auth/google",
            json!({"credential": credential}),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{first}");
        assert_eq!(first["success"], true);
        assert_eq!(first["isNewUser"], true);
        assert_eq!(first["user"]["username"], "ada_lovelace");
        assert_eq!(first["user"]["email"], "ada@example.com");
        assert_eq!(first["user"]["isAdmin"], false);
        assert_eq!(first["user"]["isGoogleUser"], true);
        let token = first["token"].as_str().unwrap();
        let (status, _) = get_auth(&mut app, "/api/stats/me", token).await;
        assert_eq!(status, StatusCode::OK);

        let (status, second) = post_json(
            &mut app,
            "/api/auth/google",
            json!({"credential": credential}),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(second["isNewUser"], false);
        assert_eq!(second["user"]["id"], first["user"]["id"]);
    }

    #[tokio::test]
    async fn test_bot_admin_requires_admin() {
        let (mut app, state) = app_with_state(false).await;
        let body = json!({"username": "RoboBot", "difficulty": "easy"});

        let (status, _) = post_json(&mut app, "/api/bots", body.clone()).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
        let (status, _) = delete_auth(&mut app, "/api/bots/whatever", None).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);

        let (_, token) = user_token(&mut app, &state, "plainuser", false).await;
        let (status, _) = post_json_auth(&mut app, "/api/bots", body, &token).await;
        assert_eq!(status, StatusCode::FORBIDDEN);
        let (status, _) = delete_auth(&mut app, "/api/bots/whatever", Some(&token)).await;
        assert_eq!(status, StatusCode::FORBIDDEN);
        assert!(state
            .user_repo
            .find_by_username("RoboBot")
            .await
            .unwrap()
            .is_none());
    }

    #[tokio::test]
    async fn test_bot_admin_create_and_delete() {
        let (mut app, state) = app_with_state(false).await;
        let (human_id, token) = user_token(&mut app, &state, "adminuser", true).await;

        let (status, body) = post_json_auth(
            &mut app,
            "/api/bots",
            json!({"username": "  RoboBot ", "difficulty": "HARD"}),
            &token,
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{body}");
        assert_eq!(body["success"], true);
        let bot = &body["bot"];
        assert_eq!(bot["username"], "RoboBot");
        assert_eq!(bot["userType"], "bot");
        assert_eq!(bot["botDifficulty"], "hard");
        assert_eq!(bot["isAdmin"], false);
        assert_eq!(bot["isGoogleUser"], false);
        assert!(bot["createdAt"].is_i64());
        let bot_id = bot["id"].as_str().unwrap().to_string();

        let (status, body) = get_auth(&mut app, "/api/bots?difficulty=hard", &token).await;
        assert_eq!(status, StatusCode::OK);
        assert!(body["bots"]
            .as_array()
            .unwrap()
            .iter()
            .any(|b| b["id"] == bot_id));

        // Duplicate username
        let (status, body) = post_json_auth(
            &mut app,
            "/api/bots",
            json!({"username": "RoboBot", "difficulty": "easy"}),
            &token,
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(
            body,
            json!({"success": false, "error": "Username \"RoboBot\" already exists"})
        );

        // Unknown difficulty (thibot is listable but not creatable, as in Node)
        for difficulty in [json!("insane"), json!("thibot"), Value::Null] {
            let (status, body) = post_json_auth(
                &mut app,
                "/api/bots",
                json!({"username": "OtherBot", "difficulty": difficulty}),
                &token,
            )
            .await;
            assert_eq!(status, StatusCode::BAD_REQUEST);
            assert_eq!(
                body["error"],
                "Difficulty must be one of: easy, medium, hard, hard_vince, ml, drl, llm"
            );
        }

        // Missing and invalid usernames
        let (status, body) =
            post_json_auth(&mut app, "/api/bots", json!({"difficulty": "easy"}), &token).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(body["error"], "Username is required");
        let (status, body) = post_json_auth(
            &mut app,
            "/api/bots",
            json!({"username": "no spaces", "difficulty": "easy"}),
            &token,
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(
            body["error"],
            "Username can only contain alphanumeric characters, hyphens, and underscores"
        );

        // A human cannot be deleted here
        let (status, body) =
            delete_auth(&mut app, &format!("/api/bots/{}", human_id), Some(&token)).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(
            body["error"],
            "User is not a bot - cannot delete human users via this endpoint"
        );
        assert!(state
            .user_repo
            .find_by_id(&human_id)
            .await
            .unwrap()
            .is_some());

        // Delete, then the same id is unknown
        let path = format!("/api/bots/{}", bot_id);
        let (status, body) = delete_auth(&mut app, &path, Some(&token)).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(body, json!({"success": true, "deletedBotId": bot_id}));
        assert!(state.user_repo.find_by_id(&bot_id).await.unwrap().is_none());

        let (status, body) = delete_auth(&mut app, &path, Some(&token)).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(body, json!({"success": false, "error": "Bot not found"}));
    }
}

// ============================================================================
// Party settings (Node's playerCount), name bounds, Node's JSON types
// ============================================================================

#[tokio::test]
async fn test_join_past_player_count_is_409_party_full() {
    let mut app = create_test_app().await;
    let (owner, _) = register(&mut app, "pc_owner").await;
    let (second, _) = register(&mut app, "pc_second").await;
    let (third, _) = register(&mut app, "pc_third").await;
    let (fourth, _) = register(&mut app, "pc_fourth").await;
    let party_id = create_party_with_seats(&mut app, &owner, "Three seats", 3).await;
    let join = format!("/api/party/{party_id}/join");
    for token in [&second, &third] {
        let (status, body) = post_json_auth(&mut app, &join, json!({}), token).await;
        assert_eq!(status, StatusCode::OK, "join: {body}");
    }

    let (status, body) = post_json_auth(&mut app, &join, json!({}), &fourth).await;
    assert_error(status, &body, StatusCode::CONFLICT, "PARTY_FULL");
    assert_eq!(seats(&mut app, &party_id, &owner).await, vec![0, 1, 2]);

    // The list shows the seats as Node: maxPlayers is settings.playerCount
    let (_, list) = get_auth(&mut app, "/api/party", &owner).await;
    let row = list["parties"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == party_id.as_str())
        .unwrap();
    assert_eq!(row["maxPlayers"], 3, "{row}");
    assert_eq!(row["playerCount"], 3, "{row}");

    // A full party starts
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/start"),
        json!({}),
        &owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "start: {body}");
}

#[tokio::test]
async fn test_add_bot_past_player_count_is_409_party_full() {
    let (mut app, state) = create_test_app_with_state().await;
    let (owner, _) = register(&mut app, "pcb_owner").await;
    let party_id = create_party_with_seats(&mut app, &owner, "Bot seats 3", 3).await;
    let path = format!("/api/party/{party_id}/bots");
    for i in 0..2 {
        let id = create_bot(&state, &format!("pcb_bot_{i}")).await;
        let (status, body) = post_json_auth(&mut app, &path, json!({"botId": id}), &owner).await;
        assert_eq!(status, StatusCode::CREATED, "{body}");
    }
    let extra = create_bot(&state, "pcb_extra").await;
    let (status, body) = post_json_auth(&mut app, &path, json!({"botId": extra}), &owner).await;
    assert_error(status, &body, StatusCode::CONFLICT, "PARTY_FULL");
}

#[tokio::test]
async fn test_create_party_player_count_validation() {
    let mut app = create_test_app().await;
    let (token, _) = register(&mut app, "pc_validator").await;

    // Outside 3-8, or missing from the settings: 400, and no party is created
    for settings in [
        json!({"playerCount": 2}),
        json!({"playerCount": 9}),
        json!({"allowSpectators": true}),
    ] {
        let (status, body) = post_json_auth(
            &mut app,
            "/api/party",
            json!({"name": "Bad seats", "settings": settings}),
            &token,
        )
        .await;
        assert_error(status, &body, StatusCode::BAD_REQUEST, "VALIDATION_ERROR");
    }

    // No settings at all: Node's PartySettings.createDefault()
    let (status, body) =
        post_json_auth(&mut app, "/api/party", json!({"name": "Defaults"}), &token).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(
        body["party"]["settings"],
        json!({"playerCount": 5, "allowSpectators": false, "roundTimeLimit": 0})
    );

    let (_, list) = get_auth(&mut app, "/api/party", &token).await;
    let names: Vec<&str> = list["parties"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["name"].as_str().unwrap())
        .collect();
    assert_eq!(names, vec!["Defaults"]);
}

#[tokio::test]
async fn test_create_party_name_bounds() {
    let mut app = create_test_app().await;
    let (token, _) = register(&mut app, "name_bounds").await;
    let create = |name: String| json!({"name": name, "settings": {"playerCount": 3}});

    // Shorter than 3 characters once trimmed, or longer than 50: 400 VALIDATION_ERROR
    for name in ["P".to_string(), "  ab  ".to_string(), "x".repeat(51)] {
        let (status, body) = post_json_auth(&mut app, "/api/party", create(name), &token).await;
        assert_error(status, &body, StatusCode::BAD_REQUEST, "VALIDATION_ERROR");
    }

    // 3 and 50 characters are accepted; the name is stored trimmed
    let (status, body) = post_json_auth(
        &mut app,
        "/api/party",
        create("  abc  ".to_string()),
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(body["party"]["name"], "abc");
    let (status, body) =
        post_json_auth(&mut app, "/api/party", create("é".repeat(50)), &token).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
}

#[tokio::test]
async fn test_create_party_with_more_bots_than_seats_is_400() {
    let (mut app, state) = create_test_app_with_state().await;
    let (token, _) = register(&mut app, "bots_seats").await;
    let mut bots = Vec::new();
    for i in 0..8 {
        bots.push(create_bot(&state, &format!("bs_bot_{i}")).await);
    }

    // The owner and 8 bots do not fit in 8 seats, nor the owner and 3 bots in 3
    for (seats, count) in [(8, 8), (3, 3)] {
        let (status, body) = post_json_auth(
            &mut app,
            "/api/party",
            json!({"name": "Crowded", "settings": {"playerCount": seats}, "botIds": &bots[..count]}),
            &token,
        )
        .await;
        assert_error(status, &body, StatusCode::BAD_REQUEST, "VALIDATION_ERROR");
    }
    let (_, list) = get_auth(&mut app, "/api/party", &token).await;
    assert_eq!(list["parties"], json!([]), "no party is left behind");

    // 7 bots fill an 8-seat party
    let (status, body) = post_json_auth(
        &mut app,
        "/api/party",
        json!({"name": "Full house", "settings": {"playerCount": 8}, "botIds": &bots[..7]}),
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(body["botsJoined"], 7);
}

#[tokio::test]
async fn test_party_timestamps_and_player_ids_are_numbers() {
    let mut app = create_test_app().await;
    let (owner, _) = register(&mut app, "types_owner").await;
    let (other, _) = register(&mut app, "types_other").await;
    let (status, created) = post_json_auth(
        &mut app,
        "/api/party",
        json!({"name": "Typed party", "settings": {"playerCount": 4}}),
        &owner,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{created}");
    assert!(created["party"]["createdAt"].is_i64(), "{created}");
    let party_id = created["party"]["id"].as_str().unwrap().to_string();

    // Details, for a member and for a non-member of a public party
    for token in [&owner, &other] {
        let (status, details) = get_auth(&mut app, &format!("/api/party/{party_id}"), token).await;
        assert_eq!(status, StatusCode::OK, "{details}");
        let party = &details["party"];
        assert!(party["createdAt"].is_i64(), "{details}");
        assert!(party["updatedAt"].is_i64(), "{details}");
        assert_eq!(
            party["settings"],
            json!({"playerCount": 4, "allowSpectators": false, "roundTimeLimit": 0})
        );
        let player = &details["players"][0];
        assert!(player["id"].is_i64(), "{details}");
        assert!(player["joinedAt"].is_i64(), "{details}");
    }

    // The list: Unix seconds, and Node's keys (no visibility: only public parties are listed)
    for list in [
        get_auth(&mut app, "/api/party", &owner).await.1,
        request_no_auth(&mut app, "GET", "/api/party").await.1,
    ] {
        let row = &list["parties"][0];
        assert!(row["createdAt"].is_i64(), "{list}");
        assert!(row.get("visibility").is_none(), "{list}");
    }
}

#[tokio::test]
async fn test_party_with_node_written_settings() {
    let (mut app, state) = create_test_app_with_state().await;
    let (owner, owner_id) = register(&mut app, "node_owner").await;
    let (second, _) = register(&mut app, "node_second").await;
    let (third, _) = register(&mut app, "node_third").await;
    let (late, _) = register(&mut app, "node_late").await;

    // A party row as Node's PartyRepository writes it (PartySettings.toJSON())
    let now = chrono::Utc::now().timestamp();
    sqlx::query(
        "INSERT INTO parties (id, name, owner_id, invite_code, visibility, status,
                              settings_json, current_round_id, created_at, updated_at)
         VALUES ('node-party', 'Node table', ?, 'NODE1234', 'public', 'waiting',
                 '{\"playerCount\":3,\"allowSpectators\":false,\"roundTimeLimit\":0}',
                 NULL, ?, ?)",
    )
    .bind(&owner_id)
    .bind(now)
    .bind(now)
    .execute(&state.db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO party_players (party_id, user_id, player_index, joined_at)
         VALUES ('node-party', ?, 0, ?)",
    )
    .bind(&owner_id)
    .bind(now)
    .execute(&state.db)
    .await
    .unwrap();

    let (status, details) = get_auth(&mut app, "/api/party/node-party", &owner).await;
    assert_eq!(status, StatusCode::OK, "{details}");
    assert_eq!(
        details["party"]["settings"],
        json!({"playerCount": 3, "allowSpectators": false, "roundTimeLimit": 0})
    );
    assert_eq!(details["party"]["createdAt"], now);

    // Its playerCount holds: two more join, a fourth player is refused
    let join = "/api/party/node-party/join";
    for token in [&second, &third] {
        let (status, body) = post_json_auth(&mut app, join, json!({}), token).await;
        assert_eq!(status, StatusCode::OK, "{body}");
    }
    let (status, body) = post_json_auth(&mut app, join, json!({}), &late).await;
    assert_error(status, &body, StatusCode::CONFLICT, "PARTY_FULL");
}

#[tokio::test]
async fn test_create_party_refuses_duplicate_bot_ids() {
    let (mut app, state) = create_test_app_with_state().await;
    let (token, _) = register(&mut app, "dup_bots").await;
    let bot = create_bot(&state, "dup_bot").await;
    let (status, body) = post_json_auth(
        &mut app,
        "/api/party",
        json!({"name": "Twice", "settings": {"playerCount": 4}, "botIds": [&bot, &bot]}),
        &token,
    )
    .await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "VALIDATION_ERROR");
    assert_eq!(body["error"], "Duplicate bot IDs detected");
    let (_, list) = get_auth(&mut app, "/api/party", &token).await;
    assert_eq!(list["parties"], json!([]), "no party is left behind");
}

#[tokio::test]
async fn test_create_party_name_length_counts_utf16_units() {
    let mut app = create_test_app().await;
    let (token, _) = register(&mut app, "utf16_names").await;
    let create = |name: String| json!({"name": name, "settings": {"playerCount": 3}});

    // "🎲🎲" is 2 characters but 4 UTF-16 units, JavaScript's length: accepted, as on Node
    let (status, body) =
        post_json_auth(&mut app, "/api/party", create("🎲🎲".to_string()), &token).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");

    // 25 dice are 50 units, 26 are 52
    let (status, body) =
        post_json_auth(&mut app, "/api/party", create("🎲".repeat(25)), &token).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let (status, body) =
        post_json_auth(&mut app, "/api/party", create("🎲".repeat(26)), &token).await;
    assert_error(status, &body, StatusCode::BAD_REQUEST, "VALIDATION_ERROR");
    assert_eq!(body["error"], "Party name must not exceed 50 characters");
}

#[tokio::test]
async fn test_create_party_player_count_out_of_range_message() {
    let mut app = create_test_app().await;
    let (token, _) = register(&mut app, "pc_message").await;
    for count in [json!(300), json!(-1), json!(3.5), json!(2)] {
        let (status, body) = post_json_auth(
            &mut app,
            "/api/party",
            json!({"name": "Odd seats", "settings": {"playerCount": count}}),
            &token,
        )
        .await;
        assert_error(status, &body, StatusCode::BAD_REQUEST, "VALIDATION_ERROR");
        assert_eq!(
            body["error"], "Player count must be between 3 and 8",
            "{count}"
        );
    }
    // A whole float is a whole number, as in JavaScript
    let (status, body) = post_json_auth(
        &mut app,
        "/api/party",
        json!({"name": "Float seats", "settings": {"playerCount": 4.0}}),
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(body["party"]["settings"]["playerCount"], 4);
}

/// Replay a lost race on a seat: `intruder_id` takes the lowest free seat of `party_id`
/// at once, but the seat reads miss it until an insert has collided with it, as when a
/// concurrent join commits between a player's read of the seats and its insert.
/// `party_players` becomes a view over the real table; its insert trigger records the
/// collision (`INSERT OR FAIL` keeps that record when the seat insert fails) and the
/// view shows the intruder from then on.
async fn steal_next_seat(state: &AppState, party_id: &str, intruder_id: &str) {
    sqlx::raw_sql(&format!(
        "INSERT INTO party_players (party_id, user_id, player_index, joined_at)
           SELECT '{party_id}', '{intruder_id}', MIN(free.i), 0
           FROM (SELECT 0 AS i UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
                 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7) AS free
           WHERE free.i NOT IN (SELECT player_index FROM party_players
                                WHERE party_id = '{party_id}');
         CREATE TABLE seat_race_lost (lost INTEGER);
         ALTER TABLE party_players RENAME TO party_players_real;
         CREATE VIEW party_players AS
           SELECT * FROM party_players_real
           WHERE user_id != '{intruder_id}' OR EXISTS (SELECT 1 FROM seat_race_lost);
         CREATE TRIGGER party_players_insert INSTEAD OF INSERT ON party_players
         BEGIN
           INSERT INTO seat_race_lost
             SELECT 1 WHERE EXISTS (SELECT 1 FROM party_players_real
                                    WHERE party_id = NEW.party_id
                                      AND player_index = NEW.player_index);
           INSERT OR FAIL INTO party_players_real (party_id, user_id, player_index, joined_at)
             VALUES (NEW.party_id, NEW.user_id, NEW.player_index, NEW.joined_at);
         END;"
    ))
    .execute(&state.db)
    .await
    .unwrap();
}

#[tokio::test]
async fn test_join_that_loses_its_seat_takes_the_next_one() {
    let (mut app, state) = create_test_app_with_state().await;
    let (owner, _) = register(&mut app, "race_owner").await;
    let (joiner, _) = register(&mut app, "race_joiner").await;
    let (_, intruder_id) = register(&mut app, "race_intruder").await;
    let party_id = create_party_with_seats(&mut app, &owner, "Race", 4).await;
    steal_next_seat(&state, &party_id, &intruder_id).await;

    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/join"),
        json!({}),
        &joiner,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(
        body["playerIndex"], 2,
        "seat 1 went to the intruder: {body}"
    );
    assert_eq!(seats(&mut app, &party_id, &owner).await, vec![0, 1, 2]);
}

#[tokio::test]
async fn test_join_that_loses_the_last_seat_is_party_full() {
    let (mut app, state) = create_test_app_with_state().await;
    let (owner, _) = register(&mut app, "race_full_owner").await;
    let (second, _) = register(&mut app, "race_full_second").await;
    let (joiner, _) = register(&mut app, "race_full_joiner").await;
    let (_, intruder_id) = register(&mut app, "race_full_intruder").await;
    let party_id = create_party_with_seats(&mut app, &owner, "Race full", 3).await;
    let join = format!("/api/party/{party_id}/join");
    let (status, body) = post_json_auth(&mut app, &join, json!({}), &second).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    steal_next_seat(&state, &party_id, &intruder_id).await;

    let (status, body) = post_json_auth(&mut app, &join, json!({}), &joiner).await;
    assert_error(status, &body, StatusCode::CONFLICT, "PARTY_FULL");
}

#[tokio::test]
async fn test_add_bot_that_loses_its_seat_takes_the_next_one() {
    let (mut app, state) = create_test_app_with_state().await;
    let (owner, _) = register(&mut app, "race_bot_owner").await;
    let (_, intruder_id) = register(&mut app, "race_bot_intruder").await;
    let bot = create_bot(&state, "race_bot").await;
    let party_id = create_party_with_seats(&mut app, &owner, "Race bot", 4).await;
    steal_next_seat(&state, &party_id, &intruder_id).await;

    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/bots"),
        json!({"botId": bot}),
        &owner,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(body["playerIndex"], 2, "{body}");
}

#[tokio::test]
async fn test_party_with_loosely_typed_node_settings_keeps_its_seats() {
    let (mut app, state) = create_test_app_with_state().await;
    let (owner, owner_id) = register(&mut app, "loose_owner").await;
    sqlx::query(
        "INSERT INTO parties (id, name, owner_id, invite_code, visibility, status,
                              settings_json, current_round_id, created_at, updated_at)
         VALUES ('loose-party', 'Loose', ?, 'LOOSE123', 'public', 'waiting',
                 '{\"playerCount\":6,\"allowSpectators\":1}', NULL, 1700000000, 1700000000)",
    )
    .bind(&owner_id)
    .execute(&state.db)
    .await
    .unwrap();
    let (status, details) = get_auth(&mut app, "/api/party/loose-party", &owner).await;
    assert_eq!(status, StatusCode::OK, "{details}");
    assert_eq!(
        details["party"]["settings"],
        json!({"playerCount": 6, "allowSpectators": true, "roundTimeLimit": 0})
    );
}

// ============================================================================
// Auth refusals, unknown routes and health answer Node's bodies
// ============================================================================

/// A GET with a raw Authorization header value (None: no header at all).
async fn get_with_auth_header(
    app: &mut Router,
    path: &str,
    header: Option<&str>,
) -> (StatusCode, Value) {
    let mut builder = Request::builder().method("GET").uri(path);
    if let Some(value) = header {
        builder = builder.header("Authorization", value);
    }
    let response = ServiceExt::<Request<Body>>::ready(app)
        .await
        .unwrap()
        .call(builder.body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let body_bytes = response.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        serde_json::from_slice(&body_bytes).unwrap_or(Value::Null),
    )
}

#[tokio::test]
async fn test_auth_missing_header_answers_missing_auth_header() {
    let mut app = create_test_app().await;
    for path in ["/api/stats/me", "/api/history", "/api/admin/users"] {
        for header in [None, Some("")] {
            let (status, body) = get_with_auth_header(&mut app, path, header).await;
            assert_eq!(
                status,
                StatusCode::UNAUTHORIZED,
                "{path} {header:?}: {body}"
            );
            assert_eq!(
                body,
                json!({"error": "Missing authorization header", "code": "MISSING_AUTH_HEADER"}),
                "{path} {header:?}"
            );
        }
    }
    let (status, body) = request_no_auth(&mut app, "POST", "/api/party").await;
    assert_error(
        status,
        &body,
        StatusCode::UNAUTHORIZED,
        "MISSING_AUTH_HEADER",
    );
}

#[tokio::test]
async fn test_auth_malformed_header_answers_invalid_auth_format() {
    let mut app = create_test_app().await;
    let (token, _) = register(&mut app, "formatuser").await;
    let bad = [
        token.clone(),
        format!("Basic {token}"),
        format!("bearer {token}"),
        "Bearer".to_string(),
        format!("Bearer  {token}"),
        format!("Bearer {token} extra"),
    ];
    for header in bad {
        let (status, body) = get_with_auth_header(&mut app, "/api/stats/me", Some(&header)).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{header}: {body}");
        assert_eq!(
            body,
            json!({
                "error": "Invalid authorization header format",
                "code": "INVALID_AUTH_FORMAT",
                "details": {"expected": "Bearer <token>"}
            }),
            "{header}"
        );
    }
    // The well-formed header with the same token gets in
    let (status, body) =
        get_with_auth_header(&mut app, "/api/stats/me", Some(&format!("Bearer {token}"))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
}

#[tokio::test]
async fn test_auth_bad_token_answers_invalid_token() {
    let mut app = create_test_app().await;
    let (status, body) =
        get_with_auth_header(&mut app, "/api/stats/me", Some("Bearer not-a-jwt")).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "{body}");
    assert_eq!(
        body,
        json!({"error": "Invalid or expired token", "code": "INVALID_TOKEN"})
    );
}

#[tokio::test]
async fn test_auth_token_of_deleted_user_answers_invalid_token() {
    let (mut app, state) = create_test_app_with_state().await;
    let (token, user_id) = register(&mut app, "vanisheduser").await;
    sqlx::query("DELETE FROM users WHERE id = ?")
        .bind(&user_id)
        .execute(&state.db)
        .await
        .unwrap();

    let (status, body) = get_auth(&mut app, "/api/stats/me", &token).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "{body}");
    assert_eq!(
        body,
        json!({"error": "Invalid or expired token", "code": "INVALID_TOKEN"})
    );
    // Behind the admin routes too: the token check comes before the admin check
    let (status, body) = get_auth(&mut app, "/api/admin/users", &token).await;
    assert_error(status, &body, StatusCode::UNAUTHORIZED, "INVALID_TOKEN");
}

#[tokio::test]
async fn test_unknown_api_route_answers_route_not_found() {
    let mut app = create_test_app().await;
    for (method, path, want_path) in [
        ("GET", "/api/nope", "/api/nope"),
        ("POST", "/api/party/abc/nothing", "/api/party/abc/nothing"),
        ("GET", "/api/nope?x=1", "/api/nope"),
    ] {
        let (status, body) = request_no_auth(&mut app, method, path).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{method} {path}: {body}");
        assert_eq!(
            body,
            json!({
                "error": "Not Found",
                "code": "ROUTE_NOT_FOUND",
                "path": want_path,
                "message": "The requested endpoint does not exist"
            }),
            "{method} {path}"
        );
    }
}

/// A timestamp as JavaScript's `toISOString()` writes it: UTC, milliseconds, `Z`.
fn assert_iso_timestamp(value: &Value) {
    let text = value.as_str().expect("timestamp is a string");
    assert!(
        chrono::DateTime::parse_from_rfc3339(text).is_ok() && text.ends_with('Z'),
        "{text}"
    );
    assert_eq!(text.len(), "2026-09-24T12:00:00.000Z".len(), "{text}");
}

#[tokio::test]
async fn test_api_health_answers_status_timestamp_uptime() {
    let mut app = create_test_app().await;
    let (status, body) = request_no_auth(&mut app, "GET", "/api/health").await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body.as_object().unwrap().len(), 3, "{body}");
    assert_eq!(body["status"], "ok");
    assert_iso_timestamp(&body["timestamp"]);
    assert!(body["uptime"].as_f64().unwrap() >= 0.0, "{body}");
}

#[tokio::test]
async fn test_root_health_and_unknown_root_path_answer_nodes_bodies() {
    // create_test_app is api::build_app, the router main.rs serves
    let mut app = create_test_app().await;

    let (status, body) = request_no_auth(&mut app, "GET", "/health").await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body.as_object().unwrap().len(), 3, "{body}");
    assert_eq!(body["status"], "ok");
    assert_eq!(body["api"], "v2 (Clean Architecture)");
    assert_iso_timestamp(&body["timestamp"]);

    let (status, body) = request_no_auth(&mut app, "GET", "/nowhere").await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "ROUTE_NOT_FOUND");
    assert_eq!(body["path"], "/nowhere");
}

/// Node routes by method and path together, so a served path asked with another method
/// falls through to its 404 like an unknown path; axum's bare 405 must not show.
#[tokio::test]
async fn test_unserved_method_answers_route_not_found() {
    let mut app = create_test_app().await;
    let (token, _) = register(&mut app, "methoduser").await;
    for (method, path) in [
        ("PUT", "/api/party"),
        // Only POST is behind auth_middleware there: no 401 for a GET, as on Node
        ("GET", "/api/party/some-party/join"),
        ("PATCH", "/api/game/some-party/play"),
        ("PUT", "/api/bots"),
        ("POST", "/api/stats/leaderboard"),
        ("DELETE", "/api/health"),
        ("POST", "/health"),
        ("POST", "/suscribeupdate"),
    ] {
        let (status, body) = request_no_auth(&mut app, method, path).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{method} {path}: {body}");
        assert_eq!(body["code"], "ROUTE_NOT_FOUND", "{method} {path}");
        assert_eq!(body["path"], path, "{method} {path}");
    }
    // With a token too
    let (status, body) = send_raw(&mut app, "PUT", "/api/party", "", None, Some(&token)).await;
    assert_error(status, &body, StatusCode::NOT_FOUND, "ROUTE_NOT_FOUND");
}

/// Node checks the token and the admin flag on every `/api/admin` path before routing
/// (`router.use` in `adminRoutes.js`): only an admin learns that a path does not exist.
#[tokio::test]
async fn test_unknown_admin_path_is_behind_auth_and_admin() {
    let (mut app, state) = create_test_app_with_state().await;
    let (user, _) = register(&mut app, "plainadminprobe").await;
    let (admin, admin_id) = register(&mut app, "realadminprobe").await;
    sqlx::query("UPDATE users SET is_admin = 1 WHERE id = ?")
        .bind(&admin_id)
        .execute(&state.db)
        .await
        .unwrap();

    for (method, path) in [
        ("GET", "/api/admin/nope"),
        ("GET", "/api/admin/users/someone/nothing"),
        // A served path with an unserved method
        ("PUT", "/api/admin/users"),
    ] {
        let (status, body) = request_no_auth(&mut app, method, path).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{method} {path}: {body}");
        assert_eq!(body["code"], "MISSING_AUTH_HEADER", "{method} {path}");

        let (status, body) = send_raw(&mut app, method, path, "", None, Some(&user)).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{method} {path}: {body}");
        assert_eq!(body["code"], "ADMIN_REQUIRED", "{method} {path}");

        let (status, body) = send_raw(&mut app, method, path, "", None, Some(&admin)).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{method} {path}: {body}");
        assert_eq!(body["code"], "ROUTE_NOT_FOUND", "{method} {path}");
        assert_eq!(body["path"], path, "{method} {path}");
    }
}

// ============================================================================
// GET /state and POST /nextRound answer Node's shapes
// ============================================================================

/// The keys of a JSON object, sorted
fn keys_of(v: &Value) -> Vec<String> {
    let mut keys: Vec<String> = v
        .as_object()
        .unwrap_or_else(|| panic!("not an object: {v}"))
        .keys()
        .cloned()
        .collect();
    keys.sort();
    keys
}

async fn game_state(app: &mut Router, party_id: &str, token: &str) -> Value {
    let (status, body) = get_auth(app, &format!("/api/game/{party_id}/state"), token).await;
    assert_eq!(status, StatusCode::OK, "state: {body}");
    body
}

#[tokio::test]
async fn test_state_sends_nodes_always_present_keys() {
    let (mut app, _state) = create_test_app_with_state().await;
    let (party_id, tokens) = started_party(&mut app, "sk").await;

    let body = game_state(&mut app, &party_id, &tokens[0]).await;
    assert!(body["party"]["currentRoundId"].is_string(), "{body}");
    assert_eq!(body["gameState"]["wasCounterActed"], false, "{body}");
    assert_eq!(body["gameState"]["gameFinished"], false, "{body}");
    // Node's players are {playerIndex, userId, username}
    for p in body["players"].as_array().unwrap() {
        assert_eq!(keys_of(p), ["playerIndex", "userId", "username"], "{p}");
    }
    // No move yet this round
    assert!(body["gameState"]["lastAction"].is_null(), "{body}");
}

#[tokio::test]
async fn test_state_last_action_of_select_play_and_draw() {
    let (mut app, state) = create_test_app_with_state().await;
    let (party_id, tokens) = started_party(&mut app, "la").await;
    let url = |a: &str| format!("/api/game/{party_id}/{a}");

    // selectHandSize: {type, playerIndex, handSize}, no timestamp (as Node)
    let starter = game_state(&mut app, &party_id, &tokens[0]).await["gameState"]["currentTurn"]
        .as_u64()
        .unwrap() as usize;
    let (status, body) = post_json_auth(
        &mut app,
        &url("selectHandSize"),
        json!({"handSize": 5}),
        &tokens[starter],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let la = &game_state(&mut app, &party_id, &tokens[0]).await["gameState"]["lastAction"];
    assert_eq!(
        *la,
        json!({"type": "selectHandSize", "playerIndex": starter, "handSize": 5})
    );

    // play: {type, playerIndex, cardIds, timestamp}
    let hands: [&[u8]; 3] = [
        &[0, 1, 2, 3, 4],
        &[13, 14, 15, 16, 17],
        &[26, 27, 28, 29, 30],
    ];
    set_game_state(&state, &party_id, &hands, &[0, 0, 0], 0, GameAction::Play).await;
    set_piles(&state, &party_id, &[40], false).await;
    let (status, body) =
        post_json_auth(&mut app, &url("play"), json!({"cardIds": [4]}), &tokens[0]).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let la = game_state(&mut app, &party_id, &tokens[1]).await["gameState"]["lastAction"].clone();
    assert_eq!(
        keys_of(&la),
        ["cardIds", "playerIndex", "timestamp", "type"],
        "{la}"
    );
    assert_eq!(la["type"], "play");
    assert_eq!(la["playerIndex"], 0);
    assert_eq!(la["cardIds"], json!([4]));
    assert!(
        la["timestamp"].as_u64().unwrap() > 1_600_000_000_000,
        "{la}"
    );

    // draw from the deck: {type, playerIndex, source, deckReshuffled, timestamp} — the
    // card drawn stays secret (Node's cardId leak is not copied)
    let (status, body) = post_json_auth(
        &mut app,
        &url("draw"),
        json!({"source": "deck"}),
        &tokens[0],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let la = game_state(&mut app, &party_id, &tokens[1]).await["gameState"]["lastAction"].clone();
    assert_eq!(
        keys_of(&la),
        [
            "deckReshuffled",
            "playerIndex",
            "source",
            "timestamp",
            "type"
        ],
        "{la}"
    );
    assert_eq!(la["type"], "draw");
    assert_eq!(la["playerIndex"], 0);
    assert_eq!(la["source"], "deck");
    assert_eq!(la["deckReshuffled"], false);
    assert!(
        la.get("cardId").is_none(),
        "a deck draw names no card: {la}"
    );

    // draw from the played pile: the card taken is on the table for all, and named
    let (status, body) =
        post_json_auth(&mut app, &url("play"), json!({"cardIds": [17]}), &tokens[1]).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (status, body) = post_json_auth(
        &mut app,
        &url("draw"),
        json!({"source": "played", "cardId": 4}),
        &tokens[1],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let la = game_state(&mut app, &party_id, &tokens[2]).await["gameState"]["lastAction"].clone();
    assert_eq!(la["type"], "draw");
    assert_eq!(la["playerIndex"], 1);
    assert_eq!(la["source"], "played");
    assert_eq!(la["cardId"], 4);
    assert_eq!(la["deckReshuffled"], false);
}

#[tokio::test]
async fn test_state_last_action_of_a_reshuffling_draw() {
    let (mut app, state) = create_test_app_with_state().await;
    let (party_id, tokens) = started_party(&mut app, "rs").await;
    let hands: [&[u8]; 3] = [&[0, 1, 2], &[13, 14, 15], &[26, 27, 28]];
    set_game_state(&state, &party_id, &hands, &[0, 0, 0], 0, GameAction::Draw).await;
    let mut gs = state
        .party_repo
        .get_game_state(&party_id)
        .await
        .unwrap()
        .unwrap();
    gs.deck.clear();
    gs.discard_pile = vec![40, 41, 42];
    state
        .party_repo
        .save_game_state(&party_id, &gs)
        .await
        .unwrap();

    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/game/{party_id}/draw"),
        json!({"source": "deck"}),
        &tokens[0],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let la = game_state(&mut app, &party_id, &tokens[0]).await["gameState"]["lastAction"].clone();
    assert_eq!(la["source"], "deck");
    assert_eq!(la["deckReshuffled"], true, "{la}");
}

#[tokio::test]
async fn test_state_last_action_of_a_zapzap() {
    let (mut app, state) = create_test_app_with_state().await;
    let (party_id, tokens) = started_party(&mut app, "lz").await;

    // Player 1 calls with 3 points, player 0 ties: counteracted by seat 0, which Node's
    // `counterActedByPlayerIndex || null` turns into null; Rust answers 0
    let hands: [&[u8]; 3] = [&[0, 1], &[13, 14], &[26, 27, 28]];
    set_game_state(
        &state,
        &party_id,
        &hands,
        &[10, 20, 30],
        1,
        GameAction::Play,
    )
    .await;
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/game/{party_id}/zapzap"),
        json!({}),
        &tokens[1],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    let body = game_state(&mut app, &party_id, &tokens[0]).await;
    let gs = &body["gameState"];
    let la = &gs["lastAction"];
    assert_eq!(
        keys_of(la),
        [
            "callerHandPoints",
            "counterActedByPlayerIndex",
            "playerIndex",
            "roundScores",
            "timestamp",
            "type",
            "wasCounterActed"
        ],
        "{la}"
    );
    assert_eq!(la["type"], "zapzap");
    assert_eq!(la["playerIndex"], 1);
    assert_eq!(la["wasCounterActed"], true);
    assert_eq!(la["counterActedByPlayerIndex"], 0);
    assert_eq!(la["callerHandPoints"], 3);
    assert_eq!(la["roundScores"], json!({"0": 0, "1": 13, "2": 6}));
    assert_eq!(gs["wasCounterActed"], true);
    assert_eq!(gs["counterActedByPlayerIndex"], 0);
    assert_eq!(gs["roundScores"], la["roundScores"]);
    assert_eq!(gs["gameFinished"], false);
}

#[tokio::test]
async fn test_next_round_answers_nodes_keys() {
    let (mut app, state) = create_test_app_with_state().await;
    let (party_id, tokens) = started_party(&mut app, "nr").await;
    let players = state.party_repo.get_party_players(&party_id).await.unwrap();
    let user_of = |i: u8| {
        players
            .iter()
            .find(|p| p.player_index == i)
            .unwrap()
            .user_id
            .clone()
    };

    // A finished round, player 1 out past 100
    let hands: [&[u8]; 3] = [&[0], &[13], &[26]];
    set_game_state(
        &state,
        &party_id,
        &hands,
        &[10, 120, 30],
        0,
        GameAction::Finished,
    )
    .await;
    let mut gs = state
        .party_repo
        .get_game_state(&party_id)
        .await
        .unwrap()
        .unwrap();
    gs.eliminate_player(1);
    state
        .party_repo
        .save_game_state(&party_id, &gs)
        .await
        .unwrap();

    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/game/{party_id}/nextRound"),
        json!({}),
        &tokens[0],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(
        keys_of(&body),
        [
            "eliminatedPlayers",
            "gameFinished",
            "round",
            "scores",
            "startingPlayer",
            "success"
        ],
        "{body}"
    );
    assert_eq!(body["gameFinished"], false);
    assert_eq!(keys_of(&body["round"]), ["id", "roundNumber", "status"]);
    assert_eq!(body["round"]["status"], "active");
    assert_eq!(body["scores"], json!({"0": 10, "1": 120, "2": 30}));
    assert_eq!(
        body["eliminatedPlayers"],
        json!([{"userId": user_of(1), "playerIndex": 1, "score": 120}])
    );
}

#[tokio::test]
async fn test_next_round_at_the_end_of_the_game_answers_nodes_keys() {
    let (mut app, state) = create_test_app_with_state().await;
    let (party_id, tokens) = started_party(&mut app, "ng").await;
    let players = state.party_repo.get_party_players(&party_id).await.unwrap();
    let user_of = |i: u8| {
        players
            .iter()
            .find(|p| p.player_index == i)
            .unwrap()
            .user_id
            .clone()
    };

    // Players 1 and 2 out: player 0 wins
    let hands: [&[u8]; 3] = [&[0], &[13], &[26]];
    set_game_state(
        &state,
        &party_id,
        &hands,
        &[10, 120, 130],
        0,
        GameAction::Finished,
    )
    .await;
    let mut gs = state
        .party_repo
        .get_game_state(&party_id)
        .await
        .unwrap()
        .unwrap();
    gs.eliminate_player(1);
    gs.eliminate_player(2);
    state
        .party_repo
        .save_game_state(&party_id, &gs)
        .await
        .unwrap();

    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/game/{party_id}/nextRound"),
        json!({}),
        &tokens[0],
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(
        keys_of(&body),
        [
            "eliminatedPlayers",
            "finalScores",
            "gameFinished",
            "success",
            "winner"
        ],
        "{body}"
    );
    assert_eq!(body["gameFinished"], true);
    assert_eq!(
        body["winner"],
        json!({"userId": user_of(0), "playerIndex": 0, "score": 10})
    );
    assert_eq!(body["finalScores"], json!({"0": 10, "1": 120, "2": 130}));
    assert_eq!(
        body["eliminatedPlayers"],
        json!([
            {"userId": user_of(1), "playerIndex": 1, "score": 120},
            {"userId": user_of(2), "playerIndex": 2, "score": 130}
        ])
    );

    // The branch finished the party: a second call is refused, the results saved once
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/game/{party_id}/nextRound"),
        json!({}),
        &tokens[0],
    )
    .await;
    assert_error(
        status,
        &body,
        StatusCode::BAD_REQUEST,
        "INVALID_PARTY_STATE",
    );
    assert_eq!(game_results_rows(&state, &party_id).await, 1);
}

async fn game_results_rows(state: &AppState, party_id: &str) -> i64 {
    let (rows,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM game_results WHERE party_id = ?")
        .bind(party_id)
        .fetch_one(&state.db)
        .await
        .unwrap();
    rows
}

#[tokio::test]
async fn test_next_round_after_the_game_ending_zapzap_is_refused() {
    let (mut app, state) = create_test_app_with_state().await;
    let (party_id, tokens) = started_party(&mut app, "ge").await;

    // Player 0 calls with 3 points; players 1 and 2 go past 100: the zapzap ends the game
    let hands: [&[u8]; 3] = [&[0, 1], &[13, 14, 15, 16, 17], &[26, 27, 28, 29, 30]];
    set_game_state(
        &state,
        &party_id,
        &hands,
        &[10, 95, 95],
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
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["gameFinished"], true);
    assert_eq!(game_results_rows(&state, &party_id).await, 1);

    // The party is over: nextRound's game-over branch is not reached
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/game/{party_id}/nextRound"),
        json!({}),
        &tokens[0],
    )
    .await;
    assert_error(
        status,
        &body,
        StatusCode::BAD_REQUEST,
        "INVALID_PARTY_STATE",
    );
    assert_eq!(game_results_rows(&state, &party_id).await, 1);
}

// ============================================================================
// The last parity items: Node's answers to a bad set-admin body, a join of a full
// started party and a delete by a non-member (tests/parity/divergences.json)
// ============================================================================

#[tokio::test]
async fn test_admin_set_admin_bad_body_answers_nodes_400() {
    let (mut app, state) = create_test_app_with_state().await;
    let (admin, _) = register_admin(&mut app, &state, "badbodyadmin").await;
    let (_, user_id) = register(&mut app, "badbodytarget").await;
    let path = format!("/api/admin/users/{user_id}/admin");
    let want = json!({ "success": false, "error": "isAdmin must be a boolean" });

    // A mistyped field, a missing one, and malformed JSON: Node's 400, not axum's 422
    for body in [r#"{"isAdmin":"yes"}"#, "{}", "{not json"] {
        let (status, got) = send_raw(
            &mut app,
            "POST",
            &path,
            body,
            Some("application/json"),
            Some(&admin),
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{body}: {got}");
        assert_eq!(got, want, "{body}");
    }
}

#[tokio::test]
async fn test_join_full_started_party_answers_party_full() {
    let mut app = create_test_app().await;
    let (owner, _) = register(&mut app, "fullstart_a").await;
    let party_id = create_party_with_seats(&mut app, &owner, "Full started", 3).await;
    for name in ["fullstart_b", "fullstart_c"] {
        let (token, _) = register(&mut app, name).await;
        let (status, body) = post_json_auth(
            &mut app,
            &format!("/api/party/{party_id}/join"),
            json!({}),
            &token,
        )
        .await;
        assert_eq!(status, StatusCode::OK, "join: {body}");
    }
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/start"),
        json!({}),
        &owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "start: {body}");

    // Node checks a full party before anything else (JoinParty.js)
    let (late, _) = register(&mut app, "fullstart_d").await;
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
async fn test_delete_party_by_a_non_member_answers_not_in_party() {
    let mut app = create_test_app().await;
    let (owner, _) = register(&mut app, "nonmember_owner").await;
    let (outsider, _) = register(&mut app, "nonmember_out").await;
    let waiting_id = create_party(&mut app, &owner, "Not yours").await;
    let (playing_id, tokens) = started_party(&mut app, "nonmember_game").await;

    // Node's order (DeleteParty.js): membership first, whatever the party's state
    for party_id in [&waiting_id, &playing_id] {
        let path = format!("/api/party/{party_id}");
        let (status, body) = send_raw(&mut app, "DELETE", &path, "", None, Some(&outsider)).await;
        assert_error(status, &body, StatusCode::FORBIDDEN, "NOT_IN_PARTY");
    }

    // Then the owner (or the only human): a member who is neither, even during a game
    let path = format!("/api/party/{playing_id}");
    let (status, body) = send_raw(&mut app, "DELETE", &path, "", None, Some(&tokens[1])).await;
    assert_error(status, &body, StatusCode::FORBIDDEN, "NOT_AUTHORIZED");
}

/// The user ids `GET /api/players/connected` lists
async fn connected_ids(app: &mut Router, token: &str) -> Vec<String> {
    let (status, body) = get_auth(app, "/api/players/connected", token).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["players"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["userId"].as_str().unwrap().to_string())
        .collect()
}

/// The `userConnected` / `userDisconnected` events of `user_id` broadcast so far
fn presence_events(
    events: &mut async_broadcast::Receiver<zapzap_backend::infrastructure::app_state::GameEvent>,
    user_id: &str,
) -> Vec<String> {
    let mut seen = Vec::new();
    while let Ok(event) = events.try_recv() {
        let presence =
            event.event_type == "userConnected" || event.event_type == "userDisconnected";
        if presence && event.user_id.as_deref() == Some(user_id) {
            seen.push(event.event_type);
        }
    }
    seen
}

#[tokio::test]
async fn test_sse_disconnect_unlists_the_user_after_the_last_stream() {
    let (mut app, state) = create_test_app_with_state().await;
    let (alice, alice_id) = register(&mut app, "presalice").await;
    let (bob, _) = register(&mut app, "presbob").await;
    let mut events = state.event_sender.new_receiver();

    // One stream: alice is listed, and her arrival broadcast
    let (_, first) = open_sse(&mut app, Some(&alice)).await;
    assert!(connected_ids(&mut app, &bob).await.contains(&alice_id));
    assert_eq!(presence_events(&mut events, &alice_id), ["userConnected"]);

    // A second stream (another tab, a reconnection) is no new arrival, and keeps her status
    state.session_manager.update_status(
        &alice_id,
        zapzap_backend::infrastructure::services::SessionStatus::Game,
        Some("some-party".to_string()),
    );
    let (_, mut second) = open_sse(&mut app, Some(&alice)).await;
    read_sse_until(&mut second, "Connected to SSE stream").await;
    assert!(presence_events(&mut events, &alice_id).is_empty());

    // The client drops its first stream: she stays listed, with her status
    drop(first);
    assert!(connected_ids(&mut app, &bob).await.contains(&alice_id));
    let session = state.session_manager.get_session(&alice_id).unwrap();
    assert_eq!(session.status.as_str(), "game");
    assert!(presence_events(&mut events, &alice_id).is_empty());

    // It drops the last one: she is gone, and her departure broadcast once
    drop(second);
    assert!(!connected_ids(&mut app, &bob).await.contains(&alice_id));
    assert_eq!(
        presence_events(&mut events, &alice_id),
        ["userDisconnected"]
    );

    // An anonymous stream registers nobody
    let before = state.session_manager.count();
    let (_, anonymous) = open_sse(&mut app, None).await;
    drop(anonymous);
    assert_eq!(state.session_manager.count(), before);
}

#[tokio::test]
async fn test_only_human_deletes_a_playing_party_against_bots() {
    let (mut app, state) = create_test_app_with_state().await;
    let (human, _) = register(&mut app, "solo_human").await;
    let party_id = create_party_with_seats(&mut app, &human, "Solo vs bots", 3).await;
    for name in ["solo_bot1", "solo_bot2"] {
        let bot_id = create_bot(&state, name).await;
        let (status, body) = post_json_auth(
            &mut app,
            &format!("/api/party/{party_id}/bots"),
            json!({"botId": bot_id}),
            &human,
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "add bot: {body}");
    }
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{party_id}/start"),
        json!({}),
        &human,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "start: {body}");
    // Let the bots' loop take the party, as a game in progress does
    zapzap_backend::application::bot::trigger_bot_turns(&state, &party_id)
        .await
        .unwrap();

    let path = format!("/api/party/{party_id}");
    let (status, body) = send_raw(&mut app, "DELETE", &path, "", None, Some(&human)).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["deletedPartyId"], party_id.as_str());

    // The party, its game state and its bot loop are gone
    assert!(state
        .party_repo
        .find_by_id(&party_id)
        .await
        .unwrap()
        .is_none());
    assert!(state
        .party_repo
        .get_game_state(&party_id)
        .await
        .unwrap()
        .is_none());
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(5);
    while state.bot_runner.party_count() > 0 {
        assert!(
            tokio::time::Instant::now() < deadline,
            "the deleted party's bots are still kept"
        );
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
    }

    // An owner with another human in a playing party still waits for its end
    let (owner, _) = register(&mut app, "duo_owner").await;
    let (other, _) = register(&mut app, "duo_other").await;
    let duo_id = create_party_with_seats(&mut app, &owner, "Duo and a bot", 3).await;
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{duo_id}/join"),
        json!({}),
        &other,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "join: {body}");
    let bot_id = create_bot(&state, "duo_bot").await;
    post_json_auth(
        &mut app,
        &format!("/api/party/{duo_id}/bots"),
        json!({"botId": bot_id}),
        &owner,
    )
    .await;
    let (status, body) = post_json_auth(
        &mut app,
        &format!("/api/party/{duo_id}/start"),
        json!({}),
        &owner,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "start: {body}");
    let path = format!("/api/party/{duo_id}");
    let (status, body) = send_raw(&mut app, "DELETE", &path, "", None, Some(&owner)).await;
    assert_error(status, &body, StatusCode::CONFLICT, "PARTY_PLAYING");
    let (status, body) = send_raw(&mut app, "DELETE", &path, "", None, Some(&other)).await;
    assert_error(status, &body, StatusCode::FORBIDDEN, "NOT_AUTHORIZED");
}
