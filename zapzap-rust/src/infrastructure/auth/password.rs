use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};

/// Password hasher service
pub struct PasswordService;

impl PasswordService {
    /// Hash a password using Argon2
    pub fn hash(password: &str) -> Result<String, PasswordError> {
        let salt = SaltString::generate(&mut OsRng);
        let argon2 = Argon2::default();

        argon2
            .hash_password(password.as_bytes(), &salt)
            .map(|hash| hash.to_string())
            .map_err(|e| PasswordError::Hash(e.to_string()))
    }

    /// Verify a password against an Argon2 hash
    pub fn verify_argon2(password: &str, hash: &str) -> Result<bool, PasswordError> {
        let parsed_hash =
            PasswordHash::new(hash).map_err(|e| PasswordError::Verify(e.to_string()))?;

        Ok(Argon2::default()
            .verify_password(password.as_bytes(), &parsed_hash)
            .is_ok())
    }

    /// Verify a password against a bcrypt hash (for migration)
    pub fn verify_bcrypt(password: &str, hash: &str) -> Result<bool, PasswordError> {
        bcrypt::verify(password, hash).map_err(|e| PasswordError::Verify(e.to_string()))
    }

    /// Verify a password against either Argon2 or bcrypt hash
    /// Used during migration period
    pub fn verify(password: &str, hash: &str) -> Result<bool, PasswordError> {
        // Try Argon2 first (new format starts with $argon2)
        if hash.starts_with("$argon2") {
            return Self::verify_argon2(password, hash);
        }

        // Fall back to bcrypt (format starts with $2)
        if hash.starts_with("$2") {
            return Self::verify_bcrypt(password, hash);
        }

        Err(PasswordError::UnknownFormat)
    }

    /// Check if a hash needs to be upgraded from bcrypt to Argon2
    pub fn needs_rehash(hash: &str) -> bool {
        hash.starts_with("$2")
    }
}

/// Password error types
#[derive(Debug, thiserror::Error)]
pub enum PasswordError {
    #[error("Failed to hash password: {0}")]
    Hash(String),
    #[error("Failed to verify password: {0}")]
    Verify(String),
    #[error("Unknown hash format")]
    UnknownFormat,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_and_verify() {
        let password = "test_password_123";
        let hash = PasswordService::hash(password).unwrap();

        assert!(hash.starts_with("$argon2"));
        assert!(PasswordService::verify(password, &hash).unwrap());
        assert!(!PasswordService::verify("wrong_password", &hash).unwrap());
    }

    #[test]
    fn test_bcrypt_compatibility() {
        // Sample bcrypt hash for "demo123"
        let bcrypt_hash = bcrypt::hash("demo123", bcrypt::DEFAULT_COST).unwrap();

        assert!(PasswordService::verify("demo123", &bcrypt_hash).unwrap());
        assert!(!PasswordService::verify("wrong", &bcrypt_hash).unwrap());
        assert!(PasswordService::needs_rehash(&bcrypt_hash));
    }
}
