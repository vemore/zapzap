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
    let (status, body) = post_json(
        &mut app,
        "/api/auth/register",
        json!({"username": "test"}),
    )
    .await;
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
    let (status, body) = post_json_auth(
        &mut app,
        "/api/party",
        json!({}),
        token,
    )
    .await;

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
