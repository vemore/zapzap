use std::sync::Arc;

use axum::{
    extract::{Request, State},
    http::StatusCode,
    middleware::Next,
    response::Response,
};

use crate::infrastructure::app_state::AppState;

// Re-export Claims for use in route handlers
pub use crate::infrastructure::auth::Claims;

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
        if auth_header.starts_with("Bearer ") {
            let token = &auth_header[7..];
            if let Ok(claims) = state.jwt_service.verify(token) {
                request.extensions_mut().insert(claims);
            }
        }
    }

    next.run(request).await
}

/// Admin middleware - requires authenticated admin user
pub async fn admin_middleware(
    State(_state): State<Arc<AppState>>,
    request: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    // Get claims from request extensions (set by auth_middleware)
    let claims = request
        .extensions()
        .get::<Claims>()
        .ok_or(StatusCode::UNAUTHORIZED)?;

    if !claims.is_admin {
        return Err(StatusCode::FORBIDDEN);
    }

    Ok(next.run(request).await)
}
