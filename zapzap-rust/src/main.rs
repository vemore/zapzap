use std::net::SocketAddr;
use std::sync::Arc;

use tokio::net::TcpListener;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use zapzap_backend::api;
use zapzap_backend::infrastructure::app_state::AppState;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // First, so that /api/health's uptime counts from process start, as Node's
    api::routes::health::start_clock();

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

    // The whole router, the same the API tests drive (`api::build_app`)
    let app = api::build_app(state);

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
