use argon2::{
    password_hash::{PasswordHash, PasswordVerifier},
    Argon2,
};

/// bcrypt cost of every hash written: the Node backend's (`bcrypt.hash(pw, 10)`)
pub const BCRYPT_COST: u32 = 10;

/// Password hasher service
///
/// Passwords are hashed with bcrypt while the Node backend is the rollback: Node verifies
/// with `bcryptjs.compare` only, so every hash Rust writes stays bcrypt. Argon2 hashes, which
/// earlier Rust builds wrote, still verify.
pub struct PasswordService;

impl PasswordService {
    /// Hash a password with bcrypt at Node's cost (`$2b$10$...`)
    pub fn hash(password: &str) -> Result<String, PasswordError> {
        bcrypt::hash(password, BCRYPT_COST).map_err(|e| PasswordError::Hash(e.to_string()))
    }

    /// Verify a password against an Argon2 hash
    pub fn verify_argon2(password: &str, hash: &str) -> Result<bool, PasswordError> {
        let parsed_hash =
            PasswordHash::new(hash).map_err(|e| PasswordError::Verify(e.to_string()))?;

        Ok(Argon2::default()
            .verify_password(password.as_bytes(), &parsed_hash)
            .is_ok())
    }

    /// Verify a password against a bcrypt hash
    pub fn verify_bcrypt(password: &str, hash: &str) -> Result<bool, PasswordError> {
        bcrypt::verify(password, hash).map_err(|e| PasswordError::Verify(e.to_string()))
    }

    /// Verify a password against either a bcrypt or an Argon2 hash
    pub fn verify(password: &str, hash: &str) -> Result<bool, PasswordError> {
        if hash.starts_with("$argon2") {
            return Self::verify_argon2(password, hash);
        }

        if hash.starts_with("$2") {
            return Self::verify_bcrypt(password, hash);
        }

        Err(PasswordError::UnknownFormat)
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
    use argon2::password_hash::{PasswordHasher, SaltString};

    /// Hashes shared with the Node test `tests/unit/infrastructure/auth/RustBcryptCompat.test.js`:
    /// `rustHash` was written by `PasswordService::hash`, `nodeHash` by `bcryptjs.hash(pw, 10)`.
    const FIXTURE: &str = include_str!("../../../tests/fixtures/bcrypt_node_compat.json");

    fn fixture(key: &str) -> String {
        let value: serde_json::Value = serde_json::from_str(FIXTURE).unwrap();
        value[key].as_str().unwrap().to_string()
    }

    #[test]
    fn test_hash_is_bcrypt_at_node_cost() {
        let password = "test_password_123";
        let hash = PasswordService::hash(password).unwrap();

        assert!(
            hash.starts_with("$2b$10$"),
            "not a cost-10 bcrypt hash: {hash}"
        );
        assert!(PasswordService::verify(password, &hash).unwrap());
        assert!(!PasswordService::verify("wrong_password", &hash).unwrap());
    }

    #[test]
    fn test_argon2_hash_still_verifies() {
        let salt = SaltString::encode_b64(&[7u8; 16]).unwrap();
        let hash = Argon2::default()
            .hash_password(b"demo123", &salt)
            .unwrap()
            .to_string();

        assert!(PasswordService::verify("demo123", &hash).unwrap());
        assert!(!PasswordService::verify("wrong", &hash).unwrap());
    }

    #[test]
    fn test_fixture_rust_hash_verifies() {
        let rust_hash = fixture("rustHash");

        assert!(rust_hash.starts_with("$2b$10$"));
        assert!(PasswordService::verify(&fixture("password"), &rust_hash).unwrap());
        assert!(!PasswordService::verify("wrong", &rust_hash).unwrap());
    }

    #[test]
    fn test_fixture_node_hash_verifies() {
        let node_hash = fixture("nodeHash");

        assert!(PasswordService::verify(&fixture("password"), &node_hash).unwrap());
        assert!(!PasswordService::verify("wrong", &node_hash).unwrap());
    }

    #[test]
    fn test_bcryptjs_2a_hash_verifies() {
        // Hashes bcryptjs 2.x wrote before the upgrade to 3.x carry the `$2a$` prefix
        let hash = fixture("nodeHash").replacen("$2b$", "$2a$", 1);

        assert!(PasswordService::verify(&fixture("password"), &hash).unwrap());
    }

    #[test]
    fn test_unknown_format_is_an_error() {
        assert!(matches!(
            PasswordService::verify("pw", "plain"),
            Err(PasswordError::UnknownFormat)
        ));
    }

    /// Prints a fresh Rust hash for the fixture: `cargo test print_fixture_hash -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn print_fixture_hash() {
        println!("{}", PasswordService::hash(&fixture("password")).unwrap());
    }
}
