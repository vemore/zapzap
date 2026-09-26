//! A player deletes their own account, confirmed by their password or, for an account
//! created with Google, by a fresh Google ID token of the same Google account. Their
//! finished games stay in the other players' history under an anonymous user
//! (`UserRepository::delete_account`).

use std::sync::Arc;

use crate::domain::repositories::{AccountDeletion, UserRepository};
use crate::infrastructure::auth::PasswordService;
use crate::infrastructure::services::{GoogleAuthError, GoogleOAuthService};

/// How old a Google ID token may be to confirm a deletion: Google's tokens live an hour,
/// and one left over from sign-in is not a fresh confirmation
pub const GOOGLE_CONFIRMATION_MAX_AGE_SECS: i64 = 10 * 60;

/// What confirms the deletion
pub struct DeleteAccountInput {
    pub password: Option<String>,
    /// A Google ID token, for an account without a password
    pub credential: Option<String>,
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

    /// Deletes the user; returns the anonymous user their finished games went to, if any
    pub async fn execute(
        &self,
        user_id: &str,
        input: DeleteAccountInput,
    ) -> Result<Option<String>, DeleteAccountError> {
        let user = self
            .user_repo
            .find_by_id(user_id)
            .await?
            .ok_or(DeleteAccountError::NotFound)?;
        let password = input.password.filter(|p| !p.is_empty());
        let credential = input.credential.filter(|c| !c.is_empty());

        match (&user.password_hash, &user.google_id) {
            (Some(hash), _) => {
                let password = password.ok_or(DeleteAccountError::MissingConfirmation)?;
                // An unreadable stored hash confirms nothing, as at login
                if !PasswordService::verify(&password, hash).unwrap_or(false) {
                    return Err(DeleteAccountError::InvalidPassword);
                }
            }
            (None, Some(google_id)) => {
                let credential = credential.ok_or(DeleteAccountError::MissingConfirmation)?;
                let google = self
                    .google
                    .as_ref()
                    .ok_or(DeleteAccountError::GoogleNotConfigured)?;
                let profile = google.verify_id_token(&credential).await?;
                if &profile.google_id != google_id {
                    return Err(DeleteAccountError::OtherGoogleAccount);
                }
                let now = chrono::Utc::now().timestamp();
                if profile
                    .issued_at
                    .is_none_or(|iat| now - iat > GOOGLE_CONFIRMATION_MAX_AGE_SECS)
                {
                    return Err(DeleteAccountError::StaleGoogleConfirmation);
                }
            }
            // Neither a password nor Google: nothing can confirm it (a bot, never a player)
            (None, None) => return Err(DeleteAccountError::MissingConfirmation),
        }

        match self.user_repo.delete_account(user_id).await? {
            AccountDeletion::Deleted { anonymised_as } => {
                tracing::info!("Account deleted: {} ({})", user.username, user.id);
                Ok(anonymised_as)
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
    #[error("Confirm with your password, or with Google for a Google account")]
    MissingConfirmation,
    #[error("Invalid password")]
    InvalidPassword,
    #[error("Google OAuth non configuré sur ce serveur")]
    GoogleNotConfigured,
    #[error(transparent)]
    Google(#[from] GoogleAuthError),
    #[error("This Google account is not the one of this user")]
    OtherGoogleAccount,
    #[error("Google confirmation too old: sign in with Google again")]
    StaleGoogleConfirmation,
    #[error("Leave or finish your waiting or playing parties first")]
    ActiveParty,
    #[error("The only admin cannot delete their account")]
    LastAdmin,
    #[error("Repository error: {0}")]
    Repository(#[from] crate::domain::repositories::RepositoryError),
}

#[cfg(test)]
mod tests {
    use super::*;
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
        assert!(matches!(err, DeleteAccountError::OtherGoogleAccount));
        let err = use_case
            .execute(&user.id, with_credential("not-a-token".into()))
            .await
            .unwrap_err();
        assert!(matches!(err, DeleteAccountError::Google(_)));
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
        assert!(matches!(err, DeleteAccountError::MissingConfirmation));
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
            assert!(matches!(err, DeleteAccountError::StaleGoogleConfirmation));
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
    async fn a_seat_in_an_active_party_keeps_the_account() {
        for status in ["waiting", "playing"] {
            let (use_case, repo) = setup().await;
            let user = google_user(&repo, "g-1").await;
            repo.seat_in_party(&user.id, status).await;
            let err = use_case
                .execute(
                    &user.id,
                    with_credential(sign(&claims("g-1", serde_json::json!({})), KID)),
                )
                .await
                .unwrap_err();
            assert!(matches!(err, DeleteAccountError::ActiveParty), "{status}");
            assert!(repo.find_by_id(&user.id).await.unwrap().is_some());
        }
    }
}
