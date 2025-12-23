use std::sync::Arc;

use axum::{extract::State, http::StatusCode, routing::post, Json, Router};
use serde::{Deserialize, Serialize};

use crate::application::auth::{LoginUser, LoginUserInput, RegisterUser, RegisterUserInput};
use crate::infrastructure::app_state::AppState;

/// Create auth router
pub fn create_auth_router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/register", post(register_handler))
        .route("/login", post(login_handler))
}

// ========== DTOs ==========

#[derive(Deserialize)]
pub struct RegisterRequest {
    username: Option<String>,
    password: Option<String>,
}

#[derive(Deserialize)]
pub struct LoginRequest {
    username: Option<String>,
    password: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RegisterResponse {
    success: bool,
    user: RegisterUserInfo,
    token: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RegisterUserInfo {
    id: String,
    username: String,
    created_at: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginResponse {
    success: bool,
    user: LoginUserInfo,
    token: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginUserInfo {
    id: String,
    username: String,
    is_admin: bool,
}

#[derive(Serialize)]
pub struct ErrorResponse {
    error: String,
    code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    details: Option<String>,
}

// ========== Handlers ==========

/// Convert timestamp to RFC3339 string
fn timestamp_to_rfc3339(ts: i64) -> String {
    chrono::DateTime::from_timestamp(ts, 0)
        .map(|dt| dt.to_rfc3339())
        .unwrap_or_else(|| "1970-01-01T00:00:00Z".to_string())
}

async fn register_handler(
    State(state): State<Arc<AppState>>,
    Json(req): Json<RegisterRequest>,
) -> Result<(StatusCode, Json<RegisterResponse>), (StatusCode, Json<ErrorResponse>)> {
    // Validate required fields (matching JS behavior)
    let username = req.username.filter(|s| !s.is_empty()).ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Username and password are required".to_string(),
                code: "MISSING_CREDENTIALS".to_string(),
                details: None,
            }),
        )
    })?;

    let password = req.password.filter(|s| !s.is_empty()).ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Username and password are required".to_string(),
                code: "MISSING_CREDENTIALS".to_string(),
                details: None,
            }),
        )
    })?;

    let use_case = RegisterUser::new(state.user_repo.clone(), state.jwt_service.clone());

    let input = RegisterUserInput { username, password };

    match use_case.execute(input).await {
        Ok(output) => Ok((
            StatusCode::CREATED,
            Json(RegisterResponse {
                success: true,
                user: RegisterUserInfo {
                    id: output.user.id.clone(),
                    username: output.user.username.clone(),
                    created_at: timestamp_to_rfc3339(output.user.created_at),
                },
                token: output.token,
            }),
        )),
        Err(e) => {
            let (status, code, message) = match &e {
                crate::application::auth::RegisterError::Validation(msg) => {
                    (StatusCode::BAD_REQUEST, "VALIDATION_ERROR", msg.clone())
                }
                crate::application::auth::RegisterError::UsernameExists => (
                    StatusCode::CONFLICT,
                    "USERNAME_EXISTS",
                    "Username already exists".to_string(),
                ),
                _ => (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "REGISTRATION_ERROR",
                    "Registration failed".to_string(),
                ),
            };
            Err((
                status,
                Json(ErrorResponse {
                    error: message,
                    code: code.to_string(),
                    details: if matches!(status, StatusCode::INTERNAL_SERVER_ERROR) {
                        Some(e.to_string())
                    } else {
                        None
                    },
                }),
            ))
        }
    }
}

async fn login_handler(
    State(state): State<Arc<AppState>>,
    Json(req): Json<LoginRequest>,
) -> Result<Json<LoginResponse>, (StatusCode, Json<ErrorResponse>)> {
    // Validate required fields (matching JS behavior)
    let username = req.username.filter(|s| !s.is_empty()).ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Username and password are required".to_string(),
                code: "MISSING_CREDENTIALS".to_string(),
                details: None,
            }),
        )
    })?;

    let password = req.password.filter(|s| !s.is_empty()).ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Username and password are required".to_string(),
                code: "MISSING_CREDENTIALS".to_string(),
                details: None,
            }),
        )
    })?;

    let use_case = LoginUser::new(state.user_repo.clone(), state.jwt_service.clone());

    let input = LoginUserInput { username, password };

    match use_case.execute(input).await {
        Ok(output) => Ok(Json(LoginResponse {
            success: true,
            user: LoginUserInfo {
                id: output.user.id.clone(),
                username: output.user.username.clone(),
                is_admin: output.user.is_admin,
            },
            token: output.token,
        })),
        Err(e) => {
            let (status, code, message) = match &e {
                crate::application::auth::LoginError::Validation(msg) => {
                    (StatusCode::BAD_REQUEST, "VALIDATION_ERROR", msg.clone())
                }
                crate::application::auth::LoginError::InvalidCredentials => (
                    StatusCode::UNAUTHORIZED,
                    "INVALID_CREDENTIALS",
                    "Invalid username or password".to_string(),
                ),
                _ => (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "LOGIN_ERROR",
                    "Login failed".to_string(),
                ),
            };
            Err((
                status,
                Json(ErrorResponse {
                    error: message,
                    code: code.to_string(),
                    details: if matches!(status, StatusCode::INTERNAL_SERVER_ERROR) {
                        Some(e.to_string())
                    } else {
                        None
                    },
                }),
            ))
        }
    }
}
