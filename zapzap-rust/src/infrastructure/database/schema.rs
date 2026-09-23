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
pub async fn ensure_schema(db: &SqlitePool) -> Result<(), sqlx::Error> {
    sqlx::raw_sql(SCHEMA_SQL).execute(db).await?;
    Ok(())
}
