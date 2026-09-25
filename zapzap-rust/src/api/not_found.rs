//! The answer to a path no route serves, in the Node backend's shape (its last
//! handler): 404 `{error, code: "ROUTE_NOT_FOUND", path, message}`, for any path.

use axum::{
    extract::OriginalUri,
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};

/// Router fallback: `path` is the full request path, without the query string (Express's
/// `req.path`), also from inside a nested router.
pub async fn route_not_found(OriginalUri(uri): OriginalUri) -> Response {
    let body = serde_json::json!({
        "error": "Not Found",
        "code": "ROUTE_NOT_FOUND",
        "path": uri.path(),
        "message": "The requested endpoint does not exist",
    });
    (StatusCode::NOT_FOUND, Json(body)).into_response()
}
