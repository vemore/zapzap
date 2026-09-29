//! A signed-in player proves it is them before an account change a stolen token must not
//! make on its own: deleting the account (`DeleteAccount`), changing its password
//! (`ChangePassword`). The proof is the account's password, or a fresh Google ID token of
//! the account's Google identity; an account that has both takes either.

use crate::domain::entities::User;
use crate::infrastructure::auth::PasswordService;
use crate::infrastructure::services::{GoogleAuthError, GoogleOAuthService};

/// How old a Google ID token may be to confirm a change: Google's tokens live an hour, and
/// one left over from sign-in is not a fresh confirmation
pub const GOOGLE_CONFIRMATION_MAX_AGE_SECS: i64 = 10 * 60;

/// Why the proof was refused
#[derive(Debug, thiserror::Error)]
pub enum ConfirmError {
    /// No proof the account can check: no password for an account with one, no Google
    /// token for a Google account (a bot has neither)
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
}

/// Checks `password` against the account's, or else `credential`, a Google ID token, against
/// its Google identity; an empty value counts as none. `google` is `None` when
/// `GOOGLE_OAUTH_CLIENT_ID` is not configured.
pub async fn confirm_identity(
    user: &User,
    password: Option<&str>,
    credential: Option<&str>,
    google: Option<&GoogleOAuthService>,
) -> Result<(), ConfirmError> {
    let password = password.filter(|p| !p.is_empty());
    let credential = credential.filter(|c| !c.is_empty());

    if let (Some(hash), Some(password)) = (&user.password_hash, password) {
        // An unreadable stored hash confirms nothing, as at login
        return match PasswordService::verify(password, hash) {
            Ok(true) => Ok(()),
            _ => Err(ConfirmError::InvalidPassword),
        };
    }
    let (Some(google_id), Some(credential)) = (&user.google_id, credential) else {
        return Err(ConfirmError::MissingConfirmation);
    };
    let google = google.ok_or(ConfirmError::GoogleNotConfigured)?;
    let profile = google.verify_id_token(credential).await?;
    if &profile.google_id != google_id {
        return Err(ConfirmError::OtherGoogleAccount);
    }
    let now = chrono::Utc::now().timestamp();
    if profile
        .issued_at
        .is_none_or(|iat| now - iat > GOOGLE_CONFIRMATION_MAX_AGE_SECS)
    {
        return Err(ConfirmError::StaleGoogleConfirmation);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::infrastructure::services::google_oauth_test_keys::{
        claims, key_set, sign, CLIENT_ID, KID,
    };

    fn google() -> GoogleOAuthService {
        GoogleOAuthService::with_keys(CLIENT_ID.into(), key_set())
    }

    fn fresh(google_id: &str) -> String {
        sign(&claims(google_id, serde_json::json!({})), KID)
    }

    /// A Google account that has set a password since
    fn google_user_with_password() -> User {
        let mut user = User::new_google(
            "u1".into(),
            "Ada".into(),
            "g-1".into(),
            "ada@example.com".into(),
        );
        user.password_hash = Some(PasswordService::hash("secret").unwrap());
        user
    }

    #[tokio::test]
    async fn an_account_with_both_takes_either_proof() {
        let user = google_user_with_password();
        let google = google();

        confirm_identity(&user, Some("secret"), None, Some(&google))
            .await
            .unwrap();
        confirm_identity(&user, None, Some(&fresh("g-1")), Some(&google))
            .await
            .unwrap();
        // A password given is the one checked, even beside a good Google token
        let err = confirm_identity(&user, Some("wrong"), Some(&fresh("g-1")), Some(&google))
            .await
            .unwrap_err();
        assert!(matches!(err, ConfirmError::InvalidPassword));
        let err = confirm_identity(&user, None, Some(&fresh("g-2")), Some(&google))
            .await
            .unwrap_err();
        assert!(matches!(err, ConfirmError::OtherGoogleAccount));
    }

    #[tokio::test]
    async fn a_password_account_is_not_confirmed_by_google() {
        let user = User::new_human(
            "u2".into(),
            "Bob".into(),
            PasswordService::hash("secret").unwrap(),
        );
        let err = confirm_identity(&user, Some(""), Some(&fresh("g-1")), Some(&google()))
            .await
            .unwrap_err();
        assert!(matches!(err, ConfirmError::MissingConfirmation));
    }
}
