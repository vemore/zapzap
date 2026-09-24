use std::sync::Arc;

use axum::{
    extract::{Request, State},
    http::StatusCode,
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

/// Extract authenticated user from request
pub async fn auth_middleware(
    State(state): State<Arc<AppState>>,
    mut request: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    // Get authorization header
    let auth_header = request
        .headers()
        .get("Authorization")
        .and_then(|h| h.to_str().ok());

    let token = match auth_header {
        Some(h) if h.starts_with("Bearer ") => &h[7..],
        _ => return Err(StatusCode::UNAUTHORIZED),
    };

    // Verify token
    let claims = state
        .jwt_service
        .verify(token)
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    // The user must still exist (Node: ValidateToken.js), one primary-key lookup
    if !user_exists(&state, &claims.user_id).await {
        return Err(StatusCode::UNAUTHORIZED);
    }

    // Add claims to request extensions
    request.extensions_mut().insert(claims);

    Ok(next.run(request).await)
}

/// Optional auth middleware - doesn't fail if no token
pub async fn optional_auth_middleware(
    State(state): State<Arc<AppState>>,
    mut request: Request,
    next: Next,
) -> Response {
    // Try to get authorization header
    if let Some(auth_header) = request
        .headers()
        .get("Authorization")
        .and_then(|h| h.to_str().ok())
    {
        if let Some(token) = auth_header.strip_prefix("Bearer ") {
            if let Ok(claims) = state.jwt_service.verify(token) {
                if user_exists(&state, &claims.user_id).await {
                    request.extensions_mut().insert(claims);
                }
            }
        }
    }

    next.run(request).await
}

/// Admin middleware - requires an authenticated user who is an admin *now*: the flag is
/// read from the database, not from the token, so a revoked admin loses access at once
/// (Node: `adminMiddleware.js`, same statuses, messages and codes). Mounted inside
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
