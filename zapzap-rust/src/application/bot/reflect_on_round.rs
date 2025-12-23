//! ReflectOnRound Use Case
//!
//! Triggers LLM reflection after each round to learn from decisions

use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, error, info};

use crate::infrastructure::bot::llm_memory::{
    Decision, LlmBotMemory, StrategyCategory, StrategyContext,
};
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
        let mut memory_guard = memory.write().await;

        // Get decisions made this round
        let decisions = memory_guard.get_decisions_for_round(input.round_number).to_vec();

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

        // Call LLM for reflection
        match self.llm_service.invoke(&system_prompt, &user_prompt).await {
            Ok(response) => {
                // Parse insights from response
                let insights = Self::parse_insights(&response);

                // Add insights to memory
                for insight in &insights {
                    let context = StrategyContext {
                        party_id: Some(input.party_id.clone()),
                        round_number: Some(input.round_number),
                        outcome: Some(if input.outcome.won { "won" } else { "lost" }.to_string()),
                    };

                    memory_guard.add_strategy(&insight.text, insight.category, context, 0.5);
                }

                // Clear round decisions and increment counter
                memory_guard.clear_round_decisions(input.round_number);
                memory_guard.increment_rounds_analyzed();

                // Save memory
                drop(memory_guard);
                if let Err(e) = memory.write().await.save().await {
                    error!("Failed to save LLM memory: {}", e);
                }

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

    /// Build system prompt for reflection
    fn build_system_prompt() -> String {
        r#"Tu es un expert du jeu de cartes ZapZap qui analyse ses propres décisions pour s'améliorer.

## Règles de ZapZap (rappel)
- But: réduire la valeur de sa main et appeler ZapZap quand ≤5 points
- Valeurs: A=1, 2-10=face, J=11, Q=12, K=13, Joker=0 (ou 25 si pénalité)
- Coups valides: cartes seules, paires/brelans, suites (3+ cartes même couleur)
- Si contre: +main + (joueurs-1)×5 points de pénalité

## Ta tâche
Analyser les décisions d'un round et générer 0-1 insight stratégique.

## Format de réponse
- Si nouvel insight: [catégorie] insight (max 100 caractères)
- Si pas de nouvel insight: NO_NEW_INSIGHTS

Catégories valides:
- play_strategy: stratégie de jeu de cartes
- zapzap_timing: timing pour appeler ZapZap
- draw_decision: choix entre pioche et défausse
- golden_score: stratégie en Golden Score

Exemples:
[play_strategy] Jouer les figures (V,D,R) en priorité réduit la main plus vite
[zapzap_timing] Appeler ZapZap à 5pts quand adversaires ont 2-3 cartes = risqué
[draw_decision] Prendre les Jokers de la défausse est toujours rentable

Sois concis et actionnable. Un seul insight maximum."#
            .to_string()
    }

    /// Build reflection prompt with round context
    fn build_reflection_prompt(
        round_number: u32,
        outcome: &RoundOutcome,
        decisions: &[Decision],
    ) -> String {
        let mut lines = vec![
            format!("## Résumé du Round {}", round_number),
            format!("- Résultat: {}", Self::outcome_to_text(outcome)),
            format!(
                "- Score ce round: {}{}  points",
                if outcome.score_change >= 0 { "+" } else { "" },
                outcome.score_change
            ),
            format!("- Valeur main finale: {} points", outcome.hand_points),
            format!("- Main finale: {}", Self::cards_to_text(&outcome.final_hand)),
        ];

        lines.push(String::new());
        lines.push("## Tes décisions ce round".to_string());

        for decision in decisions {
            lines.push(Self::decision_to_text(decision));
        }

        if outcome.is_golden_score {
            lines.push(String::new());
            lines.push("## Contexte: Golden Score (2 joueurs restants)".to_string());
        }

        lines.push(String::new());
        lines.push("## Analyse".to_string());
        lines.push("Quelle décision a le plus impacté ce résultat ?".to_string());
        lines.push("Y a-t-il un pattern à retenir pour les prochaines parties ?".to_string());

        lines.join("\n")
    }

    /// Convert outcome to readable text
    fn outcome_to_text(outcome: &RoundOutcome) -> &'static str {
        if outcome.counteracted {
            "CONTRÉ (ZapZap échoué)"
        } else if outcome.won {
            "GAGNÉ (meilleure main ou ZapZap réussi)"
        } else {
            "PERDU (main trop haute)"
        }
    }

    /// Convert cards to readable text
    fn cards_to_text(cards: &[u8]) -> String {
        if cards.is_empty() {
            return "aucune".to_string();
        }

        const SUITS: [&str; 4] = ["P", "C", "T", "K"]; // Pique, Coeur, Trèfle, Carreau
        const RANKS: [&str; 13] = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "V", "D", "R"];

        cards
            .iter()
            .map(|&id| {
                if id >= 52 {
                    "JKR".to_string()
                } else {
                    let suit = SUITS[(id / 13) as usize];
                    let rank = RANKS[(id % 13) as usize];
                    format!("{}{}", rank, suit)
                }
            })
            .collect::<Vec<_>>()
            .join(", ")
    }

    /// Convert decision to readable text
    fn decision_to_text(decision: &Decision) -> String {
        let d = &decision.details;

        match decision.decision_type.as_str() {
            "play" => {
                let cards = d
                    .cards
                    .as_ref()
                    .map(|c| Self::cards_to_text(c))
                    .unwrap_or_else(|| "?".to_string());
                let hand_before = d.hand_before.unwrap_or(0);
                let hand_after = d.hand_after.unwrap_or(0);
                format!("- JOUÉ: {} (main: {}→{} pts)", cards, hand_before, hand_after)
            }
            "draw" => {
                let source = d.source.as_deref().unwrap_or("?");
                if source == "deck" {
                    "- PIOCHÉ: pioche".to_string()
                } else {
                    format!("- PIOCHÉ: défausse ({})", source)
                }
            }
            "zapzap" => {
                let hand_value = d.hand_value.unwrap_or(0);
                let success = d.success.map(|s| if s { "RÉUSSI" } else { "CONTRÉ" });
                if let Some(success_str) = success {
                    format!("- ZAPZAP: appelé à {} pts → {}", hand_value, success_str)
                } else {
                    format!("- ZAPZAP: appelé à {} pts", hand_value)
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
        let response =
            "[play_strategy] Jouer les figures en priorité réduit la main plus rapidement";
        let insights = ReflectOnRound::parse_insights(response);
        assert_eq!(insights.len(), 1);
        assert_eq!(insights[0].category, StrategyCategory::PlayStrategy);
        assert!(insights[0].text.contains("Jouer les figures"));
    }

    #[test]
    fn test_parse_no_insights() {
        let response = "NO_NEW_INSIGHTS";
        let insights = ReflectOnRound::parse_insights(response);
        assert!(insights.is_empty());
    }

    #[test]
    fn test_cards_to_text() {
        assert_eq!(ReflectOnRound::cards_to_text(&[0]), "AP");
        assert_eq!(ReflectOnRound::cards_to_text(&[52]), "JKR");
        assert_eq!(ReflectOnRound::cards_to_text(&[0, 13]), "AP, AC");
    }
}
