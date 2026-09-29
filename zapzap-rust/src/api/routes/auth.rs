use std::sync::Arc;

use axum::{
    extract::State,
    http::StatusCode,
    middleware,
    routing::{delete, post, put},
    Extension, Json, Router,
};
use serde::{Deserialize, Serialize};

use crate::api::middleware::{auth_middleware, Claims};
use crate::application::auth::{
    ChangePassword, ChangePasswordError, ChangePasswordInput, ConfirmError, DeleteAccount,
    DeleteAccountError, DeleteAccountInput, LoginUser, LoginUserInput, LoginWithGoogle,
    RegisterUser, RegisterUserInput, RenameError, RenameUser,
};
use crate::application::bot::spawn_bot_turns;
use crate::domain::entities::User;
use crate::domain::repositories::{ForfeitOutcome, SeatForfeit};
use crate::infrastructure::app_state::{AppState, GameEvent};

/// Create auth router
pub fn create_auth_router(state: Arc<AppState>) -> Router<Arc<AppState>> {
    let auth = || middleware::from_fn_with_state(state.clone(), auth_middleware);
    Router::new()
        .route("/register", post(register_handler))
        .route("/login", post(login_handler))
        .route("/google", post(google_handler))
        .route(
            "/me",
            delete(delete_me_handler)
                .patch(rename_me_handler)
                .layer(auth()),
        )
        .route("/me/password", put(change_password_handler).layer(auth()))
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
    user: AccountUserInfo,
    token: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GoogleLoginResponse {
    success: bool,
    user: AccountUserInfo,
    token: String,
    is_new_user: bool,
}

/// The signed-in account as `/login`, `/google` and `PATCH /me` describe it: one shape, so
/// a Google account signing in with its password is stored as the Google account it is
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountUserInfo {
    id: String,
    username: String,
    email: Option<String>,
    is_admin: bool,
    is_google_user: bool,
    /// A Google account may have set a password since (`PUT /me/password`)
    has_password: bool,
}

impl From<&User> for AccountUserInfo {
    fn from(user: &User) -> Self {
        Self {
            id: user.id.clone(),
            username: user.username.clone(),
            email: user.email.clone(),
            is_admin: user.is_admin,
            is_google_user: user.google_id.is_some(),
            has_password: user.password_hash.is_some(),
        }
    }
}

/// `PATCH /me`: the renamed user and a token carrying the name
#[derive(Serialize)]
pub struct RenameResponse {
    success: bool,
    user: AccountUserInfo,
    token: String,
}

#[derive(Serialize)]
pub struct SuccessResponse {
    success: bool,
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
                // Taken, as far as the player is concerned: the clients say so
                crate::application::auth::RegisterError::Reserved => (
                    StatusCode::CONFLICT,
                    "USERNAME_EXISTS",
                    "Username is reserved".to_string(),
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
            user: AccountUserInfo::from(&output.user),
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
                user: AccountUserInfo::from(&output.user),
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

/// What follows an account deletion, by the player or by an admin: the account's live
/// session goes and its event streams end; each game it forfeited a seat in hears of it,
/// and its bots play on when the game goes on (`SeatForfeit`).
pub(crate) fn after_account_deletion(
    state: &Arc<AppState>,
    user_id: &str,
    username: &str,
    forfeits: &[SeatForfeit],
) {
    if state.session_manager.remove_user(user_id).is_some() {
        state.broadcast_event(
            GameEvent::new("userDisconnected", None, Some(user_id.to_string()))
                .with_data(serde_json::json!({ "username": username })),
        );
    }
    for forfeit in forfeits {
        let party_id = Some(forfeit.party_id.clone());
        let user_id = Some(user_id.to_string());
        match &forfeit.outcome {
            ForfeitOutcome::Continues => {
                state.broadcast_event(
                    GameEvent::new("gameUpdate", party_id, user_id)
                        .with_action("playerForfeited")
                        .with_data(serde_json::json!({ "playerIndex": forfeit.player_index })),
                );
                spawn_bot_turns(
                    state,
                    forfeit.party_id.clone(),
                    std::time::Duration::from_millis(100),
                );
            }
            ForfeitOutcome::Finished {
                winner_user_id,
                winner_index,
            } => {
                state.bot_runner.drop_party(&forfeit.party_id);
                state.broadcast_event(
                    GameEvent::new("gameUpdate", party_id, user_id)
                        .with_action("gameFinished")
                        .with_data(serde_json::json!({
                            "gameFinished": true,
                            "playerIndex": forfeit.player_index,
                            "winner": { "userId": winner_user_id, "playerIndex": winner_index },
                        })),
                );
            }
            ForfeitOutcome::Deleted { name, visibility } => {
                state.bot_runner.drop_party(&forfeit.party_id);
                state.broadcast_event(
                    GameEvent::new("partyUpdate", party_id, user_id)
                        .with_action("partyDeleted")
                        .with_data(serde_json::json!({
                            "partyName": name,
                            "visibility": visibility,
                        })),
                );
            }
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
        Ok(deleted) => {
            after_account_deletion(&state, &claims.user_id, &claims.username, &deleted.forfeits);
            Ok(Json(DeleteAccountResponse {
                success: true,
                deleted_user_id: claims.user_id,
            }))
        }
        Err(e) => {
            let (status, code) = match &e {
                DeleteAccountError::NotFound => (StatusCode::NOT_FOUND, "USER_NOT_FOUND"),
                DeleteAccountError::Confirmation(e) => confirmation_refusal(e),
                DeleteAccountError::ActiveParty => (StatusCode::CONFLICT, "ACTIVE_PARTY"),
                DeleteAccountError::LastAdmin => (StatusCode::CONFLICT, "LAST_ADMIN"),
                DeleteAccountError::Repository(_) => {
                    (StatusCode::INTERNAL_SERVER_ERROR, "DELETE_ACCOUNT_ERROR")
                }
            };
            Err(refusal(status, code, &e, "Account deletion failed"))
        }
    }
}

/// The status and code of a refused confirmation (`confirm_identity`). A wrong one is 403,
/// not 401: the clients sign out on a 401.
fn confirmation_refusal(e: &ConfirmError) -> (StatusCode, &'static str) {
    match e {
        ConfirmError::MissingConfirmation => (StatusCode::BAD_REQUEST, "MISSING_CONFIRMATION"),
        ConfirmError::InvalidPassword => (StatusCode::FORBIDDEN, "INVALID_PASSWORD"),
        ConfirmError::GoogleNotConfigured
        | ConfirmError::Google(_)
        | ConfirmError::OtherGoogleAccount
        | ConfirmError::StaleGoogleConfirmation => (StatusCode::FORBIDDEN, "GOOGLE_AUTH_FAILED"),
    }
}

/// A refusal's body: the error's message, or for a 500 `failed`, the message only logged
/// (it may be the database's)
fn refusal(
    status: StatusCode,
    code: &str,
    e: &dyn std::fmt::Display,
    failed: &str,
) -> (StatusCode, Json<ErrorResponse>) {
    let error = if status == StatusCode::INTERNAL_SERVER_ERROR {
        tracing::error!("{}: {}", failed, e);
        failed.to_string()
    } else {
        e.to_string()
    };
    (
        status,
        Json(ErrorResponse {
            error,
            code: code.to_string(),
            details: None,
        }),
    )
}

/// PATCH /api/auth/me - a player changes their username (`{username}`, sign-up's rules).
/// The answer carries a new token: the JWT names the user.
async fn rename_me_handler(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    body: Option<Json<serde_json::Value>>,
) -> Result<Json<RenameResponse>, (StatusCode, Json<ErrorResponse>)> {
    let username = body
        .as_ref()
        .and_then(|Json(b)| b.get("username"))
        .and_then(|v| v.as_str())
        .unwrap_or_default();

    let use_case = RenameUser::new(state.user_repo.clone(), state.jwt_service.clone());
    match use_case
        .execute(&claims.user_id, username, claims.exp)
        .await
    {
        Ok(output) => {
            // Who is online names them by the new name, from now on
            state
                .session_manager
                .rename_user(&output.user.id, &output.user.username);
            Ok(Json(RenameResponse {
                success: true,
                user: AccountUserInfo::from(&output.user),
                token: output.token,
            }))
        }
        Err(e) => {
            let (status, code) = match &e {
                RenameError::Validation(_) => (StatusCode::BAD_REQUEST, "VALIDATION_ERROR"),
                // A reserved name reads as taken, as at sign-up
                RenameError::UsernameExists | RenameError::Reserved => {
                    (StatusCode::CONFLICT, "USERNAME_EXISTS")
                }
                RenameError::NotFound => (StatusCode::NOT_FOUND, "USER_NOT_FOUND"),
                RenameError::Internal(_) | RenameError::Repository(_) => {
                    (StatusCode::INTERNAL_SERVER_ERROR, "ACCOUNT_UPDATE_ERROR")
                }
            };
            Err(refusal(status, code, &e, "Rename failed"))
        }
    }
}

/// PUT /api/auth/me/password - a player changes their password (`{newPassword}`),
/// confirmed as a deletion is: `currentPassword`, or for an account without one a fresh
/// Google ID token (`credential`), which sets its first password.
async fn change_password_handler(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    body: Option<Json<serde_json::Value>>,
) -> Result<Json<SuccessResponse>, (StatusCode, Json<ErrorResponse>)> {
    let field = |name: &str| {
        body.as_ref()
            .and_then(|Json(b)| b.get(name))
            .and_then(|v| v.as_str())
            .map(str::to_string)
    };
    let input = ChangePasswordInput {
        current_password: field("currentPassword"),
        credential: field("credential"),
        new_password: field("newPassword").unwrap_or_default(),
    };

    let use_case = ChangePassword::new(state.user_repo.clone(), state.google_oauth.clone());
    match use_case.execute(&claims.user_id, input).await {
        Ok(()) => Ok(Json(SuccessResponse { success: true })),
        Err(e) => {
            let (status, code) = match &e {
                ChangePasswordError::Validation(_) => (StatusCode::BAD_REQUEST, "VALIDATION_ERROR"),
                ChangePasswordError::NotFound => (StatusCode::NOT_FOUND, "USER_NOT_FOUND"),
                ChangePasswordError::Confirmation(e) => confirmation_refusal(e),
                ChangePasswordError::Internal(_) | ChangePasswordError::Repository(_) => {
                    (StatusCode::INTERNAL_SERVER_ERROR, "PASSWORD_CHANGE_ERROR")
                }
            };
            Err(refusal(status, code, &e, "Password change failed"))
        }
    }
}
