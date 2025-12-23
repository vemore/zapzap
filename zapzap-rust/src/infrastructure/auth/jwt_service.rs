use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};

/// JWT claims
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Claims {
    pub user_id: String,
    pub username: String,
    #[serde(default)]
    pub is_admin: bool,
    pub exp: usize,
    pub iat: usize,
}

/// JWT service for token management
pub struct JwtService {
    encoding_key: EncodingKey,
    decoding_key: DecodingKey,
    expires_in_seconds: usize,
}

impl JwtService {
    pub fn new(secret: String) -> Self {
        Self {
            encoding_key: EncodingKey::from_secret(secret.as_bytes()),
            decoding_key: DecodingKey::from_secret(secret.as_bytes()),
            expires_in_seconds: 7 * 24 * 60 * 60, // 7 days
        }
    }

    /// Sign a new JWT token
    pub fn sign(&self, user_id: &str, username: &str, is_admin: bool) -> Result<String, JwtError> {
        let now = chrono::Utc::now().timestamp() as usize;
        let claims = Claims {
            user_id: user_id.to_string(),
            username: username.to_string(),
            is_admin,
            exp: now + self.expires_in_seconds,
            iat: now,
        };

        encode(&Header::default(), &claims, &self.encoding_key).map_err(|e| JwtError::Sign(e.to_string()))
    }

    /// Verify and decode a JWT token
    pub fn verify(&self, token: &str) -> Result<Claims, JwtError> {
        let validation = Validation::default();
        decode::<Claims>(token, &self.decoding_key, &validation)
            .map(|data| data.claims)
            .map_err(|e| match e.kind() {
                jsonwebtoken::errors::ErrorKind::ExpiredSignature => JwtError::Expired,
                jsonwebtoken::errors::ErrorKind::InvalidToken => JwtError::Invalid,
                _ => JwtError::Verify(e.to_string()),
            })
    }

    /// Decode without verification (for debugging)
    pub fn decode_without_verify(&self, token: &str) -> Result<Claims, JwtError> {
        let mut validation = Validation::default();
        validation.insecure_disable_signature_validation();
        validation.validate_exp = false;

        decode::<Claims>(token, &self.decoding_key, &validation)
            .map(|data| data.claims)
            .map_err(|e| JwtError::Verify(e.to_string()))
    }
}

/// JWT error types
#[derive(Debug, thiserror::Error)]
pub enum JwtError {
    #[error("Failed to sign token: {0}")]
    Sign(String),
    #[error("Token has expired")]
    Expired,
    #[error("Invalid token")]
    Invalid,
    #[error("Failed to verify token: {0}")]
    Verify(String),
}
