use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use async_broadcast::{broadcast, Receiver, Sender};
use sqlx::SqlitePool;
use tokio::sync::RwLock;

use crate::application::bot::BotRunner;
use crate::infrastructure::auth::JwtService;
use crate::infrastructure::bot::llm_memory::LlmBotMemory;
use crate::infrastructure::database::repositories::{SqlitePartyRepository, SqliteUserRepository};
use crate::infrastructure::services::{
    probe_within, GoogleOAuthService, LlmService, OllamaConfig, OllamaService, SessionManager,
    STARTUP_PROBE_TIMEOUT,
};
#[cfg(feature = "bedrock")]
use crate::infrastructure::services::{BedrockConfig, BedrockService};

/// Placeholder secrets published in this repository (code defaults, `.env.example`,
/// README): a token signed with one of them can be forged by anyone.
pub const PUBLIC_JWT_SECRETS: [&str; 4] = [
    "zapzap-secret-key-change-in-production",
    "your-secret-key-change-in-production",
    "change-this-to-a-secure-random-string",
    "your-secure-random-string-here",
];

/// The JWT signing secret, from the value of `JWT_SECRET`. There is no default: a missing,
/// blank or publicly known secret is an error, and the server refuses to start.
pub fn jwt_secret_from(value: Option<String>) -> anyhow::Result<String> {
    let secret = value.unwrap_or_default().trim().to_string();
    if secret.is_empty() {
        anyhow::bail!(
            "JWT_SECRET is not set: the server refuses to start without a secret to sign \
             tokens with (generate one with `openssl rand -hex 32`)"
        );
    }
    if PUBLIC_JWT_SECRETS.contains(&secret.as_str()) {
        anyhow::bail!(
            "JWT_SECRET is a placeholder published in the repository: set it to a private \
             random value (`openssl rand -hex 32`)"
        );
    }
    Ok(secret)
}

/// Application state shared across all handlers
#[derive(Clone)]
pub struct AppState {
    /// Database connection pool
    pub db: SqlitePool,

    /// JWT service for token management
    pub jwt_service: Arc<JwtService>,

    /// Session manager for tracking connected users
    pub session_manager: Arc<SessionManager>,

    /// User repository
    pub user_repo: Arc<SqliteUserRepository>,

    /// Party repository
    pub party_repo: Arc<SqlitePartyRepository>,

    /// Event broadcaster for SSE
    pub event_sender: Sender<GameEvent>,
    pub event_receiver: Receiver<GameEvent>,

    /// LLM service for bot intelligence (optional)
    pub llm_service: Option<Arc<dyn LlmService>>,

    /// LLM bot memories (keyed by bot user ID)
    pub llm_memories: Arc<RwLock<HashMap<String, Arc<RwLock<LlmBotMemory>>>>>,
    /// Where the LLM bot memories are saved (`BOT_STRATEGIES_DIR`)
    pub bot_strategies_dir: PathBuf,

    /// Bot turns: one loop at a time per party, and each bot's strategy for the game
    pub bot_runner: Arc<BotRunner>,
    /// Google ID token verifier; `None` when `GOOGLE_OAUTH_CLIENT_ID` is unset
    pub google_oauth: Option<Arc<GoogleOAuthService>>,
}

impl AppState {
    pub async fn new() -> anyhow::Result<Self> {
        // The signing secret first: without one the server must not start at all
        let jwt_secret = jwt_secret_from(std::env::var("JWT_SECRET").ok())?;

        // Get database path from environment
        let db_path = std::env::var("DATABASE_URL")
            .or_else(|_| std::env::var("DB_PATH"))
            .unwrap_or_else(|_| "sqlite:./data/zapzap.db".to_string());

        // Ensure path has sqlite: prefix
        let db_url = if db_path.starts_with("sqlite:") {
            db_path
        } else {
            format!("sqlite:{}", db_path)
        };

        tracing::info!("Connecting to database: {}", db_url);

        // Connect to database
        let db = SqlitePool::connect(&db_url).await?;

        // Create the tables and indexes that are missing (a no-op on a Node-built database)
        crate::infrastructure::database::schema::ensure_schema(&db).await?;

        // Create JWT service
        let jwt_service = Arc::new(JwtService::new(jwt_secret));

        // Create session manager
        let session_manager = Arc::new(SessionManager::new());

        // Create repositories
        let user_repo = Arc::new(SqliteUserRepository::new(db.clone()));
        let party_repo = Arc::new(SqlitePartyRepository::new(db.clone()));

        // Create event broadcaster (capacity of 1000 events)
        // Enable overflow mode to drop oldest messages when full instead of blocking
        let (mut event_sender, event_receiver) = broadcast(1000);
        event_sender.set_overflow(true);

        // Initialize LLM service if configured
        // Priority: AWS Bedrock > Ollama > None
        let llm_service: Option<Arc<dyn LlmService>> = {
            // Check for AWS Bedrock configuration
            #[cfg(feature = "bedrock")]
            {
                if llm_enabled("AWS_BEDROCK_ENABLED", "AWS_ACCESS_KEY_ID") {
                    // Bounded: the probe runs before the port is bound
                    let probe = async {
                        let service = BedrockService::new(BedrockConfig::default()).await;
                        service.health_check().await.then_some(service)
                    };
                    match probe_within("AWS Bedrock", STARTUP_PROBE_TIMEOUT, probe).await {
                        Some(service) => {
                            tracing::info!("AWS Bedrock LLM service initialized and available");
                            Some(Arc::new(service) as Arc<dyn LlmService>)
                        }
                        None => {
                            tracing::warn!(
                                "AWS Bedrock configured but not available - trying Ollama"
                            );
                            None
                        }
                    }
                } else {
                    None
                }
            }
            #[cfg(not(feature = "bedrock"))]
            {
                None
            }
        };

        // Fall back to Ollama if Bedrock not configured/available
        let llm_service: Option<Arc<dyn LlmService>> = if llm_service.is_some() {
            llm_service
        } else if llm_enabled("ENABLE_LLM_BOTS", "OLLAMA_BASE_URL") {
            let probe = async {
                let service = OllamaService::new(OllamaConfig::default());
                service.health_check().await.then_some(service)
            };
            match probe_within("Ollama", STARTUP_PROBE_TIMEOUT, probe).await {
                Some(service) => {
                    tracing::info!("Ollama LLM service initialized and available");
                    Some(Arc::new(service))
                }
                None => {
                    tracing::warn!(
                        "Ollama configured but not available - LLM bots will use fallback"
                    );
                    None
                }
            }
        } else {
            tracing::info!("LLM service not configured - LLM bots will use fallback strategy");
            None
        };

        // Initialize LLM memories storage
        let llm_memories = Arc::new(RwLock::new(HashMap::new()));

        let google_oauth = GoogleOAuthService::from_env().map(Arc::new);
        if google_oauth.is_none() {
            tracing::warn!("GOOGLE_OAUTH_CLIENT_ID not configured, Google auth disabled");
        }

        Ok(Self {
            db,
            jwt_service,
            session_manager,
            user_repo,
            party_repo,
            event_sender,
            event_receiver,
            llm_service,
            llm_memories,
            bot_strategies_dir: bot_strategies_dir(),
            bot_runner: Arc::new(BotRunner::from_env()),
            google_oauth,
        })
    }

    /// Get or create LLM bot memory for a specific bot
    pub async fn get_llm_memory(&self, bot_user_id: &str) -> Arc<RwLock<LlmBotMemory>> {
        let memories = self.llm_memories.read().await;
        if let Some(memory) = memories.get(bot_user_id) {
            return memory.clone();
        }
        drop(memories);

        // Create new memory; one that cannot be read starts empty (`load` says why)
        let mut memory = LlmBotMemory::new(bot_user_id, Some(self.bot_strategies_dir.clone()));
        memory.load().await;

        let memory = Arc::new(RwLock::new(memory));
        let mut memories = self.llm_memories.write().await;
        memories.insert(bot_user_id.to_string(), memory.clone());
        memory
    }

    /// Broadcast an event to all connected SSE clients
    pub fn broadcast_event(&self, event: GameEvent) {
        let receiver_count = self.event_sender.receiver_count();
        tracing::debug!(
            "Broadcasting event '{}' to {} receivers",
            event.event_type,
            receiver_count
        );
        match self.event_sender.try_broadcast(event) {
            Ok(None) => {
                tracing::debug!("Event broadcast but no active receivers");
            }
            Ok(Some(_)) => {
                tracing::debug!("Event broadcast successfully with overflow");
            }
            Err(e) => {
                tracing::warn!("Failed to broadcast event: {:?}", e);
            }
        }
    }
}

/// The directory of the LLM bot memories: `BOT_STRATEGIES_DIR`, `data/bot-strategies`
/// by default
fn bot_strategies_dir() -> PathBuf {
    PathBuf::from(
        std::env::var("BOT_STRATEGIES_DIR").unwrap_or_else(|_| "data/bot-strategies".to_string()),
    )
}

/// Whether an LLM service is switched on. The switch (`AWS_BEDROCK_ENABLED`,
/// `ENABLE_LLM_BOTS`), when present, decides alone: off when empty, `false` or `0`, so a
/// compose file passing `AWS_BEDROCK_ENABLED=false` keeps Bedrock off even with AWS keys.
/// Only without a switch does its key (`AWS_ACCESS_KEY_ID`, `OLLAMA_BASE_URL`), set and
/// not empty, turn the service on.
fn llm_enabled(switch: &str, key: &str) -> bool {
    llm_switch(std::env::var(switch).ok(), std::env::var(key).ok())
}

fn llm_switch(switch: Option<String>, key: Option<String>) -> bool {
    match switch {
        Some(v) => {
            let v = v.trim();
            !v.is_empty() && v != "0" && !v.eq_ignore_ascii_case("false")
        }
        None => key.is_some_and(|k| !k.trim().is_empty()),
    }
}

/// Game event for SSE broadcasting
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GameEvent {
    #[serde(rename = "type")]
    pub event_type: String,
    pub party_id: Option<String>,
    pub user_id: Option<String>,
    /// Action field at top level for frontend compatibility
    #[serde(skip_serializing_if = "Option::is_none")]
    pub action: Option<String>,
    /// Additional data fields (flattened into root)
    #[serde(flatten)]
    pub data: serde_json::Value,
    pub timestamp: i64,
}

impl GameEvent {
    pub fn new(event_type: &str, party_id: Option<String>, user_id: Option<String>) -> Self {
        Self {
            event_type: event_type.to_string(),
            party_id,
            user_id,
            action: None,
            data: serde_json::Value::Object(serde_json::Map::new()),
            timestamp: chrono::Utc::now().timestamp_millis(),
        }
    }

    pub fn with_action(mut self, action: &str) -> Self {
        self.action = Some(action.to_string());
        self
    }

    pub fn with_data(mut self, data: serde_json::Value) -> Self {
        self.data = data;
        self
    }
}

#[cfg(test)]
mod tests {
    fn some(v: &str) -> Option<String> {
        Some(v.to_string())
    }

    #[test]
    fn test_llm_switch_present_decides_alone() {
        // AWS_BEDROCK_ENABLED=false with AWS keys set: off
        assert!(!llm_switch(some("false"), some("AKIA123")));
        assert!(!llm_switch(some("0"), some("AKIA123")));
        assert!(!llm_switch(some(""), some("http://ollama:11434")));
        assert!(llm_switch(some("true"), None));
        assert!(llm_switch(some("1"), some("")));
    }

    #[test]
    fn test_llm_switch_absent_falls_back_on_the_key() {
        assert!(llm_switch(None, some("AKIA123")));
        assert!(llm_switch(None, some("http://ollama:11434")));
        assert!(!llm_switch(None, some("  ")));
        assert!(!llm_switch(None, None));
    }

    use super::*;

    #[test]
    fn jwt_secret_is_required() {
        let err = jwt_secret_from(None).unwrap_err().to_string();
        assert!(err.contains("JWT_SECRET is not set"), "{err}");
        assert!(jwt_secret_from(Some("  ".into())).is_err());
    }

    #[test]
    fn jwt_secret_refuses_the_published_placeholders() {
        for secret in PUBLIC_JWT_SECRETS {
            let err = jwt_secret_from(Some(secret.into()))
                .unwrap_err()
                .to_string();
            assert!(err.contains("placeholder"), "{secret}: {err}");
        }
    }

    #[test]
    fn jwt_secret_is_trimmed_before_checks_and_use() {
        let err = jwt_secret_from(Some(" zapzap-secret-key-change-in-production\n".into()))
            .unwrap_err()
            .to_string();
        assert!(err.contains("placeholder"), "{err}");
        assert_eq!(
            jwt_secret_from(Some("  4f1c0e9a\n".into())).unwrap(),
            "4f1c0e9a"
        );
    }

    #[test]
    fn jwt_secret_accepts_a_private_value() {
        assert_eq!(
            jwt_secret_from(Some("4f1c0e9a".into())).unwrap(),
            "4f1c0e9a"
        );
    }
}
