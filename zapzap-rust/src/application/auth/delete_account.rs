//! A player deletes their own account, confirmed by their password or, for an account
//! created with Google, by a fresh Google ID token of the same Google account
//! (`confirm_identity`). Their finished games stay in the other players' history under an
//! anonymous user (`UserRepository::delete_account`). A seat in a game in progress is
//! forfeited; a waiting party refuses the deletion until the player leaves it.

use std::sync::Arc;

use super::confirm_identity::{confirm_identity, ConfirmError};
use crate::domain::repositories::{AccountDeletion, SeatForfeit, UserRepository};
use crate::infrastructure::services::GoogleOAuthService;

/// What confirms the deletion
pub struct DeleteAccountInput {
    pub password: Option<String>,
    /// A Google ID token, for an account without a password
    pub credential: Option<String>,
}

/// What a deletion did besides removing the account
#[derive(Debug)]
pub struct DeletedAccount {
    /// The anonymous user the account's games went to, `None` when it had played none
    pub anonymised_as: Option<String>,
    /// The seats given up in games in progress
    pub forfeits: Vec<SeatForfeit>,
}

/// Delete own account use case
pub struct DeleteAccount {
    user_repo: Arc<dyn UserRepository>,
    google: Option<Arc<GoogleOAuthService>>,
}

impl DeleteAccount {
    /// `google` is `None` when `GOOGLE_OAUTH_CLIENT_ID` is not configured
    pub fn new(
        user_repo: Arc<dyn UserRepository>,
        google: Option<Arc<GoogleOAuthService>>,
    ) -> Self {
        Self { user_repo, google }
    }

    /// Deletes the user; returns where their games went and the seats they gave up
    pub async fn execute(
        &self,
        user_id: &str,
        input: DeleteAccountInput,
    ) -> Result<DeletedAccount, DeleteAccountError> {
        let user = self
            .user_repo
            .find_by_id(user_id)
            .await?
            .ok_or(DeleteAccountError::NotFound)?;
        confirm_identity(
            &user,
            input.password.as_deref(),
            input.credential.as_deref(),
            self.google.as_deref(),
        )
        .await?;

        match self.user_repo.delete_account(user_id).await? {
            AccountDeletion::Deleted {
                anonymised_as,
                forfeits,
            } => {
                tracing::info!(
                    "Account deleted: {} ({}), {} seat(s) forfeited",
                    user.username,
                    user.id,
                    forfeits.len()
                );
                Ok(DeletedAccount {
                    anonymised_as,
                    forfeits,
                })
            }
            AccountDeletion::NotFound => Err(DeleteAccountError::NotFound),
            AccountDeletion::ActiveParty => Err(DeleteAccountError::ActiveParty),
            AccountDeletion::LastAdmin => Err(DeleteAccountError::LastAdmin),
        }
    }
}

/// Delete account error types
#[derive(Debug, thiserror::Error)]
pub enum DeleteAccountError {
    #[error("User not found")]
    NotFound,
    #[error(transparent)]
    Confirmation(#[from] ConfirmError),
    #[error("Leave your waiting parties first")]
    ActiveParty,
    #[error("The only admin cannot delete their account")]
    LastAdmin,
    #[error("Repository error: {0}")]
    Repository(#[from] crate::domain::repositories::RepositoryError),
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::application::auth::GOOGLE_CONFIRMATION_MAX_AGE_SECS;
    use crate::domain::entities::User;
    use crate::infrastructure::database::repositories::racing_user_repo::RacingUserRepo;
    use crate::infrastructure::services::google_oauth_test_keys::{
        claims, key_set, sign, CLIENT_ID, KID,
    };

    async fn setup() -> (DeleteAccount, Arc<RacingUserRepo>) {
        let repo = Arc::new(RacingUserRepo::new().await);
        let google = Arc::new(GoogleOAuthService::with_keys(CLIENT_ID.into(), key_set()));
        (DeleteAccount::new(repo.clone(), Some(google)), repo)
    }

    async fn google_user(repo: &RacingUserRepo, google_id: &str) -> User {
        let user = User::new_google(
            "u-google".into(),
            "Ada".into(),
            google_id.into(),
            "ada@example.com".into(),
        );
        repo.save(&user).await.unwrap();
        user
    }

    fn with_credential(credential: String) -> DeleteAccountInput {
        DeleteAccountInput {
            password: None,
            credential: Some(credential),
        }
    }

    #[tokio::test]
    async fn google_account_is_deleted_with_a_token_of_the_same_account() {
        let (use_case, repo) = setup().await;
        let user = google_user(&repo, "g-7").await;

        let err = use_case
            .execute(
                &user.id,
                with_credential(sign(&claims("g-8", serde_json::json!({})), KID)),
            )
            .await
            .unwrap_err();
        assert!(matches!(
            err,
            DeleteAccountError::Confirmation(ConfirmError::OtherGoogleAccount)
        ));
        let err = use_case
            .execute(&user.id, with_credential("not-a-token".into()))
            .await
            .unwrap_err();
        assert!(matches!(
            err,
            DeleteAccountError::Confirmation(ConfirmError::Google(_))
        ));
        let err = use_case
            .execute(
                &user.id,
                DeleteAccountInput {
                    password: Some("anything".into()),
                    credential: None,
                },
            )
            .await
            .unwrap_err();
        assert!(matches!(
            err,
            DeleteAccountError::Confirmation(ConfirmError::MissingConfirmation)
        ));
        assert!(repo.find_by_id(&user.id).await.unwrap().is_some());

        use_case
            .execute(
                &user.id,
                with_credential(sign(&claims("g-7", serde_json::json!({})), KID)),
            )
            .await
            .unwrap();
        assert!(repo.find_by_id(&user.id).await.unwrap().is_none());
        assert!(repo.find_by_google_id("g-7").await.unwrap().is_none());
    }

    #[tokio::test]
    async fn a_stale_google_token_does_not_confirm_the_deletion() {
        let (use_case, repo) = setup().await;
        let user = google_user(&repo, "g-5").await;
        let now = chrono::Utc::now().timestamp();

        for iat in [
            serde_json::json!({ "iat": now - GOOGLE_CONFIRMATION_MAX_AGE_SECS - 60 }),
            serde_json::json!({ "iat": null }),
        ] {
            let err = use_case
                .execute(&user.id, with_credential(sign(&claims("g-5", iat), KID)))
                .await
                .unwrap_err();
            assert!(matches!(
                err,
                DeleteAccountError::Confirmation(ConfirmError::StaleGoogleConfirmation)
            ));
            assert!(repo.find_by_id(&user.id).await.unwrap().is_some());
        }

        use_case
            .execute(
                &user.id,
                with_credential(sign(
                    &claims("g-5", serde_json::json!({ "iat": now - 60 })),
                    KID,
                )),
            )
            .await
            .unwrap();
        assert!(repo.find_by_id(&user.id).await.unwrap().is_none());
    }

    #[tokio::test]
    async fn a_seat_in_a_waiting_party_keeps_the_account() {
        let (use_case, repo) = setup().await;
        let user = google_user(&repo, "g-1").await;
        repo.seat_in_party(&user.id, "waiting").await;
        let err = use_case
            .execute(
                &user.id,
                with_credential(sign(&claims("g-1", serde_json::json!({})), KID)),
            )
            .await
            .unwrap_err();
        assert!(matches!(err, DeleteAccountError::ActiveParty));
        assert!(repo.find_by_id(&user.id).await.unwrap().is_some());
    }

    #[tokio::test]
    async fn a_seat_in_a_playing_party_is_forfeited() {
        use crate::domain::repositories::ForfeitOutcome;

        let (use_case, repo) = setup().await;
        let user = google_user(&repo, "g-2").await;
        repo.seat_in_party(&user.id, "playing").await;
        let deleted = use_case
            .execute(
                &user.id,
                with_credential(sign(&claims("g-2", serde_json::json!({})), KID)),
            )
            .await
            .unwrap();
        // Nobody else sat at that table: the party went with the seat
        assert_eq!(deleted.forfeits.len(), 1);
        assert!(matches!(
            deleted.forfeits[0].outcome,
            ForfeitOutcome::Deleted { .. }
        ));
        assert!(repo.find_by_id(&user.id).await.unwrap().is_none());
    }
}
