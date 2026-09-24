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
    // Set test environment
    std::env::set_var("DATABASE_URL", "sqlite::memory:");
    std::env::set_var("JWT_SECRET", "test-secret-key");

    let state = AppState::new().await.expect("Failed to create app state");
    let state = Arc::new(state);

    Router::new()
        .nest("/api", api::routes::create_api_router(state.clone()))
        .with_state(state)
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
// Security: JWT secret, authorization, SSE filtering
// ============================================================================

/// The test app, with the SSE route, and its state (to seed rows and broadcast events).
async fn create_test_app_with_state() -> (Router, Arc<AppState>) {
    std::env::set_var("DATABASE_URL", "sqlite::memory:");
    std::env::set_var("JWT_SECRET", "test-secret-key");

    let state = Arc::new(AppState::new().await.expect("Failed to create app state"));
    let app = Router::new()
        .nest("/api", api::routes::create_api_router(state.clone()))
        .route("/suscribeupdate", axum::routing::get(api::sse::sse_handler))
        .with_state(state.clone());
    (app, state)
}

/// Register `username`; returns its token and user id.
async fn register(app: &mut Router, username: &str) -> (String, String) {
    let (status, body) = post_json(
        app,
        "/api/auth/register",
        json!({ "username": username, "password": "password123" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "register {username}: {body}");
    (
        body["token"].as_str().unwrap().to_string(),
        body["user"]["id"].as_str().unwrap().to_string(),
    )
}

/// Create a party owned by the token's user; returns its id and invite code.
async fn create_party(app: &mut Router, token: &str, visibility: &str) -> (String, String) {
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
    let (party_id, invite_code) = create_party(&mut app, &owner, "private").await;
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
    let (party_id, invite_code) = create_party(&mut app, &owner, "private").await;
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
    let (party_id, _) = create_party(&mut app, &owner, "public").await;

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
    let (party_id, _) = create_party(&mut app, &owner, "public").await;

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
    let (party_id, _) = create_party(&mut app, &owner, "public").await;

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
    let (private_id, _) = create_party(&mut app, &owner, "private").await;
    let (public_id, _) = create_party(&mut app, &owner, "public").await;

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
    let (alice_party, _) = create_party(&mut app, &alice, "public").await;
    let (bob_party, _) = create_party(&mut app, &bob, "public").await;

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
    let (public_party, _) = create_party(&mut app, &bob, "public").await;
    let (private_party, _) = create_party(&mut app, &bob, "private").await;

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
    let (private_id, _) = create_party(&mut app, &owner, "private").await;
    let (public_id, _) = create_party(&mut app, &owner, "public").await;
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
    assert_eq!(body["total"], 1);
}

#[tokio::test]
async fn test_deleted_users_token_is_refused() {
    use zapzap_backend::infrastructure::app_state::GameEvent;

    let (mut app, state) = create_test_app_with_state().await;
    let (token, user_id) = register(&mut app, "goneuser").await;
    let (other, _) = register(&mut app, "stayinguser").await;
    let (private_party, _) = create_party(&mut app, &other, "private").await;

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
