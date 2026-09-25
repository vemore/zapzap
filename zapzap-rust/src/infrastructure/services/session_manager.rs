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

/// The connected users, and how many event streams each has open
#[derive(Default)]
struct Sessions {
    sessions: HashMap<String, UserSession>,
    /// Open event streams per user. A user is online while at least one is open (two
    /// tabs, or a reconnection whose new stream opens before the old one closes), as
    /// Node's `SessionManager.streams`.
    streams: HashMap<String, usize>,
}

/// Session manager for tracking connected users
pub struct SessionManager {
    inner: RwLock<Sessions>,
}

impl SessionManager {
    pub fn new() -> Self {
        Self {
            inner: RwLock::new(Sessions::default()),
        }
    }

    fn read(&self) -> std::sync::RwLockReadGuard<'_, Sessions> {
        self.inner.read().unwrap_or_else(|e| e.into_inner())
    }

    fn write(&self) -> std::sync::RwLockWriteGuard<'_, Sessions> {
        self.inner.write().unwrap_or_else(|e| e.into_inner())
    }

    /// Register one event stream of a user. Returns the new session on the user's first
    /// stream, `None` when the user was already connected (the session, its status and
    /// party included, is kept as is).
    pub fn connect(&self, user_id: &str, username: &str) -> Option<UserSession> {
        let mut inner = self.write();
        let open = inner.streams.entry(user_id.to_string()).or_insert(0);
        *open += 1;
        if *open > 1 && inner.sessions.contains_key(user_id) {
            return None;
        }
        let session = UserSession {
            user_id: user_id.to_string(),
            username: username.to_string(),
            status: SessionStatus::Lobby,
            party_id: None,
            connected_at: chrono::Utc::now().timestamp(),
        };
        inner.sessions.insert(user_id.to_string(), session.clone());
        Some(session)
    }

    /// Unregister one event stream of a user. Returns the removed session when that was
    /// the user's last stream, `None` while another one is still open or if not found.
    pub fn disconnect(&self, user_id: &str) -> Option<UserSession> {
        let mut inner = self.write();
        let open = inner.streams.get(user_id).copied().unwrap_or(1);
        if open > 1 {
            inner.streams.insert(user_id.to_string(), open - 1);
            return None;
        }
        inner.streams.remove(user_id);
        inner.sessions.remove(user_id)
    }

    /// Update user status
    pub fn update_status(&self, user_id: &str, status: SessionStatus, party_id: Option<String>) {
        if let Some(session) = self.write().sessions.get_mut(user_id) {
            session.status = status;
            session.party_id = party_id;
        }
    }

    /// Check if user is connected
    pub fn is_connected(&self, user_id: &str) -> bool {
        self.read().sessions.contains_key(user_id)
    }

    /// Get connected users (most recent first)
    pub fn get_connected_users(&self, limit: usize) -> Vec<UserSession> {
        let mut users: Vec<_> = self.read().sessions.values().cloned().collect();
        users.sort_by_key(|u| std::cmp::Reverse(u.connected_at));
        users.truncate(limit);
        users
    }

    /// Get user session
    pub fn get_session(&self, user_id: &str) -> Option<UserSession> {
        self.read().sessions.get(user_id).cloned()
    }

    /// Get all users in a party
    pub fn get_party_users(&self, party_id: &str) -> Vec<UserSession> {
        self.read()
            .sessions
            .values()
            .filter(|s| s.party_id.as_deref() == Some(party_id))
            .cloned()
            .collect()
    }

    /// Count connected users
    pub fn count(&self) -> usize {
        self.read().sessions.len()
    }
}

impl Default for SessionManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_user_stays_connected_until_the_last_stream_closes() {
        let sessions = SessionManager::new();
        assert!(sessions.connect("u1", "alice").is_some());
        sessions.update_status("u1", SessionStatus::Game, Some("p1".into()));

        // A second stream (another tab, a reconnection) is no arrival, and keeps the status
        assert!(sessions.connect("u1", "alice").is_none());
        let kept = sessions.get_session("u1").unwrap();
        assert_eq!(kept.status.as_str(), "game");
        assert_eq!(kept.party_id.as_deref(), Some("p1"));

        // The first close is no departure; the last one is
        assert!(sessions.disconnect("u1").is_none());
        assert!(sessions.is_connected("u1"));
        assert_eq!(sessions.disconnect("u1").unwrap().username, "alice");
        assert!(!sessions.is_connected("u1"));

        // A stray close changes nothing, and the next stream is an arrival again
        assert!(sessions.disconnect("u1").is_none());
        assert!(sessions.connect("u1", "alice").is_some());
        assert_eq!(sessions.count(), 1);
    }
}
