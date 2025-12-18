//! Global trace configuration for diagnostic output
//!
//! This module provides a configurable tracing system for debugging DRL training.
//! Trace levels can be enabled via command line flags (--trace=game,training,etc.)

use std::sync::atomic::{AtomicBool, Ordering};

/// Global trace flags (atomic for thread safety)
pub static TRACE_GAME: AtomicBool = AtomicBool::new(false);
pub static TRACE_BUFFER: AtomicBool = AtomicBool::new(false);
pub static TRACE_TRAINING: AtomicBool = AtomicBool::new(false);
pub static TRACE_WEIGHTS: AtomicBool = AtomicBool::new(false);
pub static TRACE_FEATURES: AtomicBool = AtomicBool::new(false);

/// Trace levels for different components
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TraceLevel {
    /// Game/transition collection: decisions, actions, rewards
    Game,
    /// Replay buffer: sampling stats, priority distribution
    Buffer,
    /// Training step: Q-values, TD errors, loss, gradients
    Training,
    /// Weight synchronization: DuelingDQN <-> FastDQN
    Weights,
    /// Feature extraction: validation, NaN/Inf checks
    Features,
}

impl TraceLevel {
    /// Get the name of this trace level
    pub fn name(self) -> &'static str {
        match self {
            TraceLevel::Game => "GAME",
            TraceLevel::Buffer => "BUFFER",
            TraceLevel::Training => "TRAIN",
            TraceLevel::Weights => "WEIGHTS",
            TraceLevel::Features => "FEATURES",
        }
    }
}

/// Check if a trace level is enabled
#[inline]
pub fn is_trace_enabled(level: TraceLevel) -> bool {
    match level {
        TraceLevel::Game => TRACE_GAME.load(Ordering::Relaxed),
        TraceLevel::Buffer => TRACE_BUFFER.load(Ordering::Relaxed),
        TraceLevel::Training => TRACE_TRAINING.load(Ordering::Relaxed),
        TraceLevel::Weights => TRACE_WEIGHTS.load(Ordering::Relaxed),
        TraceLevel::Features => TRACE_FEATURES.load(Ordering::Relaxed),
    }
}

/// Set trace configuration
pub fn set_trace_flags(game: bool, buffer: bool, training: bool, weights: bool, features: bool) {
    TRACE_GAME.store(game, Ordering::SeqCst);
    TRACE_BUFFER.store(buffer, Ordering::SeqCst);
    TRACE_TRAINING.store(training, Ordering::SeqCst);
    TRACE_WEIGHTS.store(weights, Ordering::SeqCst);
    TRACE_FEATURES.store(features, Ordering::SeqCst);
}

/// Check if any trace is enabled
#[inline]
pub fn any_trace_enabled() -> bool {
    TRACE_GAME.load(Ordering::Relaxed)
        || TRACE_BUFFER.load(Ordering::Relaxed)
        || TRACE_TRAINING.load(Ordering::Relaxed)
        || TRACE_WEIGHTS.load(Ordering::Relaxed)
        || TRACE_FEATURES.load(Ordering::Relaxed)
}

/// Macro for conditional tracing
/// Usage: trace_log!(TraceLevel::Game, "message {} {}", arg1, arg2);
#[macro_export]
macro_rules! trace_log {
    ($level:expr, $($arg:tt)*) => {
        if $crate::trace_config::is_trace_enabled($level) {
            eprintln!("[{}] {}", $level.name(), format!($($arg)*));
        }
    };
}

/// Macro for conditional tracing with custom prefix
/// Usage: trace_log_prefix!(TraceLevel::Game, "CUSTOM", "message {} {}", arg1, arg2);
#[macro_export]
macro_rules! trace_log_prefix {
    ($level:expr, $prefix:expr, $($arg:tt)*) => {
        if $crate::trace_config::is_trace_enabled($level) {
            eprintln!("[{}] {}", $prefix, format!($($arg)*));
        }
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_trace_level_names() {
        assert_eq!(TraceLevel::Game.name(), "GAME");
        assert_eq!(TraceLevel::Buffer.name(), "BUFFER");
        assert_eq!(TraceLevel::Training.name(), "TRAIN");
        assert_eq!(TraceLevel::Weights.name(), "WEIGHTS");
        assert_eq!(TraceLevel::Features.name(), "FEATURES");
    }

    #[test]
    fn test_set_trace_flags() {
        // Reset all flags
        set_trace_flags(false, false, false, false, false);
        assert!(!is_trace_enabled(TraceLevel::Game));
        assert!(!is_trace_enabled(TraceLevel::Training));

        // Enable some flags
        set_trace_flags(true, false, true, false, false);
        assert!(is_trace_enabled(TraceLevel::Game));
        assert!(!is_trace_enabled(TraceLevel::Buffer));
        assert!(is_trace_enabled(TraceLevel::Training));
        assert!(!is_trace_enabled(TraceLevel::Weights));
        assert!(!is_trace_enabled(TraceLevel::Features));

        // Reset
        set_trace_flags(false, false, false, false, false);
    }

    #[test]
    fn test_any_trace_enabled() {
        set_trace_flags(false, false, false, false, false);
        assert!(!any_trace_enabled());

        set_trace_flags(false, true, false, false, false);
        assert!(any_trace_enabled());

        set_trace_flags(false, false, false, false, false);
    }
}
