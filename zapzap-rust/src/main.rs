use std::net::SocketAddr;
use std::sync::Arc;

use tokio::net::TcpListener;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

// The binary links the library crate: `api::build_app` is the application the API
// tests drive
use zapzap_backend::api;
use zapzap_backend::infrastructure::app_state::{database_url, AppState};
use zapzap_backend::infrastructure::database::{reset_password, seed};

const USAGE: &str = "usage: zapzap-backend            serve the API (PORT, default 9999)
       zapzap-backend seed       create the bot accounts that are missing
       zapzap-backend seed --demo  the bots, and the demo users (password demo123)
       zapzap-backend reset-password <username>  set the user's password to the line
                                   read from stdin (never argv), bcrypt-hashed";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        [] => serve().await,
        ["seed"] => run_seed(false).await,
        ["seed", "--demo"] => run_seed(true).await,
        ["reset-password", username] => run_reset_password(username).await,
        _ => anyhow::bail!("unknown arguments {args:?}\n{USAGE}"),
    }
}

/// `zapzap-backend seed [--demo]`: the accounts a fresh database needs, on the database the
/// server would open (`DATABASE_URL` / `DB_PATH`), created if missing. Needs no JWT_SECRET.
async fn run_seed(demo: bool) -> anyhow::Result<()> {
    dotenvy::dotenv().ok();
    let url = database_url();
    let db = seed::open(&url).await?;
    let report = seed::seed(&db, demo).await?;
    db.close().await;
    println!(
        "seeded {url}: created {} [{}], already there {} [{}]",
        report.created.len(),
        report.created.join(", "),
        report.existing.len(),
        report.existing.join(", ")
    );
    Ok(())
}

/// `zapzap-backend reset-password <username>`: reads the new password from stdin — one
/// line, never a command-line argument, so it never lands in argv, a shell history or a
/// process list — and stores its bcrypt hash on the database the server would open. Needs
/// no `JWT_SECRET`. Exits with an error, the database untouched, when stdin is empty or
/// blank or when no such username exists.
async fn run_reset_password(username: &str) -> anyhow::Result<()> {
    dotenvy::dotenv().ok();

    let mut new_password = String::new();
    std::io::stdin().read_line(&mut new_password)?;
    let new_password = new_password.trim_end_matches(['\n', '\r']);
    if new_password.is_empty() {
        anyhow::bail!("empty password on stdin\n{USAGE}");
    }

    let url = database_url();
    let db = seed::open(&url).await?;
    let outcome = reset_password::reset_password(&db, username, new_password).await?;
    db.close().await;

    match outcome {
        reset_password::ResetOutcome::Reset => {
            println!("password reset for {username}");
            Ok(())
        }
        reset_password::ResetOutcome::NotFound => {
            anyhow::bail!("no such user: {username}")
        }
    }
}

async fn serve() -> anyhow::Result<()> {
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
