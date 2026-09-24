pub mod access;
pub mod dto;
pub mod error;
pub mod middleware;
pub mod not_found;
pub mod routes;
pub mod sse;

// Re-export for convenience
pub use crate::infrastructure::app_state::AppState;

use std::sync::Arc;

use axum::Router;
use tower_http::{cors::CorsLayer, trace::TraceLayer};

/// The whole HTTP application, as `main` serves it and the API tests drive it: `/api`,
/// `/suscribeupdate` (SSE) and `/health`. A path no route serves, and a served path with a
/// method it does not serve, answer Node's `ROUTE_NOT_FOUND` 404 (`not_found.rs`), except
/// under `/api/admin`, whose router sets its own behind the auth and admin checks.
pub fn build_app(state: Arc<AppState>) -> Router {
    Router::new()
        .nest("/api", routes::create_api_router(state.clone()))
        .route("/suscribeupdate", axum::routing::get(sse::sse_handler))
        .route(
            "/health",
            axum::routing::get(routes::health::root_health_handler),
        )
        // After every route, so that it reaches them all, nested ones included
        .method_not_allowed_fallback(not_found::route_not_found)
        .fallback(not_found::route_not_found)
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}
