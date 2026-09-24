//! The SQLite schema the backend creates for itself at startup.
//!
//! It is the Node backend's DDL (`schema.sql` says where it comes from), written with
//! `IF NOT EXISTS` throughout: a fresh database gets every table and index, a database the
//! Node backend built is left untouched. There is deliberately no sqlx migration table: the
//! production database has none, and `sqlx::migrate!` would try to manage it.

use sqlx::SqlitePool;

/// The DDL, statement by statement as the Node backend runs it.
pub const SCHEMA_SQL: &str = include_str!("schema.sql");

/// Create every table and index that does not exist yet. Idempotent.
///
/// The whole DDL runs in one transaction: a statement that fails (say, an index on a
/// column an older `users` table lacks) rolls back the ones before it, and the database is
/// left exactly as it was.
pub async fn ensure_schema(db: &SqlitePool) -> Result<(), sqlx::Error> {
    let mut tx = db.begin().await?;
    sqlx::raw_sql(SCHEMA_SQL).execute(&mut *tx).await?;
    tx.commit().await
}
