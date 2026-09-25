//! Google OAuth: verifies Google ID tokens (the `credential` of Google Identity Services)
//! and derives a username from the profile. The Node
//! backend relied on `google-auth-library`; here the RS256 signature is checked against
//! Google's JWKS.

use std::sync::Arc;
use std::time::{Duration, Instant};

use futures::future::BoxFuture;
use jsonwebtoken::jwk::{Jwk, JwkSet};
use jsonwebtoken::{decode, decode_header, errors::ErrorKind, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use tokio::sync::Mutex;

/// Google's public signing keys, as a JWK set
pub const GOOGLE_CERTS_URL: &str = "https://www.googleapis.com/oauth2/v3/certs";

/// The two issuers Google uses in ID tokens
const GOOGLE_ISSUERS: [&str; 2] = ["accounts.google.com", "https://accounts.google.com"];

/// How long fetched keys are trusted before a refetch (Google rotates them over days)
const KEYS_TTL: Duration = Duration::from_secs(60 * 60);

/// Minimum delay between two fetch attempts, successful or not
const MIN_REFETCH_INTERVAL: Duration = Duration::from_secs(60);

/// Fetches the key set; the error text is logged, never sent to a client
pub type KeyFetcher = Arc<dyn Fn() -> BoxFuture<'static, Result<JwkSet, String>> + Send + Sync>;

/// Profile extracted from a verified ID token
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GoogleProfile {
    pub google_id: String,
    pub email: String,
    pub name: String,
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

#[derive(Default)]
struct KeyCache {
    keys: Option<JwkSet>,
    fetched_at: Option<Instant>,
    last_attempt: Option<Instant>,
}

enum KeySource {
    /// Keys given up front (tests)
    Static(JwkSet),
    /// Keys fetched and cached. The mutex is held across a fetch, so concurrent requests
    /// wait for one fetch instead of each starting their own.
    Remote {
        fetch: KeyFetcher,
        cache: Mutex<KeyCache>,
        ttl: Duration,
        min_refetch: Duration,
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
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .unwrap_or_default();
        let fetch: KeyFetcher = Arc::new(move || {
            let http = http.clone();
            Box::pin(async move {
                let body = http
                    .get(GOOGLE_CERTS_URL)
                    .send()
                    .await
                    .and_then(|r| r.error_for_status())
                    .map_err(|e| e.to_string())?
                    .json::<serde_json::Value>()
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(parse_jwks(&body))
            })
        });
        Self::with_fetcher(client_id, fetch, KEYS_TTL, MIN_REFETCH_INTERVAL)
    }

    /// Service with a custom key fetcher and cache timings (tests)
    pub fn with_fetcher(
        client_id: String,
        fetch: KeyFetcher,
        ttl: Duration,
        min_refetch: Duration,
    ) -> Self {
        Self {
            client_id,
            keys: KeySource::Remote {
                fetch,
                cache: Mutex::new(KeyCache::default()),
                ttl,
                min_refetch,
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

    /// `Some` when `GOOGLE_OAUTH_CLIENT_ID` is set and not blank, as the Node
    /// backend did; the value is trimmed
    pub fn from_env() -> Option<Self> {
        std::env::var("GOOGLE_OAUTH_CLIENT_ID")
            .ok()
            .map(|id| id.trim().to_string())
            .filter(|id| !id.is_empty())
            .map(Self::new)
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
                ErrorKind::ExpiredSignature => GoogleAuthError::Expired,
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
        })
    }

    async fn decoding_key(&self, kid: &str) -> Result<DecodingKey, GoogleAuthError> {
        let to_key = |set: &JwkSet| -> Option<Result<DecodingKey, GoogleAuthError>> {
            set.find(kid)
                .map(|jwk| DecodingKey::from_jwk(jwk).map_err(|_| GoogleAuthError::InvalidToken))
        };

        let (fetch, cache, ttl, min_refetch) = match &self.keys {
            KeySource::Static(set) => {
                return to_key(set).unwrap_or(Err(GoogleAuthError::InvalidToken))
            }
            KeySource::Remote {
                fetch,
                cache,
                ttl,
                min_refetch,
            } => (fetch, cache, *ttl, *min_refetch),
        };

        let mut cache = cache.lock().await;
        let fresh = cache.fetched_at.is_some_and(|t| t.elapsed() < ttl);
        if fresh {
            if let Some(key) = cache.keys.as_ref().and_then(to_key) {
                return key;
            }
        }

        // Stale keys, or an unknown kid (Google may have rotated): refetch, at most once
        // per `min_refetch` whatever the outcome, so failures cannot turn into a loop
        let may_fetch = cache
            .last_attempt
            .is_none_or(|t| t.elapsed() >= min_refetch);
        if may_fetch {
            cache.last_attempt = Some(Instant::now());
            match fetch().await {
                Ok(set) => {
                    cache.keys = Some(set);
                    cache.fetched_at = Some(Instant::now());
                }
                Err(e) => tracing::error!("Google certs fetch failed: {}", e),
            }
        }

        match cache.keys.as_ref() {
            // Possibly stale when the refetch failed: better than refusing every login
            Some(set) => to_key(set).unwrap_or(Err(GoogleAuthError::InvalidToken)),
            None => Err(GoogleAuthError::Verification(
                "certificats Google indisponibles".into(),
            )),
        }
    }
}

/// Key set from a JWKS document, keeping only the keys that parse: a key of an unknown
/// `kty` or `alg` is skipped instead of failing the whole set.
pub fn parse_jwks(body: &serde_json::Value) -> JwkSet {
    let keys = body
        .get("keys")
        .and_then(|k| k.as_array())
        .map(|keys| {
            keys.iter()
                .filter_map(|k| serde_json::from_value::<Jwk>(k.clone()).ok())
                .collect()
        })
        .unwrap_or_default();
    JwkSet { keys }
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

/// Test-only RSA key (`tests/fixtures/google_oauth_test_rsa.pem`) and helpers to sign
/// Google-like ID tokens with it
#[cfg(test)]
pub(crate) mod test_keys {
    use jsonwebtoken::jwk::JwkSet;
    use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};

    pub const PEM: &str = include_str!("../../../tests/fixtures/google_oauth_test_rsa.pem");
    pub const N: &str = "ru3qPMAYvaU0HR8RHvqgNiQlq-XRKFtj5IkfTZaIfdiU5r_RyjSXi4Jx826eUZt38mjTFKgVd_apxmwjPxY-Odal5arEXdNuxxkHUI6_lJiZOv2qJrTRiylyipOobKWmQUrGamIT6F4tSx4wggUL7jST-EVUrI4jmdZqbx9BtYZoOUXBVK0QxEjNG4Zj7InwYEup64F7gC4nKyiFrfOQI3rsL85P7fFPttxFaZuyurMCSditw_VkAul88pIRmpf6ZvKjP6aMrTdxAuy4iaUbWyUOmPKRgG9fAWYwHptvHjyH8rjFJH2Q6SFE38Mup51QeVakOVGILMg8ZzFsl4k0Sw";
    pub const KID: &str = "test-kid";
    pub const CLIENT_ID: &str = "test-client.apps.googleusercontent.com";

    pub fn key_set() -> JwkSet {
        serde_json::from_value(serde_json::json!({
            "keys": [{"kty": "RSA", "alg": "RS256", "use": "sig", "kid": KID, "n": N, "e": "AQAB"}]
        }))
        .unwrap()
    }

    pub fn sign(claims: &serde_json::Value, kid: &str) -> String {
        let mut header = Header::new(Algorithm::RS256);
        header.kid = Some(kid.to_string());
        encode(
            &header,
            claims,
            &EncodingKey::from_rsa_pem(PEM.as_bytes()).unwrap(),
        )
        .unwrap()
    }

    /// Valid claims for `sub`, with `overrides` applied
    pub fn claims(sub: &str, overrides: serde_json::Value) -> serde_json::Value {
        let now = chrono::Utc::now().timestamp();
        let mut c = serde_json::json!({
            "iss": "https://accounts.google.com",
            "aud": CLIENT_ID,
            "sub": sub,
            "email": "jean.dupont@example.com",
            "email_verified": true,
            "name": "Jean Dupont",
            "iat": now,
            "exp": now + 3600,
        });
        for (k, v) in overrides.as_object().unwrap() {
            c[k] = v.clone();
        }
        c
    }
}

#[cfg(test)]
mod tests {
    use super::test_keys::{claims, key_set, sign, CLIENT_ID, KID};
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

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

    /// A fetcher that counts its calls; `answers[i]` is the outcome of call `i` (the last
    /// one repeats), each after a short delay so concurrent callers overlap
    fn counting_fetcher(answers: Vec<Result<JwkSet, String>>) -> (KeyFetcher, Arc<AtomicUsize>) {
        let calls = Arc::new(AtomicUsize::new(0));
        let counter = calls.clone();
        let answers = Arc::new(answers);
        let fetch: KeyFetcher = Arc::new(move || {
            let n = counter.fetch_add(1, Ordering::SeqCst);
            let answer = answers[n.min(answers.len() - 1)].clone();
            Box::pin(async move {
                tokio::time::sleep(Duration::from_millis(20)).await;
                answer
            })
        });
        (fetch, calls)
    }

    #[tokio::test]
    async fn concurrent_unknown_kid_requests_fetch_once() {
        let (fetch, calls) = counting_fetcher(vec![Ok(key_set())]);
        let service = Arc::new(GoogleOAuthService::with_fetcher(
            CLIENT_ID.into(),
            fetch,
            KEYS_TTL,
            MIN_REFETCH_INTERVAL,
        ));
        let token = sign(&claims("g", serde_json::json!({})), "unknown-kid");

        let tasks: Vec<_> = (0..10)
            .map(|_| {
                let service = service.clone();
                let token = token.clone();
                tokio::spawn(async move { service.verify_id_token(&token).await })
            })
            .collect();
        for task in tasks {
            assert!(matches!(
                task.await.unwrap(),
                Err(GoogleAuthError::InvalidToken)
            ));
        }
        assert_eq!(calls.load(Ordering::SeqCst), 1);

        // The known kid is served from the cache
        let good = sign(&claims("g", serde_json::json!({})), KID);
        assert!(service.verify_id_token(&good).await.is_ok());
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn failing_refetch_falls_back_to_stale_keys() {
        // TTL 0: every verification finds the keys stale and tries a refetch
        let (fetch, calls) = counting_fetcher(vec![
            Ok(key_set()),
            Err("connection refused (secret detail)".into()),
        ]);
        let service = GoogleOAuthService::with_fetcher(
            CLIENT_ID.into(),
            fetch,
            Duration::ZERO,
            Duration::ZERO,
        );
        let token = sign(&claims("g", serde_json::json!({})), KID);

        assert!(service.verify_id_token(&token).await.is_ok());
        assert!(service.verify_id_token(&token).await.is_ok());
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn failing_fetches_are_rate_limited_and_not_leaked() {
        let (fetch, calls) = counting_fetcher(vec![Err("dns error: secret-host".into())]);
        let service = GoogleOAuthService::with_fetcher(
            CLIENT_ID.into(),
            fetch,
            KEYS_TTL,
            MIN_REFETCH_INTERVAL,
        );
        let token = sign(&claims("g", serde_json::json!({})), KID);
        for _ in 0..3 {
            let err = service.verify_id_token(&token).await.unwrap_err();
            assert!(!err.to_string().contains("secret"), "{err}");
            assert!(err.to_string().contains("Google"), "{err}");
        }
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn jwks_parsing_skips_keys_it_cannot_read() {
        let body = serde_json::json!({"keys": [
            {"kty": "XYZ", "kid": "weird"},
            {"kty": "RSA", "alg": "RS999", "kid": "future", "n": "AQAB", "e": "AQAB"},
            {"kty": "RSA", "alg": "RS256", "use": "sig", "kid": KID, "n": test_keys::N, "e": "AQAB"}
        ]});
        let set = parse_jwks(&body);
        assert_eq!(set.keys.len(), 1);
        assert!(set.find(KID).is_some());
        assert!(parse_jwks(&serde_json::json!({})).keys.is_empty());
    }
}
