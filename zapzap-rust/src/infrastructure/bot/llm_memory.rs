//! LLM Bot Memory
//!
//! Manages strategic memory for LLM bots - stores learned strategies and tracks decisions

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use tokio::fs;
use tracing::{debug, error, info, warn};

/// Strategy categories
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StrategyCategory {
    PlayStrategy,
    ZapzapTiming,
    DrawDecision,
    GoldenScore,
    OpponentReading,
}

impl std::fmt::Display for StrategyCategory {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StrategyCategory::PlayStrategy => write!(f, "play_strategy"),
            StrategyCategory::ZapzapTiming => write!(f, "zapzap_timing"),
            StrategyCategory::DrawDecision => write!(f, "draw_decision"),
            StrategyCategory::GoldenScore => write!(f, "golden_score"),
            StrategyCategory::OpponentReading => write!(f, "opponent_reading"),
        }
    }
}

impl StrategyCategory {
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "play_strategy" => Some(StrategyCategory::PlayStrategy),
            "zapzap_timing" => Some(StrategyCategory::ZapzapTiming),
            "draw_decision" => Some(StrategyCategory::DrawDecision),
            "golden_score" => Some(StrategyCategory::GoldenScore),
            "opponent_reading" => Some(StrategyCategory::OpponentReading),
            _ => None,
        }
    }
}

/// Limits for memory storage
const MAX_STRATEGIES: usize = 20;
const MAX_PER_CATEGORY: usize = 5;
const MAX_RECENT_DECISIONS: usize = 50;
const MAX_GAME_HISTORY: usize = 10;

/// Strategy entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Strategy {
    pub id: String,
    pub insight: String,
    pub category: StrategyCategory,
    pub confidence: f32,
    pub created_at: i64,
    pub source_context: StrategyContext,
    pub usage_count: u32,
}

/// Strategy source context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StrategyContext {
    pub party_id: Option<String>,
    pub round_number: Option<u32>,
    pub outcome: Option<String>,
}

impl Default for StrategyContext {
    fn default() -> Self {
        Self {
            party_id: None,
            round_number: None,
            outcome: None,
        }
    }
}

/// Decision tracking entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Decision {
    #[serde(rename = "type")]
    pub decision_type: String,
    pub details: DecisionDetails,
    pub timestamp: i64,
}

/// Decision details
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DecisionDetails {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cards: Option<Vec<u8>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hand_before: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hand_after: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub card_drawn: Option<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hand_value: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub success: Option<bool>,
}

impl Default for DecisionDetails {
    fn default() -> Self {
        Self {
            cards: None,
            hand_before: None,
            hand_after: None,
            source: None,
            card_drawn: None,
            hand_value: None,
            success: None,
        }
    }
}

/// Game history summary
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameSummary {
    pub party_id: String,
    pub won: bool,
    pub final_score: u16,
    pub rounds_played: u32,
    pub timestamp: i64,
}

/// Memory data structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryData {
    pub bot_user_id: String,
    pub created_at: i64,
    pub last_updated_at: i64,
    pub total_games_analyzed: u32,
    pub total_rounds_analyzed: u32,
    pub strategies: Vec<Strategy>,
    pub round_decisions: HashMap<String, Vec<Decision>>,
    pub game_history: Vec<GameSummary>,
}

impl MemoryData {
    fn new(bot_user_id: &str) -> Self {
        let now = chrono::Utc::now().timestamp_millis();
        Self {
            bot_user_id: bot_user_id.to_string(),
            created_at: now,
            last_updated_at: now,
            total_games_analyzed: 0,
            total_rounds_analyzed: 0,
            strategies: Vec::new(),
            round_decisions: HashMap::new(),
            game_history: Vec::new(),
        }
    }
}

/// LLM Bot Memory manager
pub struct LlmBotMemory {
    bot_user_id: String,
    base_dir: PathBuf,
    file_path: PathBuf,
    data: MemoryData,
    loaded: bool,
    dirty: bool,
}

impl LlmBotMemory {
    /// Create new memory manager for a bot
    pub fn new(bot_user_id: &str, base_dir: Option<PathBuf>) -> Self {
        let base_dir = base_dir.unwrap_or_else(|| {
            PathBuf::from(
                std::env::var("BOT_STRATEGIES_DIR")
                    .unwrap_or_else(|_| "data/bot-strategies".to_string()),
            )
        });
        let file_path = base_dir.join(format!("{}.json", bot_user_id));

        Self {
            bot_user_id: bot_user_id.to_string(),
            base_dir,
            file_path,
            data: MemoryData::new(bot_user_id),
            loaded: false,
            dirty: false,
        }
    }

    /// Load memory from file
    pub async fn load(&mut self) -> Result<(), std::io::Error> {
        // Ensure directory exists
        fs::create_dir_all(&self.base_dir).await?;

        match fs::read_to_string(&self.file_path).await {
            Ok(content) => {
                match serde_json::from_str(&content) {
                    Ok(data) => {
                        self.data = data;
                        self.loaded = true;
                        debug!(
                            "LlmBotMemory loaded: {} strategies",
                            self.data.strategies.len()
                        );
                    }
                    Err(e) => {
                        warn!("Failed to parse memory file, starting fresh: {}", e);
                        self.data = MemoryData::new(&self.bot_user_id);
                        self.loaded = true;
                    }
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                debug!("Memory file not found, starting fresh");
                self.data = MemoryData::new(&self.bot_user_id);
                self.loaded = true;
            }
            Err(e) => {
                error!("Failed to load memory: {}", e);
                self.data = MemoryData::new(&self.bot_user_id);
                self.loaded = true;
            }
        }

        Ok(())
    }

    /// Load memory synchronously (blocking)
    pub fn load_sync(&mut self) {
        use std::fs as sync_fs;

        // Ensure directory exists
        if let Err(e) = sync_fs::create_dir_all(&self.base_dir) {
            warn!("Failed to create directory: {}", e);
        }

        match sync_fs::read_to_string(&self.file_path) {
            Ok(content) => {
                match serde_json::from_str(&content) {
                    Ok(data) => {
                        self.data = data;
                        self.loaded = true;
                    }
                    Err(e) => {
                        warn!("Failed to parse memory file: {}", e);
                        self.data = MemoryData::new(&self.bot_user_id);
                        self.loaded = true;
                    }
                }
            }
            Err(_) => {
                self.data = MemoryData::new(&self.bot_user_id);
                self.loaded = true;
            }
        }
    }

    /// Save memory to file
    pub async fn save(&mut self) -> Result<(), std::io::Error> {
        if !self.dirty {
            return Ok(());
        }

        // Ensure directory exists
        fs::create_dir_all(&self.base_dir).await?;

        self.data.last_updated_at = chrono::Utc::now().timestamp_millis();

        // Write atomically
        let temp_path = self.file_path.with_extension("tmp");
        let content = serde_json::to_string_pretty(&self.data)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;

        fs::write(&temp_path, &content).await?;
        fs::rename(&temp_path, &self.file_path).await?;

        self.dirty = false;
        debug!(
            "LlmBotMemory saved: {} strategies",
            self.data.strategies.len()
        );

        Ok(())
    }

    /// Check if bot has any strategies
    pub fn has_strategies(&self) -> bool {
        !self.data.strategies.is_empty()
    }

    /// Get top strategies by confidence
    pub fn get_top_strategies(&self, limit: usize) -> Vec<&Strategy> {
        let mut strategies: Vec<&Strategy> = self.data.strategies.iter().collect();
        strategies.sort_by(|a, b| b.confidence.partial_cmp(&a.confidence).unwrap());
        strategies.truncate(limit);
        strategies
    }

    /// Get all strategies
    pub fn get_all_strategies(&self) -> &[Strategy] {
        &self.data.strategies
    }

    /// Add a new strategy
    pub fn add_strategy(
        &mut self,
        insight: &str,
        category: StrategyCategory,
        context: StrategyContext,
        confidence: f32,
    ) -> Option<&Strategy> {
        // Check for duplicate insights
        let normalized = insight.to_lowercase();
        if self.data.strategies.iter().any(|s| s.insight.to_lowercase() == normalized) {
            debug!("Duplicate strategy ignored: {}", insight);
            return None;
        }

        let strategy = Strategy {
            id: format!(
                "strat_{}_{}",
                chrono::Utc::now().timestamp_millis(),
                rand::random::<u32>() % 1000000
            ),
            insight: insight.chars().take(150).collect(),
            category,
            confidence: confidence.clamp(0.0, 1.0),
            created_at: chrono::Utc::now().timestamp_millis(),
            source_context: context,
            usage_count: 0,
        };

        self.data.strategies.push(strategy);
        self.dirty = true;

        // Prune if needed
        self.prune();

        info!("Strategy added: {} ({})", insight, category);

        self.data.strategies.last()
    }

    /// Update strategy confidence based on outcome
    pub fn update_confidence(&mut self, strategy_id: &str, success: bool) {
        if let Some(strategy) = self.data.strategies.iter_mut().find(|s| s.id == strategy_id) {
            let adjustment = if success { 0.05 } else { -0.05 };
            strategy.confidence = (strategy.confidence + adjustment).clamp(0.0, 1.0);
            strategy.usage_count += 1;
            self.dirty = true;
        }
    }

    /// Track a decision made during gameplay
    pub fn track_decision(&mut self, round_number: u32, decision: Decision) {
        let round_key = round_number.to_string();
        let decisions = self.data.round_decisions.entry(round_key).or_default();

        decisions.push(decision);
        self.dirty = true;

        // Limit decisions per round
        if decisions.len() > MAX_RECENT_DECISIONS {
            let excess = decisions.len() - MAX_RECENT_DECISIONS;
            decisions.drain(0..excess);
        }
    }

    /// Get decisions for a specific round
    pub fn get_decisions_for_round(&self, round_number: u32) -> &[Decision] {
        self.data
            .round_decisions
            .get(&round_number.to_string())
            .map(|v| v.as_slice())
            .unwrap_or(&[])
    }

    /// Clear decisions for a round
    pub fn clear_round_decisions(&mut self, round_number: u32) {
        self.data.round_decisions.remove(&round_number.to_string());
        self.dirty = true;
    }

    /// Clear all decisions
    pub fn clear_all_decisions(&mut self) {
        self.data.round_decisions.clear();
        self.dirty = true;
    }

    /// Increment games analyzed counter
    pub fn increment_games_analyzed(&mut self) {
        self.data.total_games_analyzed += 1;
        self.dirty = true;
    }

    /// Increment rounds analyzed counter
    pub fn increment_rounds_analyzed(&mut self) {
        self.data.total_rounds_analyzed += 1;
        self.dirty = true;
    }

    /// Add game to history
    pub fn add_game_history(&mut self, summary: GameSummary) {
        self.data.game_history.push(summary);
        self.dirty = true;

        // Keep only recent games
        if self.data.game_history.len() > MAX_GAME_HISTORY {
            let excess = self.data.game_history.len() - MAX_GAME_HISTORY;
            self.data.game_history.drain(0..excess);
        }
    }

    /// Prune strategies to stay within limits
    fn prune(&mut self) {
        // Group by category
        let mut by_category: HashMap<StrategyCategory, Vec<Strategy>> = HashMap::new();
        for strategy in self.data.strategies.drain(..) {
            by_category
                .entry(strategy.category)
                .or_default()
                .push(strategy);
        }

        // Keep only top N per category
        let mut kept = Vec::new();
        for (_, mut strategies) in by_category {
            strategies.sort_by(|a, b| b.confidence.partial_cmp(&a.confidence).unwrap());
            strategies.truncate(MAX_PER_CATEGORY);
            kept.extend(strategies);
        }

        // If still over total limit, remove lowest confidence
        if kept.len() > MAX_STRATEGIES {
            kept.sort_by(|a, b| b.confidence.partial_cmp(&a.confidence).unwrap());
            kept.truncate(MAX_STRATEGIES);
        }

        self.data.strategies = kept;
        self.dirty = true;
    }

    /// Get memory statistics
    pub fn get_stats(&self) -> MemoryStats {
        let mut by_category: HashMap<StrategyCategory, usize> = HashMap::new();
        for s in &self.data.strategies {
            *by_category.entry(s.category).or_default() += 1;
        }

        let avg_confidence = if self.data.strategies.is_empty() {
            0.0
        } else {
            self.data.strategies.iter().map(|s| s.confidence).sum::<f32>()
                / self.data.strategies.len() as f32
        };

        MemoryStats {
            total_strategies: self.data.strategies.len(),
            total_games_analyzed: self.data.total_games_analyzed,
            total_rounds_analyzed: self.data.total_rounds_analyzed,
            strategies_by_category: by_category,
            average_confidence: avg_confidence,
        }
    }
}

/// Memory statistics
#[derive(Debug, Clone)]
pub struct MemoryStats {
    pub total_strategies: usize,
    pub total_games_analyzed: u32,
    pub total_rounds_analyzed: u32,
    pub strategies_by_category: HashMap<StrategyCategory, usize>,
    pub average_confidence: f32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add_strategy() {
        let mut memory = LlmBotMemory::new("test_bot", Some(PathBuf::from("/tmp/test")));
        memory.loaded = true;

        let result = memory.add_strategy(
            "Test insight",
            StrategyCategory::PlayStrategy,
            StrategyContext::default(),
            0.5,
        );

        assert!(result.is_some());
        assert_eq!(memory.data.strategies.len(), 1);
    }

    #[test]
    fn test_duplicate_prevention() {
        let mut memory = LlmBotMemory::new("test_bot", Some(PathBuf::from("/tmp/test")));
        memory.loaded = true;

        memory.add_strategy(
            "Test insight",
            StrategyCategory::PlayStrategy,
            StrategyContext::default(),
            0.5,
        );

        // Same insight (case insensitive)
        let result = memory.add_strategy(
            "TEST INSIGHT",
            StrategyCategory::PlayStrategy,
            StrategyContext::default(),
            0.5,
        );

        assert!(result.is_none());
        assert_eq!(memory.data.strategies.len(), 1);
    }

    #[test]
    fn test_track_decision() {
        let mut memory = LlmBotMemory::new("test_bot", Some(PathBuf::from("/tmp/test")));
        memory.loaded = true;

        let decision = Decision {
            decision_type: "play".to_string(),
            details: DecisionDetails {
                cards: Some(vec![1, 2, 3]),
                hand_before: Some(15),
                hand_after: Some(10),
                ..Default::default()
            },
            timestamp: chrono::Utc::now().timestamp_millis(),
        };

        memory.track_decision(1, decision);

        let decisions = memory.get_decisions_for_round(1);
        assert_eq!(decisions.len(), 1);
    }
}
