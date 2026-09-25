//! Health checks, with the Node backend's keys: `/api/health` answers
//! `{status, timestamp, uptime}`, `/health` answers `{status, timestamp, api}`.
//! Healthchecks and scripts/deploy_nas.sh read only the status code.

use axum::Json;
use serde::Serialize;

#[derive(Serialize)]
pub struct ApiHealthResponse {
    status: &'static str,
    /// ISO-8601 with milliseconds, as JavaScript's `toISOString()`
    timestamp: String,
    /// Seconds since the process started, fractional, as Node's `process.uptime()`
    uptime: f64,
}

#[derive(Serialize)]
pub struct RootHealthResponse {
    status: &'static str,
    timestamp: String,
    api: &'static str,
}

static START_TIME: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();

/// Start the uptime clock; `main` calls it at startup, so the first health check does not
/// read an uptime of zero.
pub fn start_clock() {
    START_TIME.get_or_init(std::time::Instant::now);
}

fn now_iso() -> String {
    chrono::Utc::now()
        .format("%Y-%m-%dT%H:%M:%S%.3fZ")
        .to_string()
}

/// `GET /api/health`
pub async fn health_handler() -> Json<ApiHealthResponse> {
    let start = START_TIME.get_or_init(std::time::Instant::now);
    Json(ApiHealthResponse {
        status: "ok",
        timestamp: now_iso(),
        uptime: start.elapsed().as_secs_f64(),
    })
}

/// `GET /health`
pub async fn root_health_handler() -> Json<RootHealthResponse> {
    Json(RootHealthResponse {
        status: "ok",
        timestamp: now_iso(),
        api: "v2 (Clean Architecture)",
    })
}
