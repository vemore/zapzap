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
// Google login and bot administration
// ============================================================================

mod google_and_bot_admin {
    use super::*;
    use jsonwebtoken::jwk::JwkSet;
    use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
    use zapzap_backend::domain::repositories::UserRepository;
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
        let mut request = Request::builder().method("DELETE").uri(path);
        if let Some(token) = token {
            request = request.header("Authorization", format!("Bearer {}", token));
        }
        let response = ServiceExt::<Request<Body>>::ready(app)
            .await
            .unwrap()
            .call(request.body(Body::empty()).unwrap())
            .await
            .unwrap();
        let status = response.status();
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        (
            status,
            serde_json::from_slice(&bytes).unwrap_or(Value::Null),
        )
    }

    /// Register a human and return (id, token); `admin` makes it an admin first
    async fn user_token(
        app: &mut Router,
        state: &AppState,
        name: &str,
        admin: bool,
    ) -> (String, String) {
        let (status, body) = post_json(
            app,
            "/api/auth/register",
            json!({"username": name, "password": "secret123"}),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED);
        let id = body["user"]["id"].as_str().unwrap().to_string();
        let token = if admin {
            state.user_repo.set_admin(&id, true).await.unwrap();
            state.jwt_service.sign(&id, name, true).unwrap()
        } else {
            body["token"].as_str().unwrap().to_string()
        };
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
