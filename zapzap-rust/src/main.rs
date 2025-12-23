// Allow dead code for features under development
#![allow(dead_code)]

use std::net::SocketAddr;
use std::sync::Arc;

use axum::Router;
use tokio::net::TcpListener;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod api;
mod application;
mod domain;
mod infrastructure;

use crate::infrastructure::app_state::AppState;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load environment variables
    dotenvy::dotenv().ok();

    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "zapzap_backend=debug,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Initialize application state
    let state = AppState::new().await?;
    let state = Arc::new(state);

    // Build router
    let app = Router::new()
        .nest("/api", api::routes::create_api_router(state.clone()))
        .route("/suscribeupdate", axum::routing::get(api::sse::sse_handler))
        .route("/health", axum::routing::get(api::routes::health::health_handler))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    // Get port from environment or use default
    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(9999);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("Starting ZapZap backend on {}", addr);

    let listener = TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
