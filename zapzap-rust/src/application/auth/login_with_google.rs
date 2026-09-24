//! Login or sign up with a Google ID token. Port of `src/use-cases/auth/LoginWithGoogle.js`.

use std::sync::Arc;

use uuid::Uuid;

use crate::domain::entities::User;
use crate::domain::repositories::UserRepository;
use crate::infrastructure::auth::JwtService;
use crate::infrastructure::services::{
    generate_username, username_candidate, GoogleAuthError, GoogleOAuthService, GoogleProfile,
};

/// Output of a Google login
pub struct LoginWithGoogleOutput {
    pub user: User,
    pub token: String,
    pub is_new_user: bool,
}

/// Login with Google use case
pub struct LoginWithGoogle {
    user_repo: Arc<dyn UserRepository>,
    jwt_service: Arc<JwtService>,
    google: Option<Arc<GoogleOAuthService>>,
}

impl LoginWithGoogle {
    /// `google` is `None` when `GOOGLE_OAUTH_CLIENT_ID` is not configured
    pub fn new(
        user_repo: Arc<dyn UserRepository>,
        jwt_service: Arc<JwtService>,
        google: Option<Arc<GoogleOAuthService>>,
    ) -> Self {
        Self {
            user_repo,
            jwt_service,
            google,
        }
    }

    pub async fn execute(
        &self,
        credential: &str,
    ) -> Result<LoginWithGoogleOutput, LoginWithGoogleError> {
        let google = self
            .google
            .as_ref()
            .ok_or(LoginWithGoogleError::NotConfigured)?;
        if credential.is_empty() {
            return Err(LoginWithGoogleError::MissingCredential);
        }

        let profile = google.verify_id_token(credential).await?;

        let (user, is_new_user) = match self.user_repo.find_by_google_id(&profile.google_id).await?
        {
            Some(user) => {
                self.user_repo.update_last_login(&user.id).await?;
                (user, false)
            }
            None => self.create_user(&profile).await?,
        };

        let token = self
            .jwt_service
            .sign(&user.id, &user.username, user.is_admin)
            .map_err(|e| LoginWithGoogleError::Internal(e.to_string()))?;

        Ok(LoginWithGoogleOutput {
            user,
            token,
            is_new_user,
        })
    }

    /// First login: create the user under a free username. Two first logins of the same
    /// account can race; the loser's save hits the username UNIQUE index, and it then
    /// answers the winner's user. A username taken by someone else meanwhile is picked
    /// again, once.
    async fn create_user(
        &self,
        profile: &GoogleProfile,
    ) -> Result<(User, bool), LoginWithGoogleError> {
        let base = generate_username(&profile.email, &profile.name);
        let mut attempts_left = 2;
        loop {
            attempts_left -= 1;
            let mut username = None;
            // Node gives up after counter 1000 (GoogleOAuthService.generateUniqueUsername)
            for counter in 0..1000 {
                let candidate = username_candidate(&base, counter);
                if !self.user_repo.exists_by_username(&candidate).await? {
                    username = Some(candidate);
                    break;
                }
            }
            let username = username.ok_or(LoginWithGoogleError::NoUniqueUsername)?;

            let user = User::new_google(
                Uuid::new_v4().to_string(),
                username,
                profile.google_id.clone(),
                profile.email.clone(),
            );
            match self.user_repo.save(&user).await {
                Ok(()) => {
                    tracing::info!(
                        "New Google user registered: {} ({})",
                        user.username,
                        user.id
                    );
                    return Ok((user, true));
                }
                Err(e) if e.is_unique_violation() => {
                    if let Some(winner) =
                        self.user_repo.find_by_google_id(&profile.google_id).await?
                    {
                        return Ok((winner, false));
                    }
                    if attempts_left == 0 {
                        return Err(e.into());
                    }
                }
                Err(e) => return Err(e.into()),
            }
        }
    }
}

/// Errors. `is_auth_failure` tells which ones Node answers with 401 `GOOGLE_AUTH_FAILED`
/// (its message contains "Token" or "Google", `src/api/routes/authRoutes.js:158`).
#[derive(Debug, thiserror::Error)]
pub enum LoginWithGoogleError {
    #[error("Token Google requis")]
    MissingCredential,
    #[error("Google OAuth non configuré sur ce serveur")]
    NotConfigured,
    #[error(transparent)]
    Google(#[from] GoogleAuthError),
    #[error("Unable to generate unique username")]
    NoUniqueUsername,
    #[error("Internal error: {0}")]
    Internal(String),
    #[error("Repository error: {0}")]
    Repository(#[from] crate::domain::repositories::RepositoryError),
}

impl LoginWithGoogleError {
    pub fn is_auth_failure(&self) -> bool {
        matches!(
            self,
            LoginWithGoogleError::MissingCredential
                | LoginWithGoogleError::NotConfigured
                | LoginWithGoogleError::Google(_)
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::infrastructure::database::repositories::racing_user_repo::RacingUserRepo;
    use crate::infrastructure::services::google_oauth_test_keys::{
        claims, key_set, sign, CLIENT_ID, KID, N,
    };
    use jsonwebtoken::{encode, EncodingKey, Header};
    use std::sync::atomic::Ordering;

    async fn setup() -> (LoginWithGoogle, Arc<RacingUserRepo>, Arc<JwtService>) {
        let repo = Arc::new(RacingUserRepo::new().await);
        let jwt = Arc::new(JwtService::new("unit-test-secret".into()));
        let google = Arc::new(GoogleOAuthService::with_keys(CLIENT_ID.into(), key_set()));
        (
            LoginWithGoogle::new(repo.clone(), jwt.clone(), Some(google)),
            repo,
            jwt,
        )
    }

    #[tokio::test]
    async fn verified_token_creates_then_finds_the_user() {
        let (uc, repo, jwt) = setup().await;
        let token = sign(&claims("g-1", serde_json::json!({})), KID);

        let first = uc.execute(&token).await.unwrap();
        assert!(first.is_new_user);
        assert_eq!(first.user.username, "jean_dupont");
        assert_eq!(first.user.google_id.as_deref(), Some("g-1"));
        assert_eq!(first.user.email.as_deref(), Some("jean.dupont@example.com"));
        assert!(first.user.password_hash.is_none());
        assert_eq!(jwt.verify(&first.token).unwrap().user_id, first.user.id);
        assert!(repo.find_by_google_id("g-1").await.unwrap().is_some());

        let second = uc.execute(&token).await.unwrap();
        assert!(!second.is_new_user);
        assert_eq!(second.user.id, first.user.id);
        let stored = repo.find_by_id(&first.user.id).await.unwrap().unwrap();
        assert!(stored.last_login_at.is_some());
    }

    #[tokio::test]
    async fn username_taken_gets_a_numbered_suffix() {
        let (uc, repo, _) = setup().await;
        repo.save(&User::new_human(
            "u-1".into(),
            "jean_dupont".into(),
            "hash".into(),
        ))
        .await
        .unwrap();

        let token = sign(&claims("g-2", serde_json::json!({})), KID);
        let out = uc.execute(&token).await.unwrap();
        assert_eq!(out.user.username, "jean_dupont_1");

        // Issuer without scheme is accepted too, and a missing name falls back to the email
        let token = sign(
            &claims(
                "g-3",
                serde_json::json!({"iss": "accounts.google.com", "name": null, "email": "zo@example.com"}),
            ),
            KID,
        );
        let out = uc.execute(&token).await.unwrap();
        assert_eq!(out.user.username, "zo_user");
    }

    #[tokio::test]
    async fn invalid_tokens_are_refused() {
        let (uc, repo, _) = setup().await;
        let cases = [
            (
                "wrong audience",
                sign(&claims("g", serde_json::json!({"aud": "other"})), KID),
            ),
            (
                "wrong issuer",
                sign(
                    &claims("g", serde_json::json!({"iss": "https://evil.example"})),
                    KID,
                ),
            ),
            (
                "expired",
                sign(
                    &claims("g", serde_json::json!({"exp": 1000, "iat": 900})),
                    KID,
                ),
            ),
            (
                "email not verified",
                sign(
                    &claims("g", serde_json::json!({"email_verified": false})),
                    KID,
                ),
            ),
            (
                "unknown kid",
                sign(&claims("g", serde_json::json!({})), "other-kid"),
            ),
            ("not a jwt", "forged.token.value".to_string()),
            ("HS256 keyed with the public key", {
                let mut header = Header::new(jsonwebtoken::Algorithm::HS256);
                header.kid = Some(KID.to_string());
                encode(
                    &header,
                    &claims("g", serde_json::json!({})),
                    &EncodingKey::from_secret(N.as_bytes()),
                )
                .unwrap()
            }),
            ("alg none", {
                let signed = sign(&claims("g", serde_json::json!({})), KID);
                let payload = signed.split('.').nth(1).unwrap().to_string();
                // {"alg":"none","typ":"JWT","kid":"test-kid"}
                format!("eyJhbGciOiJub25lIiwidHlwIjoiSldUIiwia2lkIjoidGVzdC1raWQifQ.{payload}.")
            }),
        ];
        for (what, token) in cases {
            let err = uc
                .execute(&token)
                .await
                .err()
                .unwrap_or_else(|| panic!("{what} accepted"));
            assert!(err.is_auth_failure(), "{what}: {err}");
            let msg = err.to_string();
            assert!(
                msg.contains("Token") || msg.contains("Google"),
                "{what}: {msg}"
            );
        }

        // A payload re-signed by nobody: another token's signature on it fails the check
        let honest = sign(&claims("g", serde_json::json!({})), KID);
        let other = sign(&claims("attacker", serde_json::json!({})), KID);
        let honest: Vec<&str> = honest.split('.').collect();
        let other: Vec<&str> = other.split('.').collect();
        let forged = format!("{}.{}.{}", other[0], other[1], honest[2]);
        let err = uc.execute(&forged).await.err().unwrap();
        assert!(matches!(
            err,
            LoginWithGoogleError::Google(GoogleAuthError::InvalidToken)
        ));

        assert!(repo.find_by_google_id("g").await.unwrap().is_none());
        assert!(repo.find_by_google_id("attacker").await.unwrap().is_none());
    }

    #[tokio::test]
    async fn not_configured_is_an_auth_failure() {
        let (_, repo, jwt) = setup().await;
        let uc = LoginWithGoogle::new(repo, jwt, None);
        let err = uc.execute("anything").await.err().unwrap();
        assert!(matches!(err, LoginWithGoogleError::NotConfigured));
        assert_eq!(err.to_string(), "Google OAuth non configuré sur ce serveur");
    }

    #[tokio::test]
    async fn racing_first_logins_answer_the_same_user() {
        let (uc, repo, _) = setup().await;
        let token = sign(&claims("g-race", serde_json::json!({})), KID);
        let first = uc.execute(&token).await.unwrap();

        // The second request looked the account and the username up before the first saved
        repo.stale_google_lookups.store(1, Ordering::SeqCst);
        repo.stale_username_checks.store(1, Ordering::SeqCst);
        let second = uc.execute(&token).await.unwrap();
        assert_eq!(second.user.id, first.user.id);
        assert!(!second.is_new_user);
    }

    #[tokio::test]
    async fn username_taken_meanwhile_is_picked_again() {
        let (uc, repo, _) = setup().await;
        repo.save(&User::new_human(
            "u-1".into(),
            "jean_dupont".into(),
            "hash".into(),
        ))
        .await
        .unwrap();

        // The username check ran before someone else took "jean_dupont"
        repo.stale_username_checks.store(1, Ordering::SeqCst);
        let token = sign(&claims("g-new", serde_json::json!({})), KID);
        let out = uc.execute(&token).await.unwrap();
        assert!(out.is_new_user);
        assert_eq!(out.user.username, "jean_dupont_1");
    }
}
