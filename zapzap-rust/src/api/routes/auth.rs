use std::sync::Arc;

use axum::{
    extract::State,
    http::StatusCode,
    middleware,
    routing::{delete, post},
    Extension, Json, Router,
};
use serde::{Deserialize, Serialize};

use crate::api::middleware::{auth_middleware, Claims};
use crate::application::auth::{
    DeleteAccount, DeleteAccountError, DeleteAccountInput, LoginUser, LoginUserInput,
    LoginWithGoogle, RegisterUser, RegisterUserInput,
};
use crate::infrastructure::app_state::{AppState, GameEvent};

/// Create auth router
pub fn create_auth_router(state: Arc<AppState>) -> Router<Arc<AppState>> {
    Router::new()
        .route("/register", post(register_handler))
        .route("/login", post(login_handler))
        .route("/google", post(google_handler))
        .route(
            "/me",
            delete(delete_me_handler).layer(middleware::from_fn_with_state(state, auth_middleware)),
        )
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
    /// Unix seconds, as Node
    created_at: i64,
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
#[serde(rename_all = "camelCase")]
pub struct GoogleLoginResponse {
    success: bool,
    user: GoogleUserInfo,
    token: String,
    is_new_user: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GoogleUserInfo {
    id: String,
    username: String,
    email: Option<String>,
    is_admin: bool,
    is_google_user: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteAccountResponse {
    success: bool,
    deleted_user_id: String,
}

#[derive(Serialize)]
pub struct ErrorResponse {
    error: String,
    code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    details: Option<String>,
}

// ========== Handlers ==========

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
                    created_at: output.user.created_at,
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

/// POST /api/auth/google - login or sign up with a Google ID token (`credential`), as
/// the Node backend did
async fn google_handler(
    State(state): State<Arc<AppState>>,
    body: Option<Json<serde_json::Value>>,
) -> Result<Json<GoogleLoginResponse>, (StatusCode, Json<ErrorResponse>)> {
    let credential = body.as_ref().and_then(|Json(b)| b.get("credential"));

    // Node refuses a falsy credential (`!credential`) with 400
    let falsy = match credential {
        None | Some(serde_json::Value::Null) => true,
        Some(serde_json::Value::Bool(b)) => !b,
        Some(serde_json::Value::String(s)) => s.is_empty(),
        Some(serde_json::Value::Number(n)) => n.as_f64() == Some(0.0),
        _ => false,
    };
    if falsy {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Token Google requis".to_string(),
                code: "MISSING_CREDENTIAL".to_string(),
                details: None,
            }),
        ));
    }
    // A truthy non-string credential fails in the use case with "Token Google requis"
    let credential = credential.and_then(|c| c.as_str()).unwrap_or_default();

    let use_case = LoginWithGoogle::new(
        state.user_repo.clone(),
        state.jwt_service.clone(),
        state.google_oauth.clone(),
    );

    match use_case.execute(credential).await {
        Ok(output) => {
            tracing::info!(
                "Google auth successful: {} (new: {})",
                output.user.username,
                output.is_new_user
            );
            Ok(Json(GoogleLoginResponse {
                success: true,
                user: GoogleUserInfo {
                    id: output.user.id.clone(),
                    username: output.user.username.clone(),
                    email: output.user.email.clone(),
                    is_admin: output.user.is_admin,
                    is_google_user: output.user.google_id.is_some(),
                },
                token: output.token,
                is_new_user: output.is_new_user,
            }))
        }
        Err(e) if e.is_auth_failure() => {
            tracing::warn!("Google auth failed: {}", e);
            Err((
                StatusCode::UNAUTHORIZED,
                Json(ErrorResponse {
                    error: e.to_string(),
                    code: "GOOGLE_AUTH_FAILED".to_string(),
                    details: None,
                }),
            ))
        }
        Err(e) => {
            tracing::error!("Google auth error: {}", e);
            Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: "Authentification Google échouée".to_string(),
                    code: "GOOGLE_AUTH_ERROR".to_string(),
                    // The database's message stays in the log
                    details: Some(match e {
                        crate::application::auth::LoginWithGoogleError::NoUniqueUsername => {
                            e.to_string()
                        }
                        _ => "Internal error".to_string(),
                    }),
                }),
            ))
        }
    }
}

/// DELETE /api/auth/me - a player deletes their own account, confirmed by `password`, or
/// for an account created with Google by `credential`, a fresh Google ID token of that
/// account. A wrong confirmation is 403, not 401: the clients sign out on a 401.
async fn delete_me_handler(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    body: Option<Json<serde_json::Value>>,
) -> Result<Json<DeleteAccountResponse>, (StatusCode, Json<ErrorResponse>)> {
    let field = |name: &str| {
        body.as_ref()
            .and_then(|Json(b)| b.get(name))
            .and_then(|v| v.as_str())
            .map(str::to_string)
    };
    let input = DeleteAccountInput {
        password: field("password"),
        credential: field("credential"),
    };

    let use_case = DeleteAccount::new(state.user_repo.clone(), state.google_oauth.clone());
    match use_case.execute(&claims.user_id, input).await {
        Ok(_) => {
            // The account's live session goes with it; its streams now name nobody
            if state.session_manager.remove_user(&claims.user_id).is_some() {
                state.broadcast_event(
                    GameEvent::new("userDisconnected", None, Some(claims.user_id.clone()))
                        .with_data(serde_json::json!({ "username": claims.username })),
                );
            }
            Ok(Json(DeleteAccountResponse {
                success: true,
                deleted_user_id: claims.user_id,
            }))
        }
        Err(e) => {
            let (status, code) = match &e {
                DeleteAccountError::NotFound => (StatusCode::NOT_FOUND, "USER_NOT_FOUND"),
                DeleteAccountError::MissingConfirmation => {
                    (StatusCode::BAD_REQUEST, "MISSING_CONFIRMATION")
                }
                DeleteAccountError::InvalidPassword => (StatusCode::FORBIDDEN, "INVALID_PASSWORD"),
                DeleteAccountError::GoogleNotConfigured
                | DeleteAccountError::Google(_)
                | DeleteAccountError::OtherGoogleAccount
                | DeleteAccountError::StaleGoogleConfirmation => {
                    (StatusCode::FORBIDDEN, "GOOGLE_AUTH_FAILED")
                }
                DeleteAccountError::ActiveParty => (StatusCode::CONFLICT, "ACTIVE_PARTY"),
                DeleteAccountError::LastAdmin => (StatusCode::CONFLICT, "LAST_ADMIN"),
                DeleteAccountError::Repository(_) => {
                    (StatusCode::INTERNAL_SERVER_ERROR, "DELETE_ACCOUNT_ERROR")
                }
            };
            let error = if status == StatusCode::INTERNAL_SERVER_ERROR {
                // The database's message stays in the log
                tracing::error!("Account deletion failed: {}", e);
                "Account deletion failed".to_string()
            } else {
                e.to_string()
            };
            Err((
                status,
                Json(ErrorResponse {
                    error,
                    code: code.to_string(),
                    details: None,
                }),
            ))
        }
    }
}
