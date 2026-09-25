use std::sync::Arc;

use axum::{
    extract::{Request, State},
    http::{header::AUTHORIZATION, HeaderMap, StatusCode},
    middleware::Next,
    response::{IntoResponse, Json, Response},
};

use crate::domain::repositories::UserRepository;
use crate::infrastructure::app_state::AppState;

// Re-export Claims for use in route handlers
pub use crate::infrastructure::auth::Claims;

/// Whether the token's user is still in the database; a lookup error counts as no.
pub async fn user_exists(state: &AppState, user_id: &str) -> bool {
    match state.user_repo.find_by_id(user_id).await {
        Ok(user) => user.is_some(),
        Err(e) => {
            tracing::error!("Auth user lookup failed: {}", e);
            false
        }
    }
}

/// Why a request carries no usable bearer token.
enum BearerError {
    /// No `Authorization` header, or an empty one (Express reads it as absent)
    Missing,
    /// A header that is not exactly `Bearer <token>`
    Malformed,
}

/// The token of an `Authorization: Bearer <token>` header, read as the Node backend's
/// middlewares did: split on single spaces, exactly two parts, the first `Bearer`.
fn bearer_token(headers: &HeaderMap) -> Result<&str, BearerError> {
    let header = match headers.get(AUTHORIZATION) {
        Some(h) if !h.is_empty() => h,
        _ => return Err(BearerError::Missing),
    };
    let text = header.to_str().map_err(|_| BearerError::Malformed)?;
    match text.split(' ').collect::<Vec<_>>().as_slice() {
        ["Bearer", token] => Ok(token),
        _ => Err(BearerError::Malformed),
    }
}

/// A 401 in the Node backend's shape: `{error, code, details?}`.
fn unauthorized(error: &str, code: &str, details: Option<serde_json::Value>) -> Response {
    let mut body = serde_json::json!({ "error": error, "code": code });
    if let Some(details) = details {
        body["details"] = details;
    }
    (StatusCode::UNAUTHORIZED, Json(body)).into_response()
}

/// Extract authenticated user from request. Refusals match the Node backend's:
/// no header is `MISSING_AUTH_HEADER`, a header that is not exactly `Bearer <token>` is
/// `INVALID_AUTH_FORMAT`, and a bad or expired token, or one whose user no longer exists
/// (the Node backend answered the same), is `INVALID_TOKEN`.
pub async fn auth_middleware(
    State(state): State<Arc<AppState>>,
    mut request: Request,
    next: Next,
) -> Response {
    let invalid_token = || unauthorized("Invalid or expired token", "INVALID_TOKEN", None);

    let claims = match bearer_token(request.headers()) {
        Ok(token) => match state.jwt_service.verify(token) {
            Ok(claims) => claims,
            Err(_) => return invalid_token(),
        },
        Err(BearerError::Missing) => {
            return unauthorized("Missing authorization header", "MISSING_AUTH_HEADER", None)
        }
        Err(BearerError::Malformed) => {
            return unauthorized(
                "Invalid authorization header format",
                "INVALID_AUTH_FORMAT",
                Some(serde_json::json!({ "expected": "Bearer <token>" })),
            )
        }
    };

    // The user must still exist, one primary-key lookup
    if !user_exists(&state, &claims.user_id).await {
        return invalid_token();
    }

    // Add claims to request extensions
    request.extensions_mut().insert(claims);

    next.run(request).await
}

/// Optional auth middleware - doesn't fail if no token: a well-formed header with a valid
/// token of an existing user attaches the claims, anything else goes on without them
pub async fn optional_auth_middleware(
    State(state): State<Arc<AppState>>,
    mut request: Request,
    next: Next,
) -> Response {
    let claims = bearer_token(request.headers())
        .ok()
        .and_then(|token| state.jwt_service.verify(token).ok());
    if let Some(claims) = claims {
        if user_exists(&state, &claims.user_id).await {
            request.extensions_mut().insert(claims);
        }
    }

    next.run(request).await
}

/// Admin middleware - requires an authenticated user who is an admin *now*: the flag is
/// read from the database, not from the token, so a revoked admin loses access at once
/// (the Node backend's statuses, messages and codes). Mounted inside
/// `auth_middleware`, which sets the claims.
pub async fn admin_middleware(
    State(state): State<Arc<AppState>>,
    request: Request,
    next: Next,
) -> Response {
    let refuse = |status: StatusCode, error: &str, code: &str| {
        let body = serde_json::json!({ "success": false, "error": error, "code": code });
        (status, Json(body)).into_response()
    };

    let Some(claims) = request.extensions().get::<Claims>() else {
        return refuse(
            StatusCode::UNAUTHORIZED,
            "Authentication required",
            "AUTH_REQUIRED",
        );
    };

    match state.user_repo.find_by_id(&claims.user_id).await {
        Ok(Some(user)) if user.is_admin => next.run(request).await,
        Ok(_) => refuse(
            StatusCode::FORBIDDEN,
            "Admin access required",
            "ADMIN_REQUIRED",
        ),
        Err(e) => {
            tracing::error!("Admin middleware error: {}", e);
            refuse(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Internal server error",
                "INTERNAL_ERROR",
            )
        }
    }
}
