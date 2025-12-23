//! LLM Bot Strategy
//!
//! Bot strategy using LLM (Ollama/Bedrock) for decision-making.
//! Uses HardBotStrategy as fallback when LLM is unavailable or fails.
//! Supports strategic memory to learn from previous games.

use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{error, info, warn};

use super::{BotAction, BotStrategy, DrawSource, HardBotStrategy};
use crate::domain::value_objects::GameState;
use crate::infrastructure::bot::card_analyzer::{
    calculate_hand_value, can_call_zapzap, find_all_valid_plays, get_card_points, is_valid_play,
    would_complete_pair, would_complete_sequence,
};
use crate::infrastructure::bot::llm_memory::{Decision, DecisionDetails, LlmBotMemory};
use crate::infrastructure::services::LlmService;

/// Card suit symbols and rank names
const SUIT_SYMBOLS: [&str; 4] = ["S", "H", "C", "D"];
const RANKS: [&str; 13] = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];

/// LLM Bot Strategy
pub struct LlmBotStrategy {
    llm_service: Option<Arc<dyn LlmService>>,
    fallback: HardBotStrategy,
    memory: Option<Arc<RwLock<LlmBotMemory>>>,
    system_prompt: String,
}

impl LlmBotStrategy {
    /// Create new LLM bot strategy
    pub fn new(
        llm_service: Option<Arc<dyn LlmService>>,
        memory: Option<Arc<RwLock<LlmBotMemory>>>,
    ) -> Self {
        let system_prompt = Self::build_system_prompt_base();
        Self {
            llm_service,
            fallback: HardBotStrategy::new(),
            memory,
            system_prompt,
        }
    }

    /// Create with just LLM service (no memory)
    pub fn with_service(llm_service: Arc<dyn LlmService>) -> Self {
        Self::new(Some(llm_service), None)
    }

    /// Check if this strategy is async-capable
    pub fn is_async(&self) -> bool {
        self.llm_service.is_some()
    }

    /// Get the memory instance (for decision tracking)
    pub fn get_memory(&self) -> Option<Arc<RwLock<LlmBotMemory>>> {
        self.memory.clone()
    }

    /// Build the base system prompt with game rules
    fn build_system_prompt_base() -> String {
        r#"You are an expert ZapZap card game player bot. Your goal is to win by minimizing your hand value and calling ZapZap at the optimal time.

## Game Rules

### Card Values (for ZapZap eligibility and hand scoring)
- Ace (A): 1 point
- 2-10: Face value (2=2, 3=3, ..., 10=10)
- Jack (J): 11 points
- Queen (Q): 12 points
- King (K): 13 points
- Joker: 0 points for ZapZap eligibility, but 25 points penalty in final scoring if you don't have the lowest hand

### Card Notation
Cards are written as RankSuit, for example:
- AS = Ace of Spades
- 10H = 10 of Hearts
- KC = King of Clubs
- QD = Queen of Diamonds
- JKR = Joker

### Valid Plays
1. **Single card**: Any single card can be played alone
2. **Pairs/Sets**: 2 or more cards of the same rank (e.g., KS KH = pair of Kings)
3. **Sequences**: 3 or more consecutive cards of the same suit (e.g., 5S 6S 7S)
4. **Jokers**: Can substitute any card in pairs or sequences

### Turn Structure
Each turn has two phases:
1. **PLAY phase**: You must play a valid card combination from your hand
2. **DRAW phase**: Draw one card from the deck OR pick a card from the discard pile

### ZapZap Rules
- You can call ZapZap when your hand value is 5 points or less (Joker = 0 for this check)
- If you have the lowest hand value: You score 0, all other players score their hand value (Joker = 25 points penalty)
- If someone else has equal or lower hand value: You are COUNTERACTED and receive +20 points penalty plus your hand value

### Winning
- Players are eliminated when their total score exceeds 100 points
- When only 2 players remain: "Golden Score" final round begins
- The winner is the last player with 100 points or less

## Strategy Guidelines
1. **Minimize hand value quickly** to be able to call ZapZap early
2. **Multi-card plays are more efficient** than playing single cards
3. **Track what opponents pick from discard** - they likely need those cards
4. **In Golden Score (2 players)**: NEVER play Jokers - hoard them to deny your opponent
5. **Be cautious calling ZapZap** when opponents have few cards (higher counter risk)
6. **Prefer playing high-value cards** (J, Q, K) to reduce hand value faster
7. **Consider discard pile** - pick cards that help form pairs/sequences

## Response Format
You must respond with ONLY the requested information:
- For play decisions: List the cards to play (e.g., "KS, KH" or "5C, 6C, 7C")
- For ZapZap decisions: Answer "YES" or "NO"
- For draw decisions: Answer "DECK" or "DISCARD"

Be concise and direct in your responses."#.to_string()
    }

    /// Build system prompt with learned strategies
    async fn build_system_prompt(&self) -> String {
        let mut prompt = self.system_prompt.clone();

        if let Some(ref memory) = self.memory {
            let memory = memory.read().await;
            if memory.has_strategies() {
                let strategies = memory.get_top_strategies(10);
                if !strategies.is_empty() {
                    prompt.push_str("\n\n## Learned Strategies (from your previous games)\n");
                    prompt.push_str("These insights come from your own experience - apply them:\n");
                    for s in strategies {
                        prompt.push_str(&format!("- {}\n", s.insight));
                    }
                }
            }
        }

        prompt
    }

    /// Convert card ID to human-readable name
    fn card_to_name(card_id: u8) -> String {
        if card_id >= 52 {
            return "JKR".to_string();
        }
        let suit = SUIT_SYMBOLS[(card_id / 13) as usize];
        let rank = RANKS[(card_id % 13) as usize];
        format!("{}{}", rank, suit)
    }

    /// Convert array of card IDs to human-readable names
    fn cards_to_names(cards: &[u8]) -> String {
        if cards.is_empty() {
            return "none".to_string();
        }
        cards
            .iter()
            .map(|&c| Self::card_to_name(c))
            .collect::<Vec<_>>()
            .join(", ")
    }

    /// Build game state context for LLM prompt
    fn build_game_state_context(state: &GameState, player_index: u8) -> String {
        let hand = state.get_hand(player_index);
        let hand_value = calculate_hand_value(hand);

        let mut lines = vec![
            "## Current Game Situation".to_string(),
            format!("Round: {}", state.round_number),
            format!("Your player index: {}", player_index),
            format!(
                "Golden Score mode: {}",
                if state.is_golden_score {
                    "YES (final 2-player round!)"
                } else {
                    "NO"
                }
            ),
            String::new(),
            "### Your Hand".to_string(),
            format!("Cards: {}", Self::cards_to_names(hand)),
            format!("Hand value: {} points", hand_value),
            format!(
                "Can call ZapZap: {}",
                if hand_value <= 5 { "YES" } else { "NO" }
            ),
            String::new(),
            "### Opponent Information".to_string(),
        ];

        for i in 0..state.player_count {
            if i == player_index {
                continue;
            }
            if state.is_eliminated(i) {
                lines.push(format!("Player {}: ELIMINATED", i));
            } else {
                let opponent_hand = state.get_hand(i);
                lines.push(format!(
                    "Player {}: {} cards, score: {}",
                    i,
                    opponent_hand.len(),
                    state.scores[i as usize]
                ));
            }
        }

        lines.push(String::new());
        lines.push("### Your Score".to_string());
        lines.push(format!(
            "Your total score: {} points",
            state.scores[player_index as usize]
        ));

        if !state.last_cards_played.is_empty() {
            lines.push(String::new());
            lines.push("### Discard Pile (available to pick)".to_string());
            lines.push(Self::cards_to_names(&state.last_cards_played));
        } else {
            lines.push(String::new());
            lines.push("### Discard Pile".to_string());
            lines.push("Empty".to_string());
        }

        lines.push(String::new());
        lines.push("### Deck Status".to_string());
        lines.push(format!("Cards remaining in deck: {}", state.deck.len()));

        lines.join("\n")
    }

    /// Parse LLM response to extract card IDs
    fn parse_play_response(response: &str, hand: &[u8]) -> Option<Vec<u8>> {
        let upper = response.to_uppercase();
        let mut found_cards = Vec::new();

        // Pattern: RankSuit (e.g., "KS", "10H", "AC")
        let patterns = [
            ("A", 0),
            ("2", 1),
            ("3", 2),
            ("4", 3),
            ("5", 4),
            ("6", 5),
            ("7", 6),
            ("8", 7),
            ("9", 8),
            ("10", 9),
            ("J", 10),
            ("Q", 11),
            ("K", 12),
        ];

        let suits = [("S", 0), ("H", 1), ("C", 2), ("D", 3)];

        for (rank_str, rank_idx) in &patterns {
            for (suit_str, suit_idx) in &suits {
                let pattern = format!("{}{}", rank_str, suit_str);
                if upper.contains(&pattern) {
                    let card_id = (suit_idx * 13 + rank_idx) as u8;
                    if hand.contains(&card_id) && !found_cards.contains(&card_id) {
                        found_cards.push(card_id);
                    }
                }
            }
        }

        // Check for Joker
        if upper.contains("JOKER") || upper.contains("JKR") {
            for &card_id in hand {
                if card_id >= 52 && !found_cards.contains(&card_id) {
                    found_cards.push(card_id);
                    break;
                }
            }
        }

        if found_cards.is_empty() {
            None
        } else {
            Some(found_cards)
        }
    }

    /// Async play selection using LLM
    pub async fn select_cards_async(&self, state: &GameState, player_index: u8) -> Vec<u8> {
        let hand = state.get_hand(player_index);
        if hand.is_empty() {
            return Vec::new();
        }

        // If no LLM service, use fallback
        let Some(ref llm_service) = self.llm_service else {
            return self.fallback.select_cards(state, player_index);
        };

        // Build prompt
        let valid_plays = find_all_valid_plays(hand);
        let plays_desc: Vec<String> = valid_plays
            .iter()
            .map(|play| {
                let remaining: Vec<u8> = hand.iter().copied().filter(|c| !play.contains(c)).collect();
                let remaining_value = calculate_hand_value(&remaining);
                format!(
                    "- {} (remaining hand: {} points)",
                    Self::cards_to_names(play),
                    remaining_value
                )
            })
            .collect();

        let context = Self::build_game_state_context(state, player_index);
        let system_prompt = self.build_system_prompt().await;

        let user_prompt = format!(
            r#"{}

### Valid Plays Available
{}

Based on the current game state and optimal strategy, which cards should I play?
Consider:
1. Minimizing remaining hand value
2. Setting up for ZapZap if close
3. Playing multi-card combinations when beneficial
4. In Golden Score: NEVER play Jokers

Respond with ONLY the cards to play (e.g., "KS, KH" for a pair of Kings)."#,
            context,
            plays_desc.join("\n")
        );

        match llm_service.invoke(&system_prompt, &user_prompt).await {
            Ok(response) => {
                if let Some(cards) = Self::parse_play_response(&response, hand) {
                    if is_valid_play(&cards) {
                        info!(
                            "LLM selected play: {} (response: {})",
                            Self::cards_to_names(&cards),
                            &response[..response.len().min(100)]
                        );

                        // Track decision if memory is available
                        if let Some(ref memory) = self.memory {
                            let hand_before = calculate_hand_value(hand);
                            let remaining: Vec<u8> =
                                hand.iter().copied().filter(|c| !cards.contains(c)).collect();
                            let hand_after = calculate_hand_value(&remaining);

                            let decision = Decision {
                                decision_type: "play".to_string(),
                                details: DecisionDetails {
                                    cards: Some(cards.clone()),
                                    hand_before: Some(hand_before),
                                    hand_after: Some(hand_after),
                                    ..Default::default()
                                },
                                timestamp: chrono::Utc::now().timestamp_millis(),
                            };

                            let mut memory = memory.write().await;
                            memory.track_decision(state.round_number as u32, decision);
                        }

                        return cards;
                    }
                }

                warn!(
                    "LLM response invalid, using fallback: {}",
                    &response[..response.len().min(200)]
                );
                self.fallback.select_cards(state, player_index)
            }
            Err(e) => {
                error!("LLM play selection failed: {}", e);
                self.fallback.select_cards(state, player_index)
            }
        }
    }

    /// Async ZapZap decision using LLM
    pub async fn should_call_zapzap_async(&self, state: &GameState, player_index: u8) -> bool {
        let hand = state.get_hand(player_index);

        // Use can_call_zapzap to check eligibility (hand value <= 5)
        if !can_call_zapzap(hand) {
            return false;
        }

        let hand_value = calculate_hand_value(hand);

        // Always call at 0 - no risk
        if hand_value == 0 {
            return true;
        }

        // If no LLM service, use fallback
        let Some(ref llm_service) = self.llm_service else {
            return self.fallback.should_call_zapzap(state, player_index);
        };

        // Calculate opponent info
        let active_opponents: Vec<usize> = (0..state.player_count as usize)
            .filter(|&i| i != player_index as usize && !state.is_eliminated(i as u8))
            .collect();

        let avg_opponent_cards = if active_opponents.is_empty() {
            0.0
        } else {
            active_opponents
                .iter()
                .map(|&i| state.get_hand(i as u8).len() as f32)
                .sum::<f32>()
                / active_opponents.len() as f32
        };

        let context = Self::build_game_state_context(state, player_index);
        let system_prompt = self.build_system_prompt().await;

        let user_prompt = format!(
            r#"{}

### ZapZap Decision
Your hand value is {} points, which is eligible for ZapZap (<=5).
Average opponent hand size: {:.1} cards

Should you call ZapZap now?

Consider:
1. Opponents with few cards (1-3) have higher chance of having low hands = counter risk
2. Opponents with many cards (5+) likely have high hands = safer to ZapZap
3. Your current score vs opponents - risk tolerance
4. If counteracted: +20 penalty plus your hand value

Respond with ONLY "YES" or "NO"."#,
            context, hand_value, avg_opponent_cards
        );

        match llm_service.invoke(&system_prompt, &user_prompt).await {
            Ok(response) => {
                let should_call = response.to_uppercase().contains("YES");
                info!(
                    "LLM ZapZap decision: {} (hand_value: {}, response: {})",
                    should_call,
                    hand_value,
                    &response[..response.len().min(50)]
                );

                // Track decision if memory is available
                if let Some(ref memory) = self.memory {
                    let decision = Decision {
                        decision_type: "zapzap".to_string(),
                        details: DecisionDetails {
                            hand_value: Some(hand_value),
                            success: None, // Will be updated after result
                            ..Default::default()
                        },
                        timestamp: chrono::Utc::now().timestamp_millis(),
                    };

                    let mut memory = memory.write().await;
                    memory.track_decision(state.round_number as u32, decision);
                }

                should_call
            }
            Err(e) => {
                error!("LLM ZapZap decision failed: {}", e);
                self.fallback.should_call_zapzap(state, player_index)
            }
        }
    }

    /// Async draw source selection using LLM
    pub async fn decide_draw_source_async(&self, state: &GameState, player_index: u8) -> DrawSource {
        let hand = state.get_hand(player_index);

        // If discard is empty, must draw from deck
        if state.last_cards_played.is_empty() {
            return DrawSource::Deck;
        }

        // If no LLM service, use fallback
        let Some(ref llm_service) = self.llm_service else {
            return self.fallback.decide_draw_source(state, player_index);
        };

        // Analyze discard options
        let discard_analysis: Vec<String> = state
            .last_cards_played
            .iter()
            .map(|&card| {
                let is_joker = card >= 52;
                let enables_pair = would_complete_pair(hand, card);
                let enables_seq = would_complete_sequence(hand, card);

                let card_name = Self::card_to_name(card);
                if is_joker {
                    format!("{}: JOKER (valuable!)", card_name)
                } else if enables_pair || enables_seq {
                    format!("{}: enables multi-card play", card_name)
                } else {
                    format!("{}: {} points", card_name, get_card_points(card))
                }
            })
            .collect();

        let context = Self::build_game_state_context(state, player_index);
        let system_prompt = self.build_system_prompt().await;

        let user_prompt = format!(
            r#"{}

### Draw Decision
You must draw a card. Options:

1. **DECK**: Draw unknown card from deck ({} cards remaining)

2. **DISCARD**: Pick from discard pile:
{}

Which option is better for your current hand?

Consider:
1. Does any discard card complete a pair or sequence with your hand?
2. Is there a Joker in discard? (Always valuable to grab!)
3. Picking from discard reveals information to opponents about your strategy
4. In Golden Score: Grabbing Joker denies it from opponent

Respond with ONLY "DECK" or "DISCARD"."#,
            context,
            state.deck.len(),
            discard_analysis.join("\n")
        );

        match llm_service.invoke(&system_prompt, &user_prompt).await {
            Ok(response) => {
                let source = if response.to_uppercase().contains("DISCARD") {
                    // Pick the best card from discard
                    let best_card = state
                        .last_cards_played
                        .iter()
                        .max_by_key(|&&card| {
                            let mut score = 0i32;
                            if card >= 52 {
                                score += 100; // Jokers are always good
                            }
                            if would_complete_pair(hand, card) {
                                score += 50;
                            }
                            if would_complete_sequence(hand, card) {
                                score += 40;
                            }
                            score -= get_card_points(card) as i32;
                            score
                        })
                        .copied()
                        .unwrap_or(state.last_cards_played[0]);

                    DrawSource::Discard(best_card)
                } else {
                    DrawSource::Deck
                };

                info!(
                    "LLM draw decision: {:?} (response: {})",
                    source,
                    &response[..response.len().min(50)]
                );

                // Track decision if memory is available
                if let Some(ref memory) = self.memory {
                    let decision = Decision {
                        decision_type: "draw".to_string(),
                        details: DecisionDetails {
                            source: Some(match &source {
                                DrawSource::Deck => "deck".to_string(),
                                DrawSource::Discard(card) => format!("discard:{}", card),
                            }),
                            ..Default::default()
                        },
                        timestamp: chrono::Utc::now().timestamp_millis(),
                    };

                    let mut memory = memory.write().await;
                    memory.track_decision(state.round_number as u32, decision);
                }

                source
            }
            Err(e) => {
                error!("LLM draw decision failed: {}", e);
                self.fallback.decide_draw_source(state, player_index)
            }
        }
    }
}

impl BotStrategy for LlmBotStrategy {
    fn select_hand_size(&self, state: &GameState, player_index: u8) -> u8 {
        // Hand size is a simple decision - use fallback
        self.fallback.select_hand_size(state, player_index)
    }

    fn decide_action(&self, state: &GameState, player_index: u8) -> BotAction {
        // For sync calls, use fallback
        self.fallback.decide_action(state, player_index)
    }

    fn select_cards(&self, state: &GameState, player_index: u8) -> Vec<u8> {
        // For sync calls, use fallback
        warn!("LlmBotStrategy.select_cards called synchronously, using fallback");
        self.fallback.select_cards(state, player_index)
    }

    fn decide_draw_source(&self, state: &GameState, player_index: u8) -> DrawSource {
        // For sync calls, use fallback
        warn!("LlmBotStrategy.decide_draw_source called synchronously, using fallback");
        self.fallback.decide_draw_source(state, player_index)
    }

    fn should_call_zapzap(&self, state: &GameState, player_index: u8) -> bool {
        // For sync calls, use fallback
        warn!("LlmBotStrategy.should_call_zapzap called synchronously, using fallback");
        self.fallback.should_call_zapzap(state, player_index)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_card_to_name() {
        assert_eq!(LlmBotStrategy::card_to_name(0), "AS");
        assert_eq!(LlmBotStrategy::card_to_name(12), "KS");
        assert_eq!(LlmBotStrategy::card_to_name(13), "AH");
        assert_eq!(LlmBotStrategy::card_to_name(52), "JKR");
    }

    #[test]
    fn test_parse_play_response() {
        let hand = vec![0, 12, 13, 25, 52]; // AS, KS, AH, KH, Joker

        // Single card
        let result = LlmBotStrategy::parse_play_response("Play KS", &hand);
        assert_eq!(result, Some(vec![12]));

        // Pair
        let result = LlmBotStrategy::parse_play_response("KS, KH", &hand);
        assert!(result.is_some());
        let cards = result.unwrap();
        assert!(cards.contains(&12) && cards.contains(&25));

        // Joker
        let result = LlmBotStrategy::parse_play_response("Play the Joker", &hand);
        assert_eq!(result, Some(vec![52]));
    }
}
