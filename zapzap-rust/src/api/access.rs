//! Party membership checks shared by the route handlers that have no use case to hold them.

use axum::http::StatusCode;

use crate::domain::repositories::{PartyRepository, RepositoryError};
use crate::infrastructure::app_state::AppState;

/// Why a caller may not act on a party: the status, message and code to answer with.
pub type Denied = (StatusCode, String, &'static str);

/// `None` when `user_id` is a player of `party_id`; otherwise 404 `PARTY_NOT_FOUND` for a
/// missing party, 403 `NOT_IN_PARTY` for a non-member (Node's messages and codes).
pub async fn require_party_member(
    state: &AppState,
    party_id: &str,
    user_id: &str,
) -> Option<Denied> {
    let internal = |e: RepositoryError| {
        Some((
            StatusCode::INTERNAL_SERVER_ERROR,
            e.to_string(),
            "INTERNAL_ERROR",
        ))
    };
    match state.party_repo.find_by_id(party_id).await {
        Ok(Some(_)) => {}
        Ok(None) => {
            return Some((
                StatusCode::NOT_FOUND,
                "Party not found".to_string(),
                "PARTY_NOT_FOUND",
            ))
        }
        Err(e) => return internal(e),
    }
    match state.party_repo.is_player_in_party(party_id, user_id).await {
        Ok(true) => None,
        Ok(false) => Some((
            StatusCode::FORBIDDEN,
            "User is not in this party".to_string(),
            "NOT_IN_PARTY",
        )),
        Err(e) => internal(e),
    }
}
