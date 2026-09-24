//! Google OAuth: verifies Google ID tokens (the `credential` of Google Identity Services)
//! and derives a username from the profile. Port of
//! `src/infrastructure/services/GoogleOAuthService.js`, which relies on
//! `google-auth-library`; here the RS256 signature is checked against Google's JWKS.

use std::time::{Duration, Instant};

use jsonwebtoken::jwk::JwkSet;
use jsonwebtoken::{decode, decode_header, errors::ErrorKind, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use tokio::sync::RwLock;

/// Google's public signing keys, as a JWK set
pub const GOOGLE_CERTS_URL: &str = "https://www.googleapis.com/oauth2/v3/certs";

/// The two issuers Google uses in ID tokens
const GOOGLE_ISSUERS: [&str; 2] = ["accounts.google.com", "https://accounts.google.com"];

/// How long fetched keys are trusted before a refetch (Google rotates them over days)
const KEYS_TTL: Duration = Duration::from_secs(60 * 60);

/// Minimum delay between two refetches triggered by an unknown `kid`
const UNKNOWN_KID_REFETCH: Duration = Duration::from_secs(60);

/// Profile extracted from a verified ID token
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GoogleProfile {
    pub google_id: String,
    pub email: String,
    pub name: String,
    pub picture: Option<String>,
}

/// Verification failure. The messages are Node's, and all of them contain "Token" or
/// "Google", which the route maps to 401 `GOOGLE_AUTH_FAILED` as Node does.
#[derive(Debug, thiserror::Error)]
pub enum GoogleAuthError {
    #[error("Token expiré. Veuillez réessayer.")]
    Expired,
    #[error("Token Google invalide")]
    InvalidToken,
    #[error("Échec de la vérification Google: {0}")]
    Verification(String),
}

#[derive(Debug, Deserialize)]
struct GoogleIdClaims {
    sub: String,
    email: Option<String>,
    #[serde(default)]
    email_verified: EmailVerified,
    name: Option<String>,
    picture: Option<String>,
}

/// Google sends `email_verified` as a boolean; older tokens carried the string "true".
#[derive(Debug, Default, Deserialize)]
#[serde(untagged)]
enum EmailVerified {
    Bool(bool),
    Str(String),
    #[default]
    Missing,
}

impl EmailVerified {
    fn is_true(&self) -> bool {
        match self {
            EmailVerified::Bool(b) => *b,
            EmailVerified::Str(s) => s == "true",
            EmailVerified::Missing => false,
        }
    }
}

enum KeySource {
    /// Keys given up front (tests)
    Static(JwkSet),
    /// Keys fetched from Google and cached
    Remote {
        url: String,
        http: reqwest::Client,
        cache: RwLock<Option<(JwkSet, Instant)>>,
    },
}

/// Verifies Google ID tokens for one OAuth client id
pub struct GoogleOAuthService {
    client_id: String,
    keys: KeySource,
}

impl GoogleOAuthService {
    /// Service that fetches Google's keys from `GOOGLE_CERTS_URL` and caches them
    pub fn new(client_id: String) -> Self {
        Self {
            client_id,
            keys: KeySource::Remote {
                url: GOOGLE_CERTS_URL.to_string(),
                http: reqwest::Client::builder()
                    .timeout(Duration::from_secs(10))
                    .build()
                    .unwrap_or_default(),
                cache: RwLock::new(None),
            },
        }
    }

    /// Service with a fixed key set (no network)
    pub fn with_keys(client_id: String, keys: JwkSet) -> Self {
        Self {
            client_id,
            keys: KeySource::Static(keys),
        }
    }

    /// `Some` when `GOOGLE_OAUTH_CLIENT_ID` is set and not empty, as Node's bootstrap
    /// (`src/api/bootstrap.js:110-118`)
    pub fn from_env() -> Option<Self> {
        std::env::var("GOOGLE_OAUTH_CLIENT_ID")
            .ok()
            .filter(|id| !id.trim().is_empty())
            .map(Self::new)
    }

    pub fn client_id(&self) -> &str {
        &self.client_id
    }

    /// Verify an ID token: RS256 signature by one of Google's keys, `aud` = the client
    /// id, Google issuer, expiry, and `email_verified`.
    pub async fn verify_id_token(&self, id_token: &str) -> Result<GoogleProfile, GoogleAuthError> {
        let header = decode_header(id_token).map_err(|_| GoogleAuthError::InvalidToken)?;
        if header.alg != Algorithm::RS256 {
            return Err(GoogleAuthError::InvalidToken);
        }
        let kid = header.kid.ok_or(GoogleAuthError::InvalidToken)?;
        let key = self.decoding_key(&kid).await?;

        let mut validation = Validation::new(Algorithm::RS256);
        validation.set_audience(&[&self.client_id]);
        validation.set_issuer(&GOOGLE_ISSUERS);
        validation.set_required_spec_claims(&["exp", "aud", "iss", "sub"]);

        let claims = decode::<GoogleIdClaims>(id_token, &key, &validation)
            .map_err(|e| match e.kind() {
                ErrorKind::ExpiredSignature | ErrorKind::ImmatureSignature => {
                    GoogleAuthError::Expired
                }
                ErrorKind::InvalidAudience => GoogleAuthError::Verification(
                    "Wrong recipient, payload audience != requiredAudience".into(),
                ),
                ErrorKind::InvalidIssuer => GoogleAuthError::Verification("Invalid issuer".into()),
                _ => GoogleAuthError::InvalidToken,
            })?
            .claims;

        if !claims.email_verified.is_true() {
            return Err(GoogleAuthError::Verification(
                "Email not verified by Google".into(),
            ));
        }
        let email = claims
            .email
            .filter(|e| !e.is_empty())
            .ok_or_else(|| GoogleAuthError::Verification("Email missing from token".into()))?;
        let name = claims
            .name
            .filter(|n| !n.is_empty())
            .unwrap_or_else(|| email.split('@').next().unwrap_or_default().to_string());

        Ok(GoogleProfile {
            google_id: claims.sub,
            email,
            name,
            picture: claims.picture,
        })
    }

    async fn decoding_key(&self, kid: &str) -> Result<DecodingKey, GoogleAuthError> {
        let to_key = |set: &JwkSet| -> Option<Result<DecodingKey, GoogleAuthError>> {
            set.find(kid)
                .map(|jwk| DecodingKey::from_jwk(jwk).map_err(|_| GoogleAuthError::InvalidToken))
        };

        match &self.keys {
            KeySource::Static(set) => to_key(set).unwrap_or(Err(GoogleAuthError::InvalidToken)),
            KeySource::Remote { url, http, cache } => {
                {
                    let guard = cache.read().await;
                    if let Some((set, fetched_at)) = guard.as_ref() {
                        let fresh = fetched_at.elapsed() < KEYS_TTL;
                        if fresh {
                            if let Some(key) = to_key(set) {
                                return key;
                            }
                            // Unknown kid: Google may have rotated; refetch, but not in a loop
                            if fetched_at.elapsed() < UNKNOWN_KID_REFETCH {
                                return Err(GoogleAuthError::InvalidToken);
                            }
                        }
                    }
                }

                let set = Self::fetch_keys(http, url).await?;
                let key = to_key(&set);
                *cache.write().await = Some((set, Instant::now()));
                key.unwrap_or(Err(GoogleAuthError::InvalidToken))
            }
        }
    }

    async fn fetch_keys(http: &reqwest::Client, url: &str) -> Result<JwkSet, GoogleAuthError> {
        let fetch_error = |e: reqwest::Error| {
            tracing::error!("Google certs fetch failed: {}", e);
            GoogleAuthError::Verification(format!("cannot fetch Google certs: {}", e))
        };
        http.get(url)
            .send()
            .await
            .and_then(|r| r.error_for_status())
            .map_err(fetch_error)?
            .json::<JwkSet>()
            .await
            .map_err(fetch_error)
    }
}

/// Username from a Google profile: the name, else the email prefix, lowercased, every
/// character outside `[a-z0-9_-]` turned into `_`, runs of `_` collapsed, leading and
/// trailing `_` removed, padded with `_user` under 3 characters, cut at 30.
pub fn generate_username(email: &str, name: &str) -> String {
    let base = if name.is_empty() {
        email.split('@').next().unwrap_or_default()
    } else {
        name
    };

    let mut username = String::with_capacity(base.len());
    for c in base.to_lowercase().chars() {
        let c = if c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-' {
            c
        } else {
            '_'
        };
        if !(c == '_' && username.ends_with('_')) {
            username.push(c);
        }
    }
    let mut username = username.strip_prefix('_').unwrap_or(&username).to_string();
    if username.ends_with('_') {
        username.pop();
    }

    if username.len() < 3 {
        username.push_str("_user");
    }
    // ASCII only by now, so a byte cut is a character cut
    username.truncate(30);
    username
}

/// Candidate `n` of the unique-username search: the base, then `<base>_<n>` with the
/// base cut so that the whole stays within 30 characters.
pub fn username_candidate(base: &str, counter: usize) -> String {
    if counter == 0 {
        return base.to_string();
    }
    let suffix = format!("_{}", counter);
    let max_base = 30usize.saturating_sub(suffix.len());
    let cut: String = base.chars().take(max_base).collect();
    format!("{}{}", cut, suffix)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn username_from_name_is_sanitised() {
        assert_eq!(generate_username("a@b.c", "Jean Dupont"), "jean_dupont");
        assert_eq!(
            generate_username("a@b.c", "  Élise--O'Neil  "),
            "lise--o_neil"
        );
        assert_eq!(generate_username("jo@b.c", ""), "jo_user");
        assert_eq!(generate_username("x@b.c", "__"), "_user");
        let long = generate_username("a@b.c", &"a".repeat(40));
        assert_eq!(long.len(), 30);
    }

    #[test]
    fn username_candidates_stay_within_30() {
        let base = "a".repeat(30);
        assert_eq!(username_candidate(&base, 0), base);
        assert_eq!(
            username_candidate(&base, 1),
            format!("{}_1", "a".repeat(28))
        );
        assert_eq!(username_candidate(&base, 12).len(), 30);
        assert_eq!(username_candidate("bob", 2), "bob_2");
    }
}
