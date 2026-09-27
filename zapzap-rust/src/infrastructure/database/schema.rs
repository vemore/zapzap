//! The SQLite schema the backend creates for itself at startup.
//!
//! It is the Node backend's DDL (`schema.sql` says where it comes from), written with
//! `IF NOT EXISTS` throughout: a fresh database gets every table and index, a database the
//! Node backend built is left untouched by it. The changes made since are `MIGRATIONS`,
//! counted in `PRAGMA user_version`, which the Node backend never set. There is
//! deliberately no sqlx migration table: the production database has none, and
//! `sqlx::migrate!` would try to manage it.

use sqlx::SqlitePool;

/// The DDL, statement by statement as the Node backend runs it.
pub const SCHEMA_SQL: &str = include_str!("schema.sql");

/// The schema changes made after the Node DDL, in order: the one at index `n` takes
/// `PRAGMA user_version` from `n` to `n + 1`. A database the Node backend built is at 0, a
/// fresh one runs the DDL then every step, so both end with the same schema.
pub const MIGRATIONS: &[&str] = &[
    // 1: the version of a party's game state, compared and bumped by every write so that
    // a write based on a stale read is refused (`update_game_state`); existing rows start
    // at 0
    "ALTER TABLE game_state ADD COLUMN version INTEGER NOT NULL DEFAULT 0",
    // 2: one user per Google account. Node's `idx_users_google_id` is a plain index, so two
    // first logins of one account racing on different usernames could both insert; the
    // loser's save now fails here and it answers the winner's user (`LoginWithGoogle`).
    // Partial, so every password or bot user (NULL) still inserts. A database holding two
    // users of one `google_id` fails this step and the server refuses to start, unchanged
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google_id_unique ON users(google_id) \
     WHERE google_id IS NOT NULL",
];

/// Create every table and index that does not exist yet, then run the migrations the
/// database has not had. Idempotent.
///
/// It all runs in one transaction: a statement that fails (say, an index on a column an
/// older `users` table lacks) rolls back the ones before it, `user_version` included, and
/// the database is left exactly as it was.
pub async fn ensure_schema(db: &SqlitePool) -> Result<(), sqlx::Error> {
    let mut tx = db.begin().await?;
    sqlx::raw_sql(SCHEMA_SQL).execute(&mut *tx).await?;
    let applied: i64 = sqlx::query_scalar("PRAGMA user_version")
        .fetch_one(&mut *tx)
        .await?;
    // A database a newer binary migrated further is left as it is
    for (done, step) in MIGRATIONS.iter().enumerate().skip(applied.max(0) as usize) {
        sqlx::raw_sql(step).execute(&mut *tx).await?;
        sqlx::raw_sql(&format!("PRAGMA user_version = {}", done + 1))
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await
}
