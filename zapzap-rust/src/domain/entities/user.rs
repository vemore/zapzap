use serde::{Deserialize, Serialize};

/// User type enumeration
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum UserType {
    Human,
    Bot,
}

impl UserType {
    pub fn as_str(&self) -> &'static str {
        match self {
            UserType::Human => "human",
            UserType::Bot => "bot",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "human" => Some(UserType::Human),
            "bot" => Some(UserType::Bot),
            _ => None,
        }
    }
}

/// Bot difficulty levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BotDifficulty {
    Easy,
    Medium,
    Hard,
    HardVince,
    Thibot,
    Drl,
    Llm,
    Ml,
}

impl BotDifficulty {
    pub fn as_str(&self) -> &'static str {
        match self {
            BotDifficulty::Easy => "easy",
            BotDifficulty::Medium => "medium",
            BotDifficulty::Hard => "hard",
            BotDifficulty::HardVince => "hard_vince",
            BotDifficulty::Thibot => "thibot",
            BotDifficulty::Drl => "drl",
            BotDifficulty::Llm => "llm",
            BotDifficulty::Ml => "ml",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "easy" => Some(BotDifficulty::Easy),
            "medium" => Some(BotDifficulty::Medium),
            "hard" => Some(BotDifficulty::Hard),
            "hard_vince" => Some(BotDifficulty::HardVince),
            "thibot" => Some(BotDifficulty::Thibot),
            "drl" => Some(BotDifficulty::Drl),
            "llm" => Some(BotDifficulty::Llm),
            "ml" => Some(BotDifficulty::Ml),
            _ => None,
        }
    }
}

/// User entity
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct User {
    pub id: String,
    pub username: String,
    #[serde(skip_serializing)]
    pub password_hash: Option<String>,
    pub user_type: UserType,
    pub bot_difficulty: Option<BotDifficulty>,
    pub is_admin: bool,
    pub google_id: Option<String>,
    pub email: Option<String>,
    pub last_login_at: Option<i64>,
    pub total_play_time_seconds: i64,
    pub created_at: i64,
    pub updated_at: i64,
}

impl User {
    /// Create a new human user
    pub fn new_human(id: String, username: String, password_hash: String) -> Self {
        let now = chrono::Utc::now().timestamp();
        Self {
            id,
            username,
            password_hash: Some(password_hash),
            user_type: UserType::Human,
            bot_difficulty: None,
            is_admin: false,
            google_id: None,
            email: None,
            last_login_at: None,
            total_play_time_seconds: 0,
            created_at: now,
            updated_at: now,
        }
    }

    /// Create a new bot user
    pub fn new_bot(id: String, username: String, difficulty: BotDifficulty) -> Self {
        let now = chrono::Utc::now().timestamp();
        Self {
            id,
            username,
            password_hash: None,
            user_type: UserType::Bot,
            bot_difficulty: Some(difficulty),
            is_admin: false,
            google_id: None,
            email: None,
            last_login_at: None,
            total_play_time_seconds: 0,
            created_at: now,
            updated_at: now,
        }
    }

    /// Check if user is a bot
    pub fn is_bot(&self) -> bool {
        self.user_type == UserType::Bot
    }

    /// Check if user is an admin
    pub fn is_admin_user(&self) -> bool {
        self.is_admin
    }

    /// Convert to public object (safe for API responses)
    pub fn to_public(&self) -> PublicUser {
        PublicUser {
            id: self.id.clone(),
            username: self.username.clone(),
            user_type: self.user_type,
            bot_difficulty: self.bot_difficulty,
            is_admin: self.is_admin,
            created_at: self.created_at,
        }
    }
}

/// Public user representation (safe for API responses)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PublicUser {
    pub id: String,
    pub username: String,
    pub user_type: UserType,
    pub bot_difficulty: Option<BotDifficulty>,
    pub is_admin: bool,
    pub created_at: i64,
}
