//! The schema the Rust backend creates must be the one the Node backend creates, and
//! running it on a database the Node backend built must change nothing.
//!
//! The Node DDL is read from the Node source itself
//! (`src/infrastructure/database/sqlite/DatabaseConnection.js`), so the two cannot drift
//! apart without this file going red.

use std::str::FromStr;

use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::{Row, SqlitePool};

use zapzap_backend::infrastructure::app_state::AppState;
use zapzap_backend::infrastructure::database::schema::ensure_schema;

const NODE_SOURCE: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../src/infrastructure/database/sqlite/DatabaseConnection.js"
));

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

/// The statements a fresh Node database receives, in order: the `createSchema()` DDL
/// string, then what `runMigrations()` runs — its `ALTER TABLE ... ADD COLUMN` statements
/// (Node ignores "duplicate column name", so on a fresh database only a column the DDL
/// lacks is added) and its `CREATE INDEX` calls. The password_hash rebuild is skipped on
/// a fresh database (password_hash is already nullable), so it is not replayed.
fn node_statements() -> Vec<String> {
    let start = NODE_SOURCE
        .find("const schema = `")
        .expect("createSchema() DDL not found in DatabaseConnection.js")
        + "const schema = `".len();
    let len = NODE_SOURCE[start..]
        .find('`')
        .expect("end of the createSchema() DDL not found");
    let mut statements = vec![NODE_SOURCE[start..start + len].to_string()];

    let migrations = &NODE_SOURCE[NODE_SOURCE
        .find("async runMigrations()")
        .expect("runMigrations() not found")..];
    let migrations = &migrations[..migrations
        .find("async migratePasswordHashNullable()")
        .expect("migratePasswordHashNullable() not found")];
    let (mut alters, mut indexes) = (0, 0);
    for line in migrations.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("sql: 'ALTER TABLE") {
            let stmt = rest.split('\'').next().unwrap();
            statements.push(format!("ALTER TABLE{stmt}"));
            alters += 1;
        } else if let Some(rest) = line.strip_prefix("await this.run('CREATE INDEX") {
            let stmt = rest.split("')").next().unwrap();
            statements.push(format!("CREATE INDEX{stmt};"));
            indexes += 1;
        }
    }
    assert!(
        alters >= 5,
        "the ALTER TABLE statements of runMigrations() were not read"
    );
    assert_eq!(
        indexes, 2,
        "expected the two users indexes of runMigrations()"
    );
    statements
}

/// Build the schema a fresh Node database gets, as `DatabaseConnection.js` does.
async fn build_node_schema(db: &SqlitePool) {
    for stmt in node_statements() {
        if let Err(e) = sqlx::raw_sql(&stmt).execute(db).await {
            // runMigrations() ignores exactly this error, and nothing else.
            assert!(
                stmt.starts_with("ALTER TABLE") && e.to_string().contains("duplicate column name"),
                "{stmt}: {e}"
            );
        }
    }
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
async fn rust_schema_matches_node_schema() {
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
    assert_eq!(tables, NODE_TABLES, "the Node DDL was not read in full");
    assert_eq!(
        node_objects.iter().filter(|o| o.0 == "index").count(),
        21,
        "the Node DDL was not read in full"
    );

    // Same tables, columns, types, constraints and indexes, statement for statement.
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

    // A production-shaped database: the Node schema, the extra users indexes the
    // docker-entrypoint migration leaves behind, and data in every table.
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
        "CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
         CREATE INDEX IF NOT EXISTS idx_users_user_type ON users(user_type);
         INSERT INTO users (id, username, password_hash, user_type, bot_difficulty, is_admin,
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
