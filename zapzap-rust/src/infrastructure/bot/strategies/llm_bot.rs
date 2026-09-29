//! LLM Bot Strategy
//!
//! Bot strategy using an LLM (Ollama/Bedrock) for its decisions: one question a turn, the
//! plays and the drawable cards listed and numbered, answered with one JSON object that
//! names them by number. Uses HardBotStrategy for any decision the answer does not settle
//! (no service, a failed call, malformed JSON, a number off the list).
//! Supports strategic memory to learn from previous games.

use serde_json::{Map, Value};
use std::sync::{Arc, Mutex};
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};

use super::{BotAction, BotStrategy, DrawSource, HardBotStrategy};
use crate::domain::services::{counteract_penalty, COUNTERACT_PENALTY_PER_OPPONENT};
use crate::domain::value_objects::GameState;
use crate::infrastructure::bot::card_analyzer::{
    calculate_hand_score, calculate_hand_value, can_call_zapzap, find_plays_without_lone_jokers,
    is_valid_play,
};
use crate::infrastructure::bot::llm_memory::{Decision, DecisionDetails, LlmBotMemory};
use crate::infrastructure::services::LlmService;

/// Card suit symbols and rank names
const SUIT_SYMBOLS: [&str; 4] = ["S", "H", "C", "D"];
const RANKS: [&str; 13] = [
    "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K",
];

/// A turn's question: the situation as the model reads it, and what its numbers stand for
#[derive(Debug, Clone)]
struct TurnQuestion {
    text: String,
    /// The plays offered, numbered from 1
    plays: Vec<Vec<u8>>,
    /// The cards drawable after the play, numbered from 1
    drawable: Vec<u8>,
    /// Whether ZapZap is offered (the hand is worth 5 or less)
    zapzap: bool,
}

/// Where the answer says to draw from
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DrawChoice {
    Deck,
    Card(u8),
}

/// A turn's answer, one field per decision: `None` where the answer does not settle it,
/// which that decision's fallback then takes
#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct TurnAnswer {
    zapzap: Option<bool>,
    play: Option<Vec<u8>>,
    draw: Option<DrawChoice>,
}

/// The draw an answer planned with its play, for the hand that play leaves
#[derive(Debug, Clone)]
struct DrawPlan {
    round: u16,
    /// The hand after the play, sorted
    hand: Vec<u8>,
    draw: Option<DrawChoice>,
}

/// What the strategy keeps between the calls of one turn: the ZapZap check, the play and
/// the draw read one answer
#[derive(Debug, Default)]
struct TurnMemo {
    /// The last question asked, and its answer
    answered: Option<(String, TurnAnswer)>,
    /// The draw planned with the play made
    draw: Option<DrawPlan>,
}

/// The start of a model's answer, for a log line: 200 characters at most, cut on a
/// character boundary (a byte slice would panic inside a multi-byte one)
fn excerpt(text: &str) -> String {
    text.chars().take(200).collect()
}

/// LLM Bot Strategy
pub struct LlmBotStrategy {
    llm_service: Option<Arc<dyn LlmService>>,
    fallback: HardBotStrategy,
    memory: Option<Arc<RwLock<LlmBotMemory>>>,
    system_prompt: String,
    /// The party this instance plays in: its decisions are kept per party and round
    party_id: String,
    turn: Mutex<TurnMemo>,
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
            party_id: String::new(),
            turn: Mutex::new(TurnMemo::default()),
        }
    }

    /// The same strategy, recording its decisions under `party_id`
    pub fn for_party(mut self, party_id: &str) -> Self {
        self.party_id = party_id.to_string();
        self
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

    /// The rules of ZapZap as GAME_RULES.md states them, in the prompts' card notation
    pub(crate) fn rules_text() -> String {
        format!(
            r#"## Rules of ZapZap
- 54 cards: A, 2-10, J, Q, K in four suits, and 2 jokers. A card is written rank then suit (S, H, C, D): AS, 10H, KC. JKR is a joker.
- Points: A = 1, 2-10 = face value, J = 11, Q = 12, K = 13, joker = 0.
- On your turn you play one combination from your hand, then draw one card: the top of the deck (unseen), or any one of the cards the previous player just played (seen by all).
- Combinations: one card; two or more cards of the same rank; three or more cards of one suit that follow each other (A is low: A 2 3, never Q K A). A joker stands for any card of a combination.
- ZapZap: at the start of your turn, instead of playing, you may call ZapZap if your hand is worth 5 points or less (jokers 0). The round ends and every hand is counted, jokers 0:
  - the lowest hand scores 0, and so does every hand tied with it; every other player scores their hand, each joker counting 25;
  - if another player's hand is worth as much as yours or less, you are counteracted: whatever the other hands, you score your hand, each joker counting 25, plus {penalty} points per other player still in the game, even when tied at the lowest.
- Scores add up over the rounds. A player past 100 points is out; the last player in wins the game.
- Golden Score: with two players left, the next ZapZap ends the game. The lowest hand wins it; a counteracted caller (tied hands included) loses it.
- The deck holds about 6.7 points a card on average."#,
            penalty = COUNTERACT_PENALTY_PER_OPPONENT
        )
    }

    /// Build the base system prompt: the rules and the answer's form
    fn build_system_prompt_base() -> String {
        format!(
            r#"You are a bot playing ZapZap, a rummy-like card game, to win the game: keep your score low, and call ZapZap when no other hand is likely to be as low as yours.

{}

## Your answer
Each turn lists the plays you may make and the cards you may draw, each with a number. Think it through, then answer with one JSON object and nothing else, naming them by number, in the form the turn asks for."#,
            Self::rules_text()
        )
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
    pub(crate) fn card_to_name(card_id: u8) -> String {
        if card_id >= 52 {
            return "JKR".to_string();
        }
        let suit = SUIT_SYMBOLS[(card_id / 13) as usize];
        let rank = RANKS[(card_id % 13) as usize];
        format!("{}{}", rank, suit)
    }

    /// Convert array of card IDs to human-readable names
    pub(crate) fn cards_to_names(cards: &[u8]) -> String {
        if cards.is_empty() {
            return "none".to_string();
        }
        cards
            .iter()
            .map(|&c| Self::card_to_name(c))
            .collect::<Vec<_>>()
            .join(", ")
    }

    /// The cards the player on turn may draw once they have played: the previous player's
    /// play, or on the round's first play the card turned up at the deal
    /// (`execute_play`, `game_service.rs`)
    fn drawable_after_play(state: &GameState) -> &[u8] {
        if state.cards_played.is_empty() {
            &state.last_cards_played
        } else {
            &state.cards_played
        }
    }

    /// The turn's question, for the player on turn before they play
    fn turn_question(state: &GameState, player_index: u8) -> TurnQuestion {
        let hand = state.get_hand(player_index);
        let hand_value = calculate_hand_value(hand);
        let plays: Vec<Vec<u8>> = find_plays_without_lone_jokers(hand)
            .into_iter()
            .map(|play| play.to_vec())
            .collect();
        let drawable = Self::drawable_after_play(state).to_vec();
        let zapzap = can_call_zapzap(hand);

        let mut lines = vec![format!(
            "Round {}{}. You are player {}, your score is {}.",
            state.round_number,
            if state.is_golden_score {
                ", Golden Score"
            } else {
                ""
            },
            player_index,
            state.scores[player_index as usize]
        )];
        lines.push(format!(
            "Your hand: {} (worth {} points, jokers 0).",
            Self::cards_to_names(hand),
            hand_value
        ));
        lines.push("Opponents:".to_string());
        for i in (0..state.player_count).filter(|&i| i != player_index) {
            if state.is_eliminated(i) {
                lines.push(format!("- Player {}: out.", i));
                continue;
            }
            let known = state.get_player_known_cards(i);
            let known = if known.is_empty() {
                String::new()
            } else {
                format!(
                    ", holds {} (taken from the played cards)",
                    Self::cards_to_names(&known)
                )
            };
            lines.push(format!(
                "- Player {}: score {}, {} cards in hand{}.",
                i,
                state.scores[i as usize],
                state.get_hand(i).len(),
                known
            ));
        }
        lines.push(format!("Deck: {} cards.", state.deck.len()));
        lines.push(String::new());

        lines.push("Plays you may make (number: cards -> your hand after it):".to_string());
        for (n, play) in plays.iter().enumerate() {
            let remaining: Vec<u8> = hand.iter().copied().filter(|c| !play.contains(c)).collect();
            lines.push(format!(
                "{}: {} -> {} points",
                n + 1,
                Self::cards_to_names(play),
                calculate_hand_value(&remaining)
            ));
        }
        lines.push(String::new());
        lines.push(format!(
            "Then you draw \"deck\" (an unseen card){}",
            if drawable.is_empty() {
                ".".to_string()
            } else {
                format!(
                    ", or one of the cards {} (number: card):",
                    if state.cards_played.is_empty() {
                        "turned up at the deal"
                    } else {
                        "the previous player played"
                    }
                )
            }
        ));
        for (n, &card) in drawable.iter().enumerate() {
            lines.push(format!("{}: {}", n + 1, Self::card_to_name(card)));
        }
        lines.push(String::new());

        let play_form = r#""play": <play number>, "draw": "deck" or <card number>"#;
        if zapzap {
            let counteracted =
                calculate_hand_score(hand, false) + counteract_penalty(state.active_player_count());
            lines.push(format!(
                "Your hand is worth {} points: you may call ZapZap instead of playing. {}",
                hand_value,
                if state.is_golden_score {
                    "Counteracted, you lose the game.".to_string()
                } else {
                    format!("Counteracted, you score {} points.", counteracted)
                }
            ));
            lines.push(format!(
                "Answer {{\"zapzap\": true}} to call it, or {{\"zapzap\": false, {}}}.",
                play_form
            ));
        } else {
            lines.push(format!("Answer {{{}}}.", play_form));
        }

        TurnQuestion {
            text: lines.join("\n"),
            plays,
            drawable,
            zapzap,
        }
    }

    /// The JSON object an answer holds: the last object in the text that parses (a code
    /// fence, a sentence, or an example object before the answer is left out). Objects
    /// are read from left to right, each skipped whole, so an object nested in another
    /// is never taken for the answer.
    fn answer_object(text: &str) -> Option<Map<String, Value>> {
        let mut last = None;
        let mut from = 0;
        while let Some(offset) = text[from..].find('{') {
            let start = from + offset;
            let mut values = serde_json::Deserializer::from_str(&text[start..]).into_iter();
            match values.next() {
                Some(Ok(Value::Object(object))) => {
                    last = Some(object);
                    from = start + values.byte_offset();
                }
                _ => from = start + 1,
            }
        }
        last
    }

    /// The item numbered `value` (from 1) of `count`: an integer in range, or a string of
    /// one (`"1"`, as gpt-oss writes a draw now and then); nothing else
    fn numbered(value: &Value, count: usize) -> Option<usize> {
        let n = match value {
            Value::String(s) => s.trim().parse::<u64>().ok()?,
            _ => value.as_u64()?,
        };
        (1..=count as u64).contains(&n).then(|| n as usize - 1)
    }

    /// Read an answer against its question: each decision it settles, strictly (the types
    /// and numbers the question asked for), the others `None`
    fn parse_turn_answer(text: &str, question: &TurnQuestion) -> TurnAnswer {
        let Some(object) = Self::answer_object(text) else {
            return TurnAnswer::default();
        };
        let zapzap = if question.zapzap {
            object.get("zapzap").and_then(Value::as_bool)
        } else {
            None
        };
        let play = object
            .get("play")
            .and_then(|v| Self::numbered(v, question.plays.len()))
            .map(|n| question.plays[n].clone())
            .filter(|cards| is_valid_play(cards));
        let draw = match object.get("draw") {
            Some(Value::String(s)) if s.eq_ignore_ascii_case("deck") => Some(DrawChoice::Deck),
            Some(v) => Self::numbered(v, question.drawable.len())
                .map(|n| DrawChoice::Card(question.drawable[n])),
            None => None,
        };
        TurnAnswer { zapzap, play, draw }
    }

    /// The answer for the turn `state` shows: the one already given to this very question
    /// (the ZapZap check and the play ask the same), else the model's
    async fn turn_answer(
        &self,
        llm_service: &Arc<dyn LlmService>,
        state: &GameState,
        player_index: u8,
    ) -> TurnAnswer {
        let question = Self::turn_question(state, player_index);
        if let Some((asked, answer)) = &self.turn_memo().answered {
            if *asked == question.text {
                return answer.clone();
            }
        }

        let system_prompt = self.build_system_prompt().await;
        debug!("LLM turn question:\n{}", question.text);
        let answer = match llm_service.invoke(&system_prompt, &question.text).await {
            Ok(response) => {
                let answer = Self::parse_turn_answer(&response, &question);
                info!(
                    "LLM turn answer: {:?} (response: {})",
                    answer,
                    excerpt(&response)
                );
                if answer.zapzap != Some(true) {
                    if answer.play.is_none() {
                        warn!(
                            "LLM answer names no listed play, the play falls back: {}",
                            excerpt(&response)
                        );
                    } else if answer.draw.is_none() {
                        warn!(
                            "LLM answer names no listed draw, the draw falls back: {}",
                            excerpt(&response)
                        );
                    }
                }
                answer
            }
            Err(e) => {
                error!("LLM turn question failed: {}", e);
                TurnAnswer::default()
            }
        };
        self.turn_memo().answered = Some((question.text, answer.clone()));
        answer
    }

    fn turn_memo(&self) -> std::sync::MutexGuard<'_, TurnMemo> {
        self.turn.lock().unwrap_or_else(|e| e.into_inner())
    }

    async fn track(&self, round: u16, decision_type: &str, details: DecisionDetails) {
        if let Some(ref memory) = self.memory {
            let decision = Decision {
                decision_type: decision_type.to_string(),
                details,
                timestamp: chrono::Utc::now().timestamp_millis(),
            };
            memory
                .write()
                .await
                .track_decision(&self.party_id, round as u32, decision);
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

        let answer = self.turn_answer(llm_service, state, player_index).await;
        let Some(cards) = answer.play else {
            self.turn_memo().draw = None;
            return self.fallback.select_cards(state, player_index);
        };

        let mut remaining: Vec<u8> = hand
            .iter()
            .copied()
            .filter(|c| !cards.contains(c))
            .collect();
        let details = DecisionDetails {
            cards: Some(cards.clone()),
            hand_before: Some(calculate_hand_value(hand)),
            hand_after: Some(calculate_hand_value(&remaining)),
            ..Default::default()
        };
        remaining.sort_unstable();
        self.turn_memo().draw = Some(DrawPlan {
            round: state.round_number,
            hand: remaining,
            draw: answer.draw,
        });
        self.track(state.round_number, "play", details).await;
        cards
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

        let answer = self.turn_answer(llm_service, state, player_index).await;
        let Some(call) = answer.zapzap else {
            return self.fallback.should_call_zapzap(state, player_index);
        };
        info!("LLM ZapZap decision: {} (hand_value: {})", call, hand_value);
        if call {
            let details = DecisionDetails {
                hand_value: Some(hand_value),
                success: None, // Will be updated after result
                ..Default::default()
            };
            self.track(state.round_number, "zapzap", details).await;
        }
        call
    }

    /// Async draw source selection: the draw the answer planned with the play made
    pub async fn decide_draw_source_async(
        &self,
        state: &GameState,
        player_index: u8,
    ) -> DrawSource {
        // If discard is empty, must draw from deck
        if state.last_cards_played.is_empty() {
            return DrawSource::Deck;
        }

        // Read, not taken: a draw write that loses its race comes back here on the same
        // state, and must find the same plan (a new play replaces it)
        let plan = self.turn_memo().draw.clone();
        let mut hand = state.get_hand(player_index).to_vec();
        hand.sort_unstable();
        let planned = plan
            .filter(|plan| plan.round == state.round_number && plan.hand == hand)
            .and_then(|plan| plan.draw);
        let source = match planned {
            Some(DrawChoice::Deck) => DrawSource::Deck,
            Some(DrawChoice::Card(card)) if state.last_cards_played.contains(&card) => {
                DrawSource::Discard(card)
            }
            // No plan for this hand (no service, a play that fell back, a restart since the
            // play), or a card no longer there
            _ => return self.fallback.decide_draw_source(state, player_index),
        };

        info!("LLM draw decision: {:?}", source);
        let details = DecisionDetails {
            source: Some(match &source {
                DrawSource::Deck => "deck".to_string(),
                DrawSource::Discard(card) => format!("discard:{}", card),
            }),
            ..Default::default()
        };
        self.track(state.round_number, "draw", details).await;
        source
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
    use crate::domain::services::execute_play;
    use crate::domain::value_objects::GameAction;
    use crate::infrastructure::services::{LlmError, MockLlmService};
    use std::sync::atomic::{AtomicUsize, Ordering};

    // Card ids: suit * 13 + rank, S 0, H 13, C 26, D 39; jokers 52, 53
    const AS: u8 = 0;
    const TWO_S: u8 = 1;
    const FIVE_S: u8 = 4;
    const SIX_S: u8 = 5;
    const KS: u8 = 12;
    const AH: u8 = 13;
    const TWO_H: u8 = 14;
    const SEVEN_H: u8 = 19;
    const KH: u8 = 25;
    const SEVEN_C: u8 = 32;
    const NINE_D: u8 = 47;
    const JKR: u8 = 52;

    /// Three players, seat 0 to play `hand`, the previous player's play `played` to draw
    /// from after it
    fn table(hand: &[u8], played: &[u8]) -> GameState {
        let mut state = GameState::new(3);
        state.hands[0] = hand.iter().copied().collect();
        state.hands[1] = [30, 31, 33, 34].into_iter().collect();
        state.hands[2] = [40, 41, 42, 43, 44].into_iter().collect();
        state.last_cards_played = [NINE_D].into_iter().collect();
        state.cards_played = played.iter().copied().collect();
        state.deck = (6..12).collect();
        state.current_turn = 0;
        state.current_action = GameAction::Play;
        state
    }

    /// A service answering `answer`, counting its calls
    struct Counted {
        answer: String,
        calls: AtomicUsize,
    }

    impl Counted {
        fn new(answer: &str) -> Arc<Self> {
            Arc::new(Self {
                answer: answer.to_string(),
                calls: AtomicUsize::new(0),
            })
        }
    }

    #[async_trait::async_trait]
    impl LlmService for Counted {
        async fn invoke(&self, _: &str, _: &str) -> Result<String, LlmError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            Ok(self.answer.clone())
        }

        async fn health_check(&self) -> bool {
            true
        }
    }

    fn bot(answer: &str) -> LlmBotStrategy {
        LlmBotStrategy::with_service(Arc::new(MockLlmService::new(answer)))
    }

    #[test]
    fn test_excerpt_cuts_on_a_character_boundary() {
        // A byte slice at 200 would cut the arrow's three bytes and panic
        let answer = format!("{}→ {{\"play\": 1}}", "a".repeat(199));
        assert_eq!(excerpt(&answer).chars().count(), 200);
        assert!(excerpt(&answer).ends_with('→'));
    }

    #[test]
    fn test_card_to_name() {
        assert_eq!(LlmBotStrategy::card_to_name(0), "AS");
        assert_eq!(LlmBotStrategy::card_to_name(12), "KS");
        assert_eq!(LlmBotStrategy::card_to_name(13), "AH");
        assert_eq!(LlmBotStrategy::card_to_name(52), "JKR");
    }

    #[test]
    fn test_prompt_counteract_penalty_matches_scoring() {
        let prompt = LlmBotStrategy::build_system_prompt_base();
        assert!(
            !prompt.contains("+20"),
            "the penalty depends on the player count"
        );
        assert!(prompt.contains(&format!(
            "plus {} points per other player still in the game",
            COUNTERACT_PENALTY_PER_OPPONENT
        )));

        // The per-player rate times the other active players is what scoring charges
        for active in 2..=8u8 {
            assert_eq!(
                counteract_penalty(active),
                (active as u16 - 1) * COUNTERACT_PENALTY_PER_OPPONENT
            );
        }
    }

    #[test]
    fn test_turn_question_numbers_the_plays_and_the_drawable_cards() {
        // KS KH JKR, the previous player played 5S 6S
        let state = table(&[KS, KH, JKR, AS], &[FIVE_S, SIX_S]);
        let question = LlmBotStrategy::turn_question(&state, 0);

        // No lone joker is offered (a joker pair neither)
        assert!(question.plays.iter().all(|p| p.iter().any(|&c| c != JKR)));
        assert!(question.plays.contains(&vec![KS, KH]));
        assert_eq!(question.drawable, vec![FIVE_S, SIX_S]);
        assert!(!question.zapzap);
        assert!(question
            .text
            .contains("Your hand: KS, KH, JKR, AS (worth 27 points"));
        assert!(question.text.contains("1: 5S\n2: 6S"));
        assert!(question.text.contains("the previous player played"));
        assert!(question
            .text
            .ends_with(r#"Answer {"play": <play number>, "draw": "deck" or <card number>}."#));
        assert!(!question.text.contains("<|"));

        // On the round's first play, the card turned up at the deal is the one to draw
        let first = table(&[KS, KH, AS], &[]);
        let question = LlmBotStrategy::turn_question(&first, 0);
        assert_eq!(question.drawable, vec![NINE_D]);
        assert!(question.text.contains("turned up at the deal"));
    }

    #[test]
    fn test_turn_question_offers_zapzap_with_its_cost() {
        // AS 2S JKR: worth 3; counteracted it scores 1 + 2 + 25 + 2 × 5
        let state = table(&[AS, TWO_S, JKR], &[FIVE_S]);
        let question = LlmBotStrategy::turn_question(&state, 0);

        assert!(question.zapzap);
        assert!(question.text.contains("Counteracted, you score 38 points."));
        assert!(question
            .text
            .contains(r#"Answer {"zapzap": true} to call it"#));
    }

    #[test]
    fn test_parse_turn_answer_reads_numbers_strictly() {
        let state = table(&[KS, KH, AS], &[FIVE_S, SIX_S]);
        let question = LlmBotStrategy::turn_question(&state, 0);
        let pair = question
            .plays
            .iter()
            .position(|p| *p == vec![KS, KH])
            .unwrap()
            + 1;

        let answer = LlmBotStrategy::parse_turn_answer(
            &format!("```json\n{{\"play\": {pair}, \"draw\": 2}}\n```"),
            &question,
        );
        assert_eq!(answer.play, Some(vec![KS, KH]));
        assert_eq!(answer.draw, Some(DrawChoice::Card(SIX_S)));
        assert_eq!(answer.zapzap, None, "not offered");

        let answer = LlmBotStrategy::parse_turn_answer(r#"{"play": 1, "draw": "deck"}"#, &question);
        assert_eq!(answer.draw, Some(DrawChoice::Deck));

        // A number written as a string is still that number
        let answer = LlmBotStrategy::parse_turn_answer(
            &format!(r#"{{"play": "{pair}", "draw": "1"}}"#),
            &question,
        );
        assert_eq!(answer.play, Some(vec![KS, KH]));
        assert_eq!(answer.draw, Some(DrawChoice::Card(FIVE_S)));

        // Off the list, of the wrong type, or no JSON: nothing settled
        for text in [
            r#"{"play": 0, "draw": 3}"#,
            r#"{"play": 99, "draw": -1}"#,
            r#"{"play": "first", "draw": "discard"}"#,
            r#"{"play": true, "draw": "5S"}"#,
            r#"{"play": 1.5}"#,
            "KS, KH then DISCARD",
            "{play: 1}",
        ] {
            let answer = LlmBotStrategy::parse_turn_answer(text, &question);
            assert_eq!(answer.play, None, "{text}");
            assert_eq!(answer.draw, None, "{text}");
        }
    }

    #[test]
    fn test_answer_object_is_the_last_object_of_the_text() {
        let state = table(&[KS, KH, AS], &[FIVE_S, SIX_S]);
        let question = LlmBotStrategy::turn_question(&state, 0);

        // An example object in the prose before the real answer
        let text = r#"The form is {"play": <n>, "draw": "deck"}, e.g. {"play": 99, "draw": 7}.
Answer: {"play": 1, "draw": 2}"#;
        let answer = LlmBotStrategy::parse_turn_answer(text, &question);
        assert_eq!(answer.play, Some(question.plays[0].clone()));
        assert_eq!(answer.draw, Some(DrawChoice::Card(SIX_S)));

        // An object nested in the answer is not the answer
        let object = LlmBotStrategy::answer_object(r#"{"play": 1, "why": {"play": 2}}"#).unwrap();
        assert_eq!(object["play"], 1);
    }

    #[tokio::test]
    async fn test_a_draw_that_loses_its_race_is_decided_again_from_the_plan() {
        // The previous player played 7H 7C; the model takes the 7C, which HardBot would
        // not (it pairs nothing): the draw write loses a race and the loop asks again on
        // the same state
        let hand = [TWO_S, KS, KH, NINE_D];
        let question = LlmBotStrategy::turn_question(&table(&hand, &[SEVEN_H, SEVEN_C]), 0);
        let kings = question
            .plays
            .iter()
            .position(|p| *p == vec![KS, KH])
            .unwrap()
            + 1;
        let llm = Counted::new(&format!(r#"{{"play": {kings}, "draw": 2}}"#));
        let strategy = LlmBotStrategy::with_service(llm.clone());
        let mut state = table(&hand, &[SEVEN_H, SEVEN_C]);
        let cards = strategy.select_cards_async(&state, 0).await;
        execute_play(&mut state, &cards).unwrap();
        assert_eq!(
            HardBotStrategy::new().decide_draw_source(&state, 0),
            DrawSource::Deck
        );

        for _ in 0..2 {
            assert_eq!(
                strategy.decide_draw_source_async(&state, 0).await,
                DrawSource::Discard(SEVEN_C)
            );
        }
        assert_eq!(llm.calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn test_a_turn_is_one_question() {
        // Eligible for ZapZap (AS 2S AH: 4 points): the check, the play and the draw read
        // one answer
        let llm = Counted::new(r#"{"zapzap": false, "play": 1, "draw": 1}"#);
        let strategy = LlmBotStrategy::with_service(llm.clone());
        let mut state = table(&[AS, TWO_S, AH], &[SEVEN_H]);

        assert!(!strategy.should_call_zapzap_async(&state, 0).await);
        let cards = strategy.select_cards_async(&state, 0).await;
        let first = LlmBotStrategy::turn_question(&state, 0).plays[0].clone();
        assert_eq!(cards, first);
        execute_play(&mut state, &cards).unwrap();
        assert_eq!(
            strategy.decide_draw_source_async(&state, 0).await,
            DrawSource::Discard(SEVEN_H)
        );
        assert_eq!(llm.calls.load(Ordering::SeqCst), 1);

        // Another situation is another question
        state.current_action = GameAction::Play;
        state.hands[0] = [KS, KH, NINE_D].into_iter().collect();
        strategy.select_cards_async(&state, 0).await;
        assert_eq!(llm.calls.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn test_an_invalid_play_falls_back_to_hard_bot() {
        let state = table(&[KS, KH, AS, SEVEN_C], &[FIVE_S]);
        let hard = HardBotStrategy::new().select_cards(&state, 0);

        for answer in [
            r#"{"play": 99, "draw": "deck"}"#,
            r#"{"play": 0}"#,
            "I play KS and KH",
            r#"{"play": 1"#,
        ] {
            let cards = bot(answer).select_cards_async(&state, 0).await;
            assert_eq!(cards, hard, "{answer}");
        }
        // A valid answer is the model's, not the fallback's
        let question = LlmBotStrategy::turn_question(&state, 0);
        let other = question.plays.iter().position(|p| *p != hard).unwrap() + 1;
        let cards = bot(&format!(r#"{{"play": {other}}}"#))
            .select_cards_async(&state, 0)
            .await;
        assert_ne!(cards, hard);
    }

    #[tokio::test]
    async fn test_an_invalid_zapzap_answer_falls_back_to_hard_bot() {
        // AS AH: worth 2, where HardBot calls
        let state = table(&[AS, AH], &[FIVE_S]);
        assert!(HardBotStrategy::new().should_call_zapzap(&state, 0));

        for answer in [
            r#"{"zapzap": "yes"}"#,
            r#"{"zapzap": 1}"#,
            "YES",
            r#"{"play": 1, "draw": "deck"}"#,
        ] {
            assert!(
                bot(answer).should_call_zapzap_async(&state, 0).await,
                "{answer}"
            );
        }
        // The model's own no is followed
        assert!(
            !bot(r#"{"zapzap": false, "play": 1, "draw": "deck"}"#)
                .should_call_zapzap_async(&state, 0)
                .await
        );
    }

    #[tokio::test]
    async fn test_an_invalid_draw_falls_back_to_hard_bot() {
        // The previous player played 2H, which pairs the 2S kept: HardBot takes it
        let hand = [TWO_S, KS, KH, NINE_D];
        let hard = {
            let mut state = table(&hand, &[TWO_H]);
            execute_play(&mut state, &[KS, KH]).unwrap();
            HardBotStrategy::new().decide_draw_source(&state, 0)
        };
        assert_eq!(hard, DrawSource::Discard(TWO_H));

        let question = LlmBotStrategy::turn_question(&table(&hand, &[TWO_H]), 0);
        let kings = question
            .plays
            .iter()
            .position(|p| *p == vec![KS, KH])
            .unwrap()
            + 1;
        for draw in ["2", "0", "\"discard\"", "\"2H\"", "null"] {
            let answer = format!(r#"{{"play": {kings}, "draw": {draw}}}"#);
            let strategy = bot(&answer);
            let mut state = table(&hand, &[TWO_H]);
            let cards = strategy.select_cards_async(&state, 0).await;
            assert_eq!(cards, vec![KS, KH], "{answer}");
            execute_play(&mut state, &cards).unwrap();
            assert_eq!(
                strategy.decide_draw_source_async(&state, 0).await,
                hard,
                "{answer}"
            );
        }

        // Malformed: the play and the draw both fall back
        let strategy = bot("{\"play\": ");
        let mut state = table(&hand, &[TWO_H]);
        let cards = strategy.select_cards_async(&state, 0).await;
        execute_play(&mut state, &cards).unwrap();
        let fallback = HardBotStrategy::new().decide_draw_source(&state, 0);
        assert_eq!(strategy.decide_draw_source_async(&state, 0).await, fallback);

        // The model's own deck draw is followed
        let strategy = bot(&format!(r#"{{"play": {kings}, "draw": "deck"}}"#));
        let mut state = table(&hand, &[TWO_H]);
        let cards = strategy.select_cards_async(&state, 0).await;
        execute_play(&mut state, &cards).unwrap();
        assert_eq!(
            strategy.decide_draw_source_async(&state, 0).await,
            DrawSource::Deck
        );
    }
}
