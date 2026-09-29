//! Play without an account: a guest is a human user created without a form, under a
//! random name (`Guest_` and five digits) and a random password the player's device keeps
//! and signs back in with once the 7-day token has expired. The account becomes the
//! player's own (`is_guest` cleared) when they set a password of their own
//! (`ChangePassword`, `UserRepository::update_password_hash`).

use std::sync::Arc;

use rand::distr::Alphanumeric;
use rand::RngExt;
use uuid::Uuid;

use crate::domain::entities::User;
use crate::domain::repositories::UserRepository;
use crate::infrastructure::auth::{JwtService, PasswordService};

/// The start of every guest's name; the rest is `GUEST_DIGITS` random digits
pub const GUEST_PREFIX: &str = "Guest_";
const GUEST_DIGITS: usize = 5;
/// Letters and digits: about 143 bits, under bcrypt's 72-byte limit
pub const GUEST_PASSWORD_LENGTH: usize = 24;
/// Names drawn before giving up: 100 000 of them, so a miss is rare until guests number
/// tens of thousands
const NAME_ATTEMPTS: usize = 20;

/// A guest's name: `Guest_` and five random digits, which passes sign-up's rules
pub fn guest_username() -> String {
    let mut rng = rand::rng();
    let digits: String = (0..GUEST_DIGITS)
        .map(|_| char::from(b'0' + rng.random_range(0..10u8)))
        .collect();
    format!("{GUEST_PREFIX}{digits}")
}

/// A guest's password: `GUEST_PASSWORD_LENGTH` letters and digits from the thread's
/// generator, a CSPRNG (ChaCha12 seeded from the operating system)
pub fn guest_password() -> String {
    rand::rng()
        .sample_iter(Alphanumeric)
        .take(GUEST_PASSWORD_LENGTH)
        .map(char::from)
        .collect()
}

/// A new guest: the user, its token, and its password, answered once and never logged
pub struct CreateGuestOutput {
    pub user: User,
    pub token: String,
    pub password: String,
}

/// Create guest use case
pub struct CreateGuest {
    user_repo: Arc<dyn UserRepository>,
    jwt_service: Arc<JwtService>,
}

impl CreateGuest {
    pub fn new(user_repo: Arc<dyn UserRepository>, jwt_service: Arc<JwtService>) -> Self {
        Self {
            user_repo,
            jwt_service,
        }
    }

    /// A name free whatever its case is drawn, then saved; a name taken between the check
    /// and the save fails on the `username` UNIQUE constraint and another one is drawn
    pub async fn execute(&self) -> Result<CreateGuestOutput, CreateGuestError> {
        self.execute_with(guest_username).await
    }

    /// `execute`, the names drawn from `next_name`
    async fn execute_with(
        &self,
        mut next_name: impl FnMut() -> String,
    ) -> Result<CreateGuestOutput, CreateGuestError> {
        let password = guest_password();
        let password_hash = PasswordService::hash(&password)
            .map_err(|e| CreateGuestError::Internal(e.to_string()))?;

        for _ in 0..NAME_ATTEMPTS {
            let username = next_name();
            if self.user_repo.exists_by_username_ci(&username).await? {
                continue;
            }
            let user = User::new_guest(Uuid::new_v4().to_string(), username, password_hash.clone());
            match self.user_repo.save(&user).await {
                Ok(()) => {
                    let token = self
                        .jwt_service
                        .sign(&user.id, &user.username, user.is_admin)
                        .map_err(|e| CreateGuestError::Internal(e.to_string()))?;
                    return Ok(CreateGuestOutput {
                        user,
                        token,
                        password,
                    });
                }
                Err(e) if e.is_unique_violation() => continue,
                Err(e) => return Err(e.into()),
            }
        }
        Err(CreateGuestError::NoFreeName)
    }
}

/// Create guest error types
#[derive(Debug, thiserror::Error)]
pub enum CreateGuestError {
    #[error("No free guest name")]
    NoFreeName,
    #[error("Internal error: {0}")]
    Internal(String),
    #[error("Repository error: {0}")]
    Repository(#[from] crate::domain::repositories::RepositoryError),
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::application::auth::validate_username;
    use crate::infrastructure::database::repositories::racing_user_repo::RacingUserRepo;
    use std::sync::atomic::Ordering;

    #[test]
    fn a_guest_name_passes_the_sign_up_rules() {
        for _ in 0..100 {
            let name = guest_username();
            assert!(name.starts_with(GUEST_PREFIX), "{name}");
            assert_eq!(name.len(), GUEST_PREFIX.len() + GUEST_DIGITS);
            validate_username(&name).unwrap();
        }
    }

    #[test]
    fn a_guest_password_is_long_alphanumeric_and_never_the_same() {
        let a = guest_password();
        let b = guest_password();
        assert_eq!(a.len(), GUEST_PASSWORD_LENGTH);
        assert!(a.chars().all(|c| c.is_ascii_alphanumeric()), "{a}");
        assert_ne!(a, b);
    }

    #[tokio::test]
    async fn a_name_taken_in_any_case_or_after_the_check_is_drawn_again() {
        let repo = Arc::new(RacingUserRepo::new().await);
        let jwt = Arc::new(JwtService::new("unit-test-secret".into()));
        let uc = CreateGuest::new(repo.clone(), jwt.clone());
        for (id, name) in [
            ("a", "Guest_00001"),
            ("b", "guest_00002"),
            ("c", "Guest_00003"),
        ] {
            repo.save(&User::new_human(id.into(), name.into(), "hash".into()))
                .await
                .unwrap();
        }
        let mut names = ["Guest_00001", "Guest_00002", "Guest_00003", "Guest_00004"]
            .into_iter()
            .map(String::from);

        // The first two are seen taken (the second in another case); the third's check
        // answers free, as if it were taken between the check and the save: the UNIQUE
        // constraint refuses it, and the fourth is drawn
        repo.stale_username_checks.store(0, Ordering::SeqCst);
        let checks = [false, false, true];
        let mut drawn = 0;
        let guest = uc
            .execute_with(|| {
                if checks.get(drawn).copied().unwrap_or(false) {
                    repo.stale_username_checks.store(1, Ordering::SeqCst);
                }
                drawn += 1;
                names.next().unwrap()
            })
            .await
            .unwrap();

        assert_eq!(guest.user.username, "Guest_00004");
        assert!(guest.user.is_guest);
        assert_eq!(jwt.verify(&guest.token).unwrap().user_id, guest.user.id);
        let stored = repo.find_by_id(&guest.user.id).await.unwrap().unwrap();
        assert!(stored.is_guest);
        assert!(
            PasswordService::verify(&guest.password, stored.password_hash.as_deref().unwrap())
                .unwrap()
        );
    }

    #[tokio::test]
    async fn no_free_name_is_an_error() {
        let repo = Arc::new(RacingUserRepo::new().await);
        let jwt = Arc::new(JwtService::new("unit-test-secret".into()));
        repo.save(&User::new_human(
            "a".into(),
            "Guest_00001".into(),
            "hash".into(),
        ))
        .await
        .unwrap();
        let uc = CreateGuest::new(repo, jwt);
        let err = uc
            .execute_with(|| "Guest_00001".to_string())
            .await
            .err()
            .unwrap();
        assert!(matches!(err, CreateGuestError::NoFreeName), "{err}");
    }
}
