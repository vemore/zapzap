pub mod access;
pub mod dto;
pub mod error;
pub mod middleware;
pub mod not_found;
pub mod routes;
pub mod sse;

// Re-export for convenience
pub use crate::infrastructure::app_state::AppState;
