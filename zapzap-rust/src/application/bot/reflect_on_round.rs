//! ReflectOnRound Use Case
//!
//! Triggers LLM reflection after each round to learn from decisions

use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, error, info};

use crate::infrastructure::bot::llm_memory::{
    Decision, LlmBotMemory, StrategyCategory, StrategyContext,
};
use crate::infrastructure::bot::strategies::LlmBotStrategy;
use crate::infrastructure::services::LlmService;

/// Round outcome information
#[derive(Debug, Clone)]
pub struct RoundOutcome {
    pub won: bool,
    pub counteracted: bool,
    pub score_change: i16,
    pub hand_points: u16,
    pub final_hand: Vec<u8>,
    pub is_golden_score: bool,
}

/// ReflectOnRound input
pub struct ReflectOnRoundInput {
    pub bot_user_id: String,
    pub party_id: String,
    pub round_number: u32,
    pub outcome: RoundOutcome,
}

/// ReflectOnRound output
#[derive(Debug)]
pub struct ReflectOnRoundOutput {
    pub success: bool,
    pub insights_generated: usize,
    pub insights: Vec<String>,
    pub reason: Option<String>,
}

/// ReflectOnRound use case
pub struct ReflectOnRound {
    llm_service: Arc<dyn LlmService>,
}

impl ReflectOnRound {
    pub fn new(llm_service: Arc<dyn LlmService>) -> Self {
        Self { llm_service }
    }

    /// Execute round reflection
    pub async fn execute(
        &self,
        input: ReflectOnRoundInput,
        memory: Arc<RwLock<LlmBotMemory>>,
    ) -> ReflectOnRoundOutput {
        // The round's decisions are copied out under a read lock: the LLM call below can
        // take the service timeout, and the bot's next decisions need the memory meanwhile
        let decisions = memory
            .read()
            .await
            .get_decisions_for_round(&input.party_id, input.round_number)
            .to_vec();

        if decisions.is_empty() {
            debug!(
                "ReflectOnRound skipped - no decisions tracked for round {}",
                input.round_number
            );
            return ReflectOnRoundOutput {
                success: false,
                insights_generated: 0,
                insights: Vec::new(),
                reason: Some("no_decisions".to_string()),
            };
        }

        // Build reflection prompt
        let system_prompt = Self::build_system_prompt();
        let user_prompt =
            Self::build_reflection_prompt(input.round_number, &input.outcome, &decisions);

        // Call LLM for reflection, no lock held
        match self.llm_service.invoke(&system_prompt, &user_prompt).await {
            Ok(response) => {
                // Parse insights from response
                let insights = Self::parse_insights(&response);

                let mut memory_guard = memory.write().await;
                for insight in &insights {
                    let context = StrategyContext {
                        party_id: Some(input.party_id.clone()),
                        round_number: Some(input.round_number),
                        outcome: Some(if input.outcome.won { "won" } else { "lost" }.to_string()),
                    };

                    memory_guard.add_strategy(&insight.text, insight.category, context, 0.5);
                }

                // Clear round decisions and increment counter
                memory_guard.clear_round_decisions(&input.party_id, input.round_number);
                memory_guard.increment_rounds_analyzed();

                // An unwritable directory keeps the insights in memory (it warns once)
                memory_guard.save_or_keep().await;
                drop(memory_guard);

                info!(
                    "Round reflection completed: {} insights generated for round {}",
                    insights.len(),
                    input.round_number
                );

                ReflectOnRoundOutput {
                    success: true,
                    insights_generated: insights.len(),
                    insights: insights.iter().map(|i| i.text.clone()).collect(),
                    reason: None,
                }
            }
            Err(e) => {
                error!("ReflectOnRound failed: {}", e);
                ReflectOnRoundOutput {
                    success: false,
                    insights_generated: 0,
                    insights: Vec::new(),
                    reason: Some(e.to_string()),
                }
            }
        }
    }

    /// Build system prompt for reflection: the play prompt's rules and card notation, so
    /// that an insight reads the same when the play prompt quotes it back
    fn build_system_prompt() -> String {
        format!(
            r#"You are an expert ZapZap player looking back on your own decisions to play better.

{}

## Your task
Read one round's decisions and draw at most one strategic insight from them.

## Answer
- A new insight: one line, [category] insight (100 characters at most)
- No new insight: NO_NEW_INSIGHTS

Categories:
- play_strategy: which cards to play
- zapzap_timing: when to call ZapZap
- draw_decision: deck or played cards
- golden_score: the two-player final round

Examples:
[play_strategy] Shedding J, Q and K first lowers the hand fastest
[zapzap_timing] Calling ZapZap at 5 when opponents hold 2-3 cards is risky
[draw_decision] Taking a joker from the played cards always pays

Be concise and actionable. One insight at most."#,
            LlmBotStrategy::rules_text()
        )
    }

    /// Build reflection prompt with round context
    fn build_reflection_prompt(
        round_number: u32,
        outcome: &RoundOutcome,
        decisions: &[Decision],
    ) -> String {
        let mut lines = vec![
            format!("## Round {} summary", round_number),
            format!("- Result: {}", Self::outcome_to_text(outcome)),
            format!(
                "- Points this round: {}{}",
                if outcome.score_change >= 0 { "+" } else { "" },
                outcome.score_change
            ),
            format!("- Final hand value: {} points", outcome.hand_points),
            format!(
                "- Final hand: {}",
                LlmBotStrategy::cards_to_names(&outcome.final_hand)
            ),
        ];

        lines.push(String::new());
        lines.push("## Your decisions this round".to_string());

        for decision in decisions {
            lines.push(Self::decision_to_text(decision));
        }

        if outcome.is_golden_score {
            lines.push(String::new());
            lines.push("## Context: Golden Score (two players left)".to_string());
        }

        lines.push(String::new());
        lines.push("## Analysis".to_string());
        lines.push("Which decision weighed most on this result?".to_string());
        lines.push("Is there a pattern worth keeping for the next games?".to_string());

        lines.join("\n")
    }

    /// Convert outcome to readable text
    fn outcome_to_text(outcome: &RoundOutcome) -> &'static str {
        if outcome.counteracted {
            "COUNTERACTED (your ZapZap failed)"
        } else if outcome.won {
            "WON (lowest hand, or a ZapZap that held)"
        } else {
            "LOST (hand too high)"
        }
    }

    /// Convert decision to readable text
    fn decision_to_text(decision: &Decision) -> String {
        let d = &decision.details;

        match decision.decision_type.as_str() {
            "play" => {
                let cards = d
                    .cards
                    .as_ref()
                    .map(|c| LlmBotStrategy::cards_to_names(c))
                    .unwrap_or_else(|| "?".to_string());
                let hand_before = d.hand_before.unwrap_or(0);
                let hand_after = d.hand_after.unwrap_or(0);
                format!(
                    "- PLAYED: {} (hand: {} -> {} points)",
                    cards, hand_before, hand_after
                )
            }
            "draw" => {
                let source = d.source.as_deref().unwrap_or("?");
                match source.strip_prefix("discard:").map(str::parse::<u8>) {
                    Some(Ok(card)) => format!(
                        "- DREW: {} from the played cards",
                        LlmBotStrategy::card_to_name(card)
                    ),
                    _ if source == "deck" => "- DREW: from the deck".to_string(),
                    _ => format!("- DREW: {}", source),
                }
            }
            "zapzap" => {
                let hand_value = d.hand_value.unwrap_or(0);
                let success = d.success.map(|s| if s { "HELD" } else { "COUNTERACTED" });
                if let Some(success_str) = success {
                    format!(
                        "- ZAPZAP: called at {} points -> {}",
                        hand_value, success_str
                    )
                } else {
                    format!("- ZAPZAP: called at {} points", hand_value)
                }
            }
            _ => format!("- {}: {:?}", decision.decision_type, d),
        }
    }

    /// Parse insights from LLM response
    fn parse_insights(response: &str) -> Vec<ParsedInsight> {
        let mut insights = Vec::new();

        // Check for no insights
        if response.to_uppercase().contains("NO_NEW_INSIGHTS") {
            return insights;
        }

        // Parse [category] insight format
        let categories = [
            "play_strategy",
            "zapzap_timing",
            "draw_decision",
            "golden_score",
            "opponent_reading",
        ];

        for line in response.lines() {
            let line_lower = line.to_lowercase();
            for cat_str in &categories {
                let pattern = format!("[{}]", cat_str);
                if line_lower.contains(&pattern) {
                    // Extract text after the category
                    if let Some(pos) = line_lower.find(&pattern) {
                        let text = line[pos + pattern.len()..].trim();
                        if text.len() > 10 {
                            if let Some(category) = StrategyCategory::from_str(cat_str) {
                                insights.push(ParsedInsight {
                                    category,
                                    text: text.chars().take(100).collect(),
                                });
                            }
                        }
                    }
                }
            }
        }

        // Limit to 1 insight per round
        insights.truncate(1);
        insights
    }
}

/// Parsed insight from LLM response
struct ParsedInsight {
    category: StrategyCategory,
    text: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_insights() {
        let response = "[play_strategy] Shedding J, Q and K first lowers the hand fastest";
        let insights = ReflectOnRound::parse_insights(response);
        assert_eq!(insights.len(), 1);
        assert_eq!(insights[0].category, StrategyCategory::PlayStrategy);
        assert!(insights[0].text.contains("Shedding J, Q and K"));
    }

    #[test]
    fn test_parse_no_insights() {
        let response = "NO_NEW_INSIGHTS";
        let insights = ReflectOnRound::parse_insights(response);
        assert!(insights.is_empty());
    }

    #[test]
    fn test_reflection_speaks_the_play_prompt_notation() {
        // The insight goes back into the play prompt: the same suits (C is clubs there)
        let outcome = RoundOutcome {
            won: false,
            counteracted: false,
            score_change: 14,
            hand_points: 14,
            final_hand: vec![0, 13, 38, 52],
            is_golden_score: false,
        };
        let draw = Decision {
            decision_type: "draw".to_string(),
            details: DecisionDetails {
                source: Some("discard:26".to_string()),
                ..Default::default()
            },
            timestamp: 0,
        };
        let prompt = ReflectOnRound::build_reflection_prompt(3, &outcome, &[draw]);
        assert!(prompt.contains("- Final hand: AS, AH, KC, JKR"), "{prompt}");
        assert!(
            prompt.contains("- DREW: AC from the played cards"),
            "{prompt}"
        );

        let system = ReflectOnRound::build_system_prompt();
        assert!(system.contains(&LlmBotStrategy::rules_text()));
    }

    use crate::infrastructure::bot::llm_memory::DecisionDetails;
    use crate::infrastructure::services::LlmError;
    use async_trait::async_trait;
    use std::time::Duration;
    use tokio::sync::Notify;

    /// An LLM whose answer waits until the test releases it
    struct HeldLlm {
        called: Notify,
        release: Notify,
    }

    #[async_trait]
    impl LlmService for HeldLlm {
        async fn invoke(&self, _system: &str, _user: &str) -> Result<String, LlmError> {
            self.called.notify_one();
            self.release.notified().await;
            Ok("[play_strategy] Shedding the face cards first empties the hand faster".to_string())
        }

        async fn health_check(&self) -> bool {
            true
        }
    }

    fn decision(kind: &str) -> Decision {
        Decision {
            decision_type: kind.to_string(),
            details: DecisionDetails::default(),
            timestamp: 0,
        }
    }

    #[tokio::test]
    async fn test_reflection_releases_the_memory_during_the_llm_call() {
        let dir = std::env::temp_dir().join(format!("zapzap-reflect-{}", uuid::Uuid::new_v4()));
        let memory = Arc::new(RwLock::new(LlmBotMemory::new("bot", Some(dir.clone()))));
        memory
            .write()
            .await
            .track_decision("party", 1, decision("play"));
        // The same round number in another party is not this reflection's
        memory
            .write()
            .await
            .track_decision("other", 1, decision("play"));

        let llm = Arc::new(HeldLlm {
            called: Notify::new(),
            release: Notify::new(),
        });
        let reflect = ReflectOnRound::new(llm.clone());
        let input = ReflectOnRoundInput {
            bot_user_id: "bot".to_string(),
            party_id: "party".to_string(),
            round_number: 1,
            outcome: RoundOutcome {
                won: false,
                counteracted: false,
                score_change: 12,
                hand_points: 12,
                final_hand: vec![11],
                is_golden_score: false,
            },
        };
        let task = tokio::spawn({
            let memory = memory.clone();
            async move { reflect.execute(input, memory).await }
        });

        // While the LLM call is pending, the bot's next action records its decision
        llm.called.notified().await;
        let write = tokio::time::timeout(Duration::from_secs(1), memory.write()).await;
        let mut guard = write.expect("the memory is locked during the LLM call");
        guard.track_decision("party", 2, decision("draw"));
        drop(guard);

        llm.release.notify_one();
        let output = task.await.unwrap();
        assert!(output.success);
        assert_eq!(output.insights_generated, 1);
        let memory = memory.read().await;
        assert!(memory.get_decisions_for_round("party", 1).is_empty());
        assert_eq!(memory.get_decisions_for_round("party", 2).len(), 1);
        assert_eq!(memory.get_decisions_for_round("other", 1).len(), 1);
        assert!(memory.has_strategies());
        drop(memory);
        let _ = std::fs::remove_dir_all(dir);
    }

    /// An LLM that answers at once
    struct QuickLlm;

    #[async_trait]
    impl LlmService for QuickLlm {
        async fn invoke(&self, _system: &str, _user: &str) -> Result<String, LlmError> {
            Ok("[zapzap_timing] Call ZapZap early when the hand is worth two".to_string())
        }

        async fn health_check(&self) -> bool {
            true
        }
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn test_reflection_in_a_read_only_strategies_dir_keeps_the_insights_in_memory() {
        use std::os::unix::fs::PermissionsExt;

        // A root-owned data/bot-strategies seen from the uid-1000 container: read-only
        let dir = std::env::temp_dir().join(format!("zapzap-ro-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o555)).unwrap();
        let writable = std::fs::write(dir.join("probe"), b"").is_ok();

        let mut memory = LlmBotMemory::new("bot", Some(dir.clone()));
        memory.load().await;
        memory.track_decision("party", 1, decision("play"));
        let memory = Arc::new(RwLock::new(memory));

        let output = ReflectOnRound::new(Arc::new(QuickLlm))
            .execute(
                ReflectOnRoundInput {
                    bot_user_id: "bot".to_string(),
                    party_id: "party".to_string(),
                    round_number: 1,
                    outcome: RoundOutcome {
                        won: true,
                        counteracted: false,
                        score_change: 0,
                        hand_points: 2,
                        final_hand: vec![0, 13],
                        is_golden_score: false,
                    },
                },
                memory.clone(),
            )
            .await;

        // The reflection succeeds and its insight is kept, though no file was written
        assert!(output.success, "{:?}", output.reason);
        assert_eq!(output.insights_generated, 1);
        let mut guard = memory.write().await;
        assert!(guard.has_strategies());
        if !writable {
            assert!(!dir.join("bot.json").exists());
            // Saving again fails again, quietly, and changes nothing
            assert!(!guard.save_or_keep().await);
            assert!(guard.has_strategies());
        }
        drop(guard);
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o755)).unwrap();
        let _ = std::fs::remove_dir_all(dir);
    }
}
