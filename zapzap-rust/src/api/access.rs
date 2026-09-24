//! Party membership checks shared by the route handlers that have no use case to hold them.

use crate::api::error::ApiError;
use crate::domain::repositories::PartyRepository;
use crate::infrastructure::app_state::AppState;

/// `Ok` when `user_id` is a player of `party_id`; otherwise 404 `PARTY_NOT_FOUND` for a
/// missing party, 403 `NOT_IN_PARTY` for a non-member (Node's messages and codes).
pub async fn require_party_member(
    state: &AppState,
    party_id: &str,
    user_id: &str,
) -> Result<(), ApiError> {
    let internal = |e| ApiError::internal("INTERNAL_ERROR", "Internal server error", e);
    if state
        .party_repo
        .find_by_id(party_id)
        .await
        .map_err(internal)?
        .is_none()
    {
        return Err(ApiError::party_not_found());
    }
    if !state
        .party_repo
        .is_player_in_party(party_id, user_id)
        .await
        .map_err(internal)?
    {
        return Err(ApiError::not_in_party());
    }
    Ok(())
}
