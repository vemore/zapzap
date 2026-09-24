//! Test double: a SQLite user repository whose reads can be made stale, to replay the
//! interleavings of two concurrent requests deterministically.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

use async_trait::async_trait;
use sqlx::sqlite::SqlitePoolOptions;
use sqlx::SqlitePool;

use crate::domain::entities::{BotDifficulty, User};
use crate::domain::repositories::{RepositoryError, UserRepository};
use crate::infrastructure::database::repositories::SqliteUserRepository;
use crate::infrastructure::database::schema::ensure_schema;

pub struct RacingUserRepo {
    pub pool: SqlitePool,
    pub inner: SqliteUserRepository,
    /// Number of upcoming `find_by_google_id` calls that answer `None`
    pub stale_google_lookups: AtomicUsize,
    /// Number of upcoming `exists_by_username` / `find_by_username` calls that find no user
    pub stale_username_checks: AtomicUsize,
    /// When set, `find_by_id` answers this user whatever the table holds
    pub stale_user: Mutex<Option<User>>,
}

impl RacingUserRepo {
    /// On a fresh in-memory database with the schema
    pub async fn new() -> Self {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .unwrap();
        ensure_schema(&pool).await.unwrap();
        Self {
            inner: SqliteUserRepository::new(pool.clone()),
            pool,
            stale_google_lookups: AtomicUsize::new(0),
            stale_username_checks: AtomicUsize::new(0),
            stale_user: Mutex::new(None),
        }
    }

    /// Seat `user_id` in a new party of the given status (`waiting`, `playing`, `finished`)
    pub async fn seat_in_party(&self, user_id: &str, status: &str) {
        let party_id = uuid::Uuid::new_v4().to_string();
        sqlx::query(
            "INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json, created_at, updated_at) \
             VALUES (?, 'p', ?, ?, 'public', ?, '{}', 0, 0)",
        )
        .bind(&party_id)
        .bind(user_id)
        .bind(&party_id[..8])
        .bind(status)
        .execute(&self.pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO party_players (party_id, user_id, player_index, joined_at) VALUES (?, ?, 0, 0)",
        )
        .bind(&party_id)
        .bind(user_id)
        .execute(&self.pool)
        .await
        .unwrap();
    }

    fn take(counter: &AtomicUsize) -> bool {
        counter
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1))
            .is_ok()
    }
}

#[async_trait]
impl UserRepository for RacingUserRepo {
    async fn find_by_id(&self, id: &str) -> Result<Option<User>, RepositoryError> {
        if let Some(user) = self.stale_user.lock().unwrap().clone() {
            return Ok(Some(user));
        }
        self.inner.find_by_id(id).await
    }
    async fn find_by_ids(&self, ids: &[String]) -> Result<Vec<User>, RepositoryError> {
        self.inner.find_by_ids(ids).await
    }
    async fn find_by_username(&self, username: &str) -> Result<Option<User>, RepositoryError> {
        if Self::take(&self.stale_username_checks) {
            return Ok(None);
        }
        self.inner.find_by_username(username).await
    }
    async fn find_by_google_id(&self, google_id: &str) -> Result<Option<User>, RepositoryError> {
        if Self::take(&self.stale_google_lookups) {
            return Ok(None);
        }
        self.inner.find_by_google_id(google_id).await
    }
    async fn exists_by_username(&self, username: &str) -> Result<bool, RepositoryError> {
        if Self::take(&self.stale_username_checks) {
            return Ok(false);
        }
        self.inner.exists_by_username(username).await
    }
    async fn find_all_bots(
        &self,
        difficulty: Option<BotDifficulty>,
    ) -> Result<Vec<User>, RepositoryError> {
        self.inner.find_all_bots(difficulty).await
    }
    async fn save(&self, user: &User) -> Result<(), RepositoryError> {
        self.inner.save(user).await
    }
    async fn delete(&self, id: &str) -> Result<bool, RepositoryError> {
        self.inner.delete(id).await
    }
    async fn is_in_active_party(&self, id: &str) -> Result<bool, RepositoryError> {
        self.inner.is_in_active_party(id).await
    }
    async fn update_last_login(&self, id: &str) -> Result<(), RepositoryError> {
        self.inner.update_last_login(id).await
    }
    async fn find_all_humans(&self, limit: u32, offset: u32) -> Result<Vec<User>, RepositoryError> {
        self.inner.find_all_humans(limit, offset).await
    }
    async fn set_admin(&self, id: &str, is_admin: bool) -> Result<(), RepositoryError> {
        self.inner.set_admin(id, is_admin).await
    }
}
