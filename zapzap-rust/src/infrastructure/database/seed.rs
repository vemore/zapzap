//! Seeding the accounts a fresh database needs: the bot accounts and, on request, the demo
//! users. `zapzap-backend seed [--demo]` runs it (`main.rs`); it replaces the Node scripts
//! `scripts/init-bots.js` and `scripts/init-demo-data.js`.
//!
//! Idempotent: the schema step first (`ensure_schema`, a no-op on an existing database),
//! then an account is created only when its username is free. Run twice, or on the
//! production file, it adds nothing that is already there and changes nothing that is.

use std::str::FromStr;

use sqlx::sqlite::SqliteConnectOptions;
use sqlx::SqlitePool;
use uuid::Uuid;

use crate::domain::entities::{BotDifficulty, User};
use crate::domain::repositories::UserRepository;
use crate::infrastructure::auth::PasswordService;
use crate::infrastructure::database::repositories::SqliteUserRepository;
use crate::infrastructure::database::schema::ensure_schema;

/// The bot accounts, as `scripts/init-bots.js` creates them: two of each difficulty.
pub const SEED_BOTS: [(&str, BotDifficulty); 8] = [
    ("EasyBot1", BotDifficulty::Easy),
    ("EasyBot2", BotDifficulty::Easy),
    ("MediumBot1", BotDifficulty::Medium),
    ("MediumBot2", BotDifficulty::Medium),
    ("HardBot1", BotDifficulty::Hard),
    ("HardBot2", BotDifficulty::Hard),
    ("Thibot1", BotDifficulty::Thibot),
    ("Thibot2", BotDifficulty::Thibot),
];

/// The demo users of `scripts/init-demo-data.js`, all with the password [`DEMO_PASSWORD`].
pub const DEMO_USERS: [&str; 5] = ["Vincent", "Thibaut", "Simon", "Lyo", "Laurent"];

/// The demo users' password.
pub const DEMO_PASSWORD: &str = "demo123";

/// What a seed did: the usernames it created and the ones it found already taken.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct SeedReport {
    pub created: Vec<String>,
    pub existing: Vec<String>,
}

/// Open the SQLite database at `url` (`sqlite:<path>`, or a bare path), creating the file
/// when it does not exist.
pub async fn open(url: &str) -> anyhow::Result<SqlitePool> {
    let url = if url.starts_with("sqlite:") {
        url.to_string()
    } else {
        format!("sqlite:{url}")
    };
    let options = SqliteConnectOptions::from_str(&url)?.create_if_missing(true);
    Ok(SqlitePool::connect_with(options).await?)
}

/// Create the schema that is missing, then every bot account whose username is free and,
/// with `demo`, every free demo user (bcrypt-hashed `demo123`, as registration hashes).
pub async fn seed(db: &SqlitePool, demo: bool) -> anyhow::Result<SeedReport> {
    ensure_schema(db).await?;
    let repo = SqliteUserRepository::new(db.clone());
    let mut report = SeedReport::default();

    for (username, difficulty) in SEED_BOTS {
        if repo.exists_by_username(username).await? {
            report.existing.push(username.to_string());
            continue;
        }
        let bot = User::new_bot(Uuid::new_v4().to_string(), username.to_string(), difficulty);
        repo.save(&bot).await?;
        report.created.push(username.to_string());
    }

    if demo {
        for username in DEMO_USERS {
            if repo.exists_by_username(username).await? {
                report.existing.push(username.to_string());
                continue;
            }
            let hash = PasswordService::hash(DEMO_PASSWORD)?;
            let user = User::new_human(Uuid::new_v4().to_string(), username.to_string(), hash);
            repo.save(&user).await?;
            report.created.push(username.to_string());
        }
    }

    Ok(report)
}
