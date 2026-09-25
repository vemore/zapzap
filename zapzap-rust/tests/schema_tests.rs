//! The schema the Rust backend creates must be the one production's database has, and
//! running it on that database must change nothing.
//!
//! Production's database was built by the Node backend. Its schema is frozen in
//! `tests/fixtures/node_built_schema.sql` (how it was generated is at the top of that
//! file), so these tests need nothing outside `zapzap-rust/`.

use std::str::FromStr;

use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::{Row, SqlitePool};

use zapzap_backend::infrastructure::app_state::AppState;
use zapzap_backend::infrastructure::database::schema::ensure_schema;

/// The `sqlite_master` of a Node-built database, in creation order.
const NODE_BUILT_SCHEMA: &str = include_str!("fixtures/node_built_schema.sql");

/// The two users indexes the Node image's entrypoint added to databases it migrated;
/// the Rust schema does not create them.
const ENTRYPOINT_INDEXES: [&str; 2] = ["idx_users_username", "idx_users_user_type"];

const NODE_TABLES: [&str; 9] = [
    "game_actions",
    "game_results",
    "game_state",
    "parties",
    "party_players",
    "player_game_results",
    "round_scores",
    "rounds",
    "users",
];

/// Give `db` the schema of a Node-built database.
async fn build_node_schema(db: &SqlitePool) {
    sqlx::raw_sql(NODE_BUILT_SCHEMA).execute(db).await.unwrap();
}

async fn memory_pool() -> SqlitePool {
    SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .unwrap()
}

/// Every schema object with its DDL, whitespace collapsed, ordered by type and name.
async fn schema_objects(db: &SqlitePool) -> Vec<(String, String, String, String)> {
    sqlx::query(
        "SELECT type, name, tbl_name, COALESCE(sql, '') FROM sqlite_master \
         WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
    )
    .fetch_all(db)
    .await
    .unwrap()
    .into_iter()
    .map(|r| {
        let sql: String = r.get(3);
        (
            r.get(0),
            r.get(1),
            r.get(2),
            sql.split_whitespace().collect::<Vec<_>>().join(" "),
        )
    })
    .collect()
}

/// Every row of every table, each value `quote()`d, in rowid order.
async fn dump_rows(db: &SqlitePool) -> Vec<(String, String)> {
    let mut out = Vec::new();
    for table in NODE_TABLES {
        let cols: Vec<String> = sqlx::query(&format!("PRAGMA table_info({table})"))
            .fetch_all(db)
            .await
            .unwrap()
            .into_iter()
            .map(|r| format!("quote({})", r.get::<String, _>("name")))
            .collect();
        let rows: Vec<String> = sqlx::query_scalar(&format!(
            "SELECT {} FROM {table} ORDER BY rowid",
            cols.join(" || '|' || ")
        ))
        .fetch_all(db)
        .await
        .unwrap();
        for row in rows {
            out.push((table.to_string(), row));
        }
    }
    out
}

#[tokio::test]
async fn rust_schema_matches_the_node_built_schema() {
    let node = memory_pool().await;
    build_node_schema(&node).await;

    let rust = memory_pool().await;
    ensure_schema(&rust).await.unwrap();

    let node_objects = schema_objects(&node).await;
    let rust_objects = schema_objects(&rust).await;

    let tables: Vec<&str> = node_objects
        .iter()
        .filter(|o| o.0 == "table")
        .map(|o| o.1.as_str())
        .collect();
    assert_eq!(tables, NODE_TABLES, "the fixture was not read in full");
    assert_eq!(
        node_objects.iter().filter(|o| o.0 == "index").count(),
        23,
        "the fixture was not read in full"
    );

    // Same tables, columns, types, constraints and indexes, statement for statement,
    // but for the indexes only the entrypoint migration made.
    let node_objects: Vec<_> = node_objects
        .into_iter()
        .filter(|o| !ENTRYPOINT_INDEXES.contains(&o.1.as_str()))
        .collect();
    assert_eq!(rust_objects, node_objects);
}

#[tokio::test]
async fn schema_step_is_a_noop_on_a_node_built_database() {
    let path = std::env::temp_dir().join(format!(
        "zapzap-schema-test-{}-{}.db",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let url = format!("sqlite:{}", path.display());

    // A production-shaped database: the Node-built schema (the extra users indexes of
    // the docker-entrypoint migration included), and data in every table.
    let node = SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(
            SqliteConnectOptions::from_str(&url)
                .unwrap()
                .create_if_missing(true),
        )
        .await
        .unwrap();
    build_node_schema(&node).await;
    sqlx::raw_sql(
        "INSERT INTO users (id, username, password_hash, user_type, bot_difficulty, is_admin,
                            last_login_at, total_play_time_seconds, google_id, email,
                            created_at, updated_at)
           VALUES ('u1', 'alice', '$2b$10$hash', 'human', NULL, 1, 1700000100, 3600,
                   'g-123', 'alice@example.com', 1700000000, 1700000000),
                  ('b1', 'bot', NULL, 'bot', 'hard', 0, NULL, 0, NULL, NULL,
                   1700000000, 1700000000);
         INSERT INTO parties (id, name, owner_id, invite_code, visibility, status,
                              settings_json, current_round_id, created_at, updated_at)
           VALUES ('p1', 'Table', 'u1', 'ABC123', 'public', 'finished',
                   '{\"handSize\":5}', 'r1', 1700000000, 1700000500);
         INSERT INTO party_players (party_id, user_id, player_index, joined_at)
           VALUES ('p1', 'u1', 0, 1700000000), ('p1', 'b1', 1, 1700000001);
         INSERT INTO rounds (id, party_id, round_number, status, current_turn, current_action,
                             created_at, finished_at)
           VALUES ('r1', 'p1', 1, 'finished', 3, 'zapzap', 1700000010, 1700000400);
         INSERT INTO game_state (party_id, state_json, updated_at)
           VALUES ('p1', '{\"deck\":[1,2,3]}', 1700000400);
         INSERT INTO round_scores (party_id, round_number, user_id, player_index,
                                   score_this_round, total_score_after, hand_points,
                                   is_zapzap_caller, zapzap_success, hand_cards, created_at)
           VALUES ('p1', 1, 'u1', 0, 0, 0, 3, 1, 1, '[0,1]', 1700000400);
         INSERT INTO game_results (party_id, winner_user_id, winner_final_score, total_rounds,
                                   was_golden_score, player_count, finished_at, created_at)
           VALUES ('p1', 'u1', 12, 7, 1, 2, 1700000500, 1700000500);
         INSERT INTO player_game_results (party_id, user_id, final_score, finish_position,
                                          rounds_played, is_winner, created_at)
           VALUES ('p1', 'u1', 12, 1, 7, 1, 1700000500);
         INSERT INTO game_actions (party_id, round_number, turn_number, player_index, user_id,
                                   is_human, action_type, action_data, hand_before,
                                   hand_value_before, scores_before, opponent_hand_sizes,
                                   deck_size, last_cards_played, created_at)
           VALUES ('p1', 1, 1, 0, 'u1', 1, 'play', '{}', '[0,1]', 3, '[0,0]', '[5]', 40, '[]',
                   1700000200);",
    )
    .execute(&node)
    .await
    .unwrap();

    let objects_before = schema_objects(&node).await;
    let rows_before = dump_rows(&node).await;
    assert_eq!(rows_before.len(), 11);
    node.close().await;

    // The Rust schema step, as the server runs it at startup, twice.
    std::env::set_var("DATABASE_URL", &url);
    std::env::set_var("JWT_SECRET", "schema-test-secret");
    let state = AppState::new()
        .await
        .expect("AppState::new on a Node database");
    ensure_schema(&state.db).await.unwrap();

    assert_eq!(schema_objects(&state.db).await, objects_before);
    assert_eq!(dump_rows(&state.db).await, rows_before);
    let sqlx_table: Option<String> =
        sqlx::query_scalar("SELECT name FROM sqlite_master WHERE name = '_sqlx_migrations'")
            .fetch_optional(&state.db)
            .await
            .unwrap();
    assert_eq!(
        sqlx_table, None,
        "no sqlx migration bookkeeping on a Node DB"
    );

    state.db.close().await;
    let _ = std::fs::remove_file(&path);
}

/// A `users` table rebuilt by the Node image's entrypoint (its `users_new` has no
/// `google_id`/`email`) and not yet opened by the Node app: the schema step cannot create
/// `idx_users_google_id` on it. It must fail as a whole, leaving the database unchanged —
/// not commit the tables it created before the failing statement.
#[tokio::test]
async fn schema_step_failure_leaves_the_database_unchanged() {
    let db = memory_pool().await;
    sqlx::raw_sql(
        "CREATE TABLE users (
             id TEXT PRIMARY KEY,
             username TEXT UNIQUE NOT NULL,
             password_hash TEXT NOT NULL,
             user_type TEXT DEFAULT 'human' CHECK(user_type IN ('human', 'bot')),
             bot_difficulty TEXT CHECK(bot_difficulty IN ('easy', 'medium', 'hard', 'hard_vince')),
             is_admin INTEGER DEFAULT 0,
             last_login_at INTEGER,
             total_play_time_seconds INTEGER DEFAULT 0,
             created_at INTEGER NOT NULL,
             updated_at INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
         CREATE INDEX IF NOT EXISTS idx_users_user_type ON users(user_type);
         INSERT INTO users (id, username, password_hash, created_at, updated_at)
           VALUES ('u1', 'alice', '$2b$10$hash', 1700000000, 1700000000);",
    )
    .execute(&db)
    .await
    .unwrap();

    let objects_before = schema_objects(&db).await;
    let rows_before: Vec<String> =
        sqlx::query_scalar("SELECT id || '|' || username FROM users ORDER BY rowid")
            .fetch_all(&db)
            .await
            .unwrap();

    let err = ensure_schema(&db)
        .await
        .expect_err("the schema step cannot index a column the table lacks");
    assert!(err.to_string().contains("google_id"), "{err}");

    // Nothing the step ran before the failing index survived: no parties table, no index.
    assert_eq!(schema_objects(&db).await, objects_before);
    let rows_after: Vec<String> =
        sqlx::query_scalar("SELECT id || '|' || username FROM users ORDER BY rowid")
            .fetch_all(&db)
            .await
            .unwrap();
    assert_eq!(rows_after, rows_before);
}
