use std::collections::HashMap;
use std::sync::RwLock;

/// User session status
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionStatus {
    Lobby,
    Party,
    Game,
}

impl SessionStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            SessionStatus::Lobby => "lobby",
            SessionStatus::Party => "party",
            SessionStatus::Game => "game",
        }
    }
}

/// Connected user session
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UserSession {
    pub user_id: String,
    pub username: String,
    pub status: SessionStatus,
    pub party_id: Option<String>,
    pub connected_at: i64,
}

/// Session manager for tracking connected users
pub struct SessionManager {
    sessions: RwLock<HashMap<String, UserSession>>,
}

impl SessionManager {
    pub fn new() -> Self {
        Self {
            sessions: RwLock::new(HashMap::new()),
        }
    }

    /// Connect a user
    pub fn connect(&self, user_id: &str, username: &str) -> UserSession {
        let session = UserSession {
            user_id: user_id.to_string(),
            username: username.to_string(),
            status: SessionStatus::Lobby,
            party_id: None,
            connected_at: chrono::Utc::now().timestamp(),
        };

        let mut sessions = self.sessions.write().unwrap();
        sessions.insert(user_id.to_string(), session.clone());
        session
    }

    /// Disconnect a user
    pub fn disconnect(&self, user_id: &str) {
        let mut sessions = self.sessions.write().unwrap();
        sessions.remove(user_id);
    }

    /// Update user status
    pub fn update_status(&self, user_id: &str, status: SessionStatus, party_id: Option<String>) {
        let mut sessions = self.sessions.write().unwrap();
        if let Some(session) = sessions.get_mut(user_id) {
            session.status = status;
            session.party_id = party_id;
        }
    }

    /// Check if user is connected
    pub fn is_connected(&self, user_id: &str) -> bool {
        let sessions = self.sessions.read().unwrap();
        sessions.contains_key(user_id)
    }

    /// Get connected users (most recent first)
    pub fn get_connected_users(&self, limit: usize) -> Vec<UserSession> {
        let sessions = self.sessions.read().unwrap();
        let mut users: Vec<_> = sessions.values().cloned().collect();
        users.sort_by(|a, b| b.connected_at.cmp(&a.connected_at));
        users.truncate(limit);
        users
    }

    /// Get user session
    pub fn get_session(&self, user_id: &str) -> Option<UserSession> {
        let sessions = self.sessions.read().unwrap();
        sessions.get(user_id).cloned()
    }

    /// Get all users in a party
    pub fn get_party_users(&self, party_id: &str) -> Vec<UserSession> {
        let sessions = self.sessions.read().unwrap();
        sessions
            .values()
            .filter(|s| s.party_id.as_deref() == Some(party_id))
            .cloned()
            .collect()
    }

    /// Count connected users
    pub fn count(&self) -> usize {
        let sessions = self.sessions.read().unwrap();
        sessions.len()
    }
}

impl Default for SessionManager {
    fn default() -> Self {
        Self::new()
    }
}
