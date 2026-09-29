//! An in-memory rate limit: at most `per_key` accepted requests per key (a client address)
//! and `global` in all over a sliding `window`. The backend is one process, so memory is
//! enough; a restart forgets the counts. Only accepted requests count, so the log holds
//! at most `global` instants and a refused client does not push its own wait further; a
//! request that failed after it was counted gives its slot back (`release`).

use std::collections::{HashMap, VecDeque};
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Guest accounts one client address may create per `GUEST_WINDOW`
pub const GUEST_PER_IP: usize = 5;
/// Guest accounts the server creates per `GUEST_WINDOW`, every address together: the
/// backstop when addresses cannot be told apart, or are many
pub const GUEST_GLOBAL: usize = 300;
pub const GUEST_WINDOW: Duration = Duration::from_secs(60 * 60);

#[derive(Default)]
struct Log {
    /// Every accepted request of the window, oldest first
    all: VecDeque<Instant>,
    /// The same, by key
    by_key: HashMap<String, VecDeque<Instant>>,
}

pub struct RateLimiter {
    per_key: usize,
    global: usize,
    window: Duration,
    log: Mutex<Log>,
}

impl RateLimiter {
    pub fn new(per_key: usize, global: usize, window: Duration) -> Self {
        Self {
            per_key,
            global,
            window,
            log: Mutex::new(Log::default()),
        }
    }

    /// The limit of `POST /api/auth/guest`
    pub fn guest() -> Self {
        Self::new(GUEST_PER_IP, GUEST_GLOBAL, GUEST_WINDOW)
    }

    /// Whether a request of `key` may go on now; if so it is counted
    pub fn try_acquire(&self, key: &str) -> bool {
        self.try_acquire_at(key, Instant::now())
    }

    pub fn try_acquire_at(&self, key: &str, now: Instant) -> bool {
        let mut log = self.log.lock().unwrap_or_else(|e| e.into_inner());
        let window = self.window;
        let expired = |at: &Instant| now.saturating_duration_since(*at) >= window;
        while log.all.front().is_some_and(expired) {
            log.all.pop_front();
        }
        log.by_key.retain(|_, times| {
            while times.front().is_some_and(expired) {
                times.pop_front();
            }
            !times.is_empty()
        });

        let used = log.by_key.get(key).map_or(0, VecDeque::len);
        if used >= self.per_key || log.all.len() >= self.global {
            return false;
        }
        log.all.push_back(now);
        log.by_key
            .entry(key.to_string())
            .or_default()
            .push_back(now);
        true
    }

    /// Give back the last slot `key` acquired: the request it counted failed and created
    /// nothing
    pub fn release(&self, key: &str) {
        let mut log = self.log.lock().unwrap_or_else(|e| e.into_inner());
        let Some(times) = log.by_key.get_mut(key) else {
            return;
        };
        let Some(at) = times.pop_back() else {
            return;
        };
        if times.is_empty() {
            log.by_key.remove(key);
        }
        if let Some(i) = log.all.iter().rposition(|t| *t == at) {
            log.all.remove(i);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_key_has_its_quota_and_all_share_the_global_one() {
        let limiter = RateLimiter::new(2, 3, Duration::from_secs(60));
        let t = Instant::now();
        assert!(limiter.try_acquire_at("a", t));
        assert!(limiter.try_acquire_at("a", t));
        assert!(!limiter.try_acquire_at("a", t), "a's quota");
        assert!(limiter.try_acquire_at("b", t));
        assert!(!limiter.try_acquire_at("c", t), "the global quota");
    }

    #[test]
    fn the_window_slides() {
        let limiter = RateLimiter::new(1, 10, Duration::from_secs(60));
        let t = Instant::now();
        assert!(limiter.try_acquire_at("a", t));
        assert!(!limiter.try_acquire_at("a", t + Duration::from_secs(59)));
        assert!(limiter.try_acquire_at("a", t + Duration::from_secs(60)));
        // A refused request is not counted: it does not push the next one further
        assert!(!limiter.try_acquire_at("a", t + Duration::from_secs(90)));
        assert!(limiter.try_acquire_at("a", t + Duration::from_secs(120)));
    }

    #[test]
    fn a_released_slot_is_given_back_to_the_key_and_the_global_quota() {
        let limiter = RateLimiter::new(1, 2, Duration::from_secs(60));
        let t = Instant::now();
        assert!(limiter.try_acquire_at("a", t));
        limiter.release("a");
        assert!(limiter.try_acquire_at("a", t));
        assert!(limiter.try_acquire_at("b", t));
        assert!(!limiter.try_acquire_at("c", t), "the global quota is full");
        limiter.release("b");
        assert!(limiter.try_acquire_at("c", t));
        // Nothing to give back: no effect
        limiter.release("nobody");
        assert!(!limiter.try_acquire_at("d", t));
    }

    #[test]
    fn keys_whose_requests_expired_are_forgotten() {
        let limiter = RateLimiter::new(1, 10, Duration::from_secs(60));
        let t = Instant::now();
        for key in ["a", "b", "c"] {
            assert!(limiter.try_acquire_at(key, t));
        }
        assert!(limiter.try_acquire_at("d", t + Duration::from_secs(61)));
        let log = limiter.log.lock().unwrap();
        assert_eq!(log.by_key.len(), 1);
        assert_eq!(log.all.len(), 1);
    }
}
