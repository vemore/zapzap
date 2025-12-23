use std::collections::HashMap;
use std::sync::Arc;

use async_broadcast::{broadcast, Receiver, Sender};
use sqlx::SqlitePool;
use tokio::sync::RwLock;

use crate::infrastructure::auth::JwtService;
use crate::infrastructure::bot::llm_memory::LlmBotMemory;
use crate::infrastructure::database::repositories::{SqlitePartyRepository, SqliteUserRepository};
use crate::infrastructure::services::{LlmService, OllamaConfig, OllamaService, SessionManager};
#[cfg(feature = "bedrock")]
use crate::infrastructure::services::{BedrockConfig, BedrockService};

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
}

impl AppState {
    pub async fn new() -> anyhow::Result<Self> {
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

        // Run migrations if needed
        // sqlx::migrate!("./migrations").run(&db).await?;

        // Create JWT service
        let jwt_secret = std::env::var("JWT_SECRET")
            .unwrap_or_else(|_| "zapzap-secret-key-change-in-production".to_string());
        let jwt_service = Arc::new(JwtService::new(jwt_secret));

        // Create session manager
        let session_manager = Arc::new(SessionManager::new());

        // Create repositories
        let user_repo = Arc::new(SqliteUserRepository::new(db.clone()));
        let party_repo = Arc::new(SqlitePartyRepository::new(db.clone()));

        // Create event broadcaster (capacity of 1000 events)
        let (event_sender, event_receiver) = broadcast(1000);

        // Initialize LLM service if configured
        // Priority: AWS Bedrock > Ollama > None
        let llm_service: Option<Arc<dyn LlmService>> = {
            // Check for AWS Bedrock configuration
            #[cfg(feature = "bedrock")]
            {
                if std::env::var("AWS_BEDROCK_ENABLED").is_ok()
                    || std::env::var("AWS_ACCESS_KEY_ID").is_ok()
                {
                    let config = BedrockConfig::default();
                    let service = BedrockService::new(config).await;
                    if service.health_check().await {
                        tracing::info!("AWS Bedrock LLM service initialized and available");
                        Some(Arc::new(service) as Arc<dyn LlmService>)
                    } else {
                        tracing::warn!("AWS Bedrock configured but not available - trying Ollama");
                        None
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
        } else if std::env::var("OLLAMA_BASE_URL").is_ok() || std::env::var("ENABLE_LLM_BOTS").is_ok()
        {
            let service = OllamaService::new(OllamaConfig::default());
            // Check if Ollama is available
            if service.health_check().await {
                tracing::info!("Ollama LLM service initialized and available");
                Some(Arc::new(service))
            } else {
                tracing::warn!("Ollama configured but not available - LLM bots will use fallback");
                None
            }
        } else {
            tracing::info!("LLM service not configured - LLM bots will use fallback strategy");
            None
        };

        // Initialize LLM memories storage
        let llm_memories = Arc::new(RwLock::new(HashMap::new()));

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
        })
    }

    /// Get or create LLM bot memory for a specific bot
    pub async fn get_llm_memory(&self, bot_user_id: &str) -> Arc<RwLock<LlmBotMemory>> {
        let memories = self.llm_memories.read().await;
        if let Some(memory) = memories.get(bot_user_id) {
            return memory.clone();
        }
        drop(memories);

        // Create new memory
        let mut memory = LlmBotMemory::new(bot_user_id, None);
        if let Err(e) = memory.load().await {
            tracing::warn!("Failed to load LLM memory for {}: {}", bot_user_id, e);
        }

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
