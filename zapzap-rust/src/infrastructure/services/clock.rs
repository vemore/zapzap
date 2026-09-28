//! The time the turn clock reads (GAME_RULES.md "Turn Time Limit"): the deadline a
//! game-state write stamps and the time the turn timer compares it with come from one
//! `Clock`, the system's in production, one a test sets by hand (`ManualClock`), so that a
//! test passes a 30 s deadline without waiting for it.

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

/// Now, in Unix milliseconds
pub trait Clock: Send + Sync {
    fn now_millis(&self) -> u64;
}

/// The system clock
#[derive(Debug, Default, Clone, Copy)]
pub struct SystemClock;

impl Clock for SystemClock {
    fn now_millis(&self) -> u64 {
        crate::domain::value_objects::now_millis()
    }
}

/// A clock that stands still until it is moved on (`advance`): the tests' clock
#[derive(Debug)]
pub struct ManualClock {
    now: AtomicU64,
}

impl ManualClock {
    /// A clock standing at the system's time
    pub fn new() -> Self {
        Self::at(SystemClock.now_millis())
    }

    /// A clock standing at `now` (Unix milliseconds)
    pub fn at(now: u64) -> Self {
        Self {
            now: AtomicU64::new(now),
        }
    }

    /// Move the clock on by `by`
    pub fn advance(&self, by: Duration) {
        self.now.fetch_add(by.as_millis() as u64, Ordering::SeqCst);
    }
}

impl Default for ManualClock {
    fn default() -> Self {
        Self::new()
    }
}

impl Clock for ManualClock {
    fn now_millis(&self) -> u64 {
        self.now.load(Ordering::SeqCst)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_manual_clock_moves_only_when_advanced() {
        let clock = ManualClock::at(1_000);
        assert_eq!(clock.now_millis(), 1_000);
        clock.advance(Duration::from_secs(30));
        assert_eq!(clock.now_millis(), 31_000);
    }
}
