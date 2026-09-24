//! Bot turns
//!
//! Bots move when a request triggers them: every state poll and every game action asks
//! for the bots of its party to play. A party runs **one bot loop at a time**: a trigger
//! that arrives while a loop runs only marks the party pending, and the running loop
//! goes round once more before it lets go. Each bot of a party keeps **one strategy
//! instance for the whole game**, so what a strategy remembers between two calls
//! (Thibot's play/draw coordination, VinceBot's round memory) survives from its play to
//! its draw and from one turn to the next.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::Mutex as AsyncMutex;

use crate::application::bot::{ReflectOnRound, ReflectOnRoundInput, RoundOutcome};
use crate::application::game::{
    CallZapZap, CallZapZapInput, DrawCard, DrawCardInput, PlayCards, PlayCardsInput,
    SelectHandSize, SelectHandSizeInput,
};
use crate::domain::entities::{BotDifficulty, PartyStatus};
use crate::domain::repositories::{PartyRepository, UserRepository};
use crate::domain::value_objects::{GameAction, GameState};
use crate::infrastructure::app_state::{AppState, GameEvent};
use crate::infrastructure::bot::card_analyzer::calculate_hand_value;
use crate::infrastructure::bot::strategies::{
    BotStrategy, DrawSource, EasyBotStrategy, HardBotStrategy, LlmBotStrategy, MediumBotStrategy,
    ThibotStrategy, VinceBotStrategy,
};

/// Pause between two bot actions, so clients can follow them
const ACTION_PAUSE: Duration = Duration::from_millis(200);
/// Most bot actions one loop takes while a human is still in the game
const MAX_ACTIONS_WITH_HUMANS: usize = 50;
/// Most bot actions one loop takes when only bots remain (they play the game out)
const MAX_ACTIONS_BOTS_ONLY: usize = 500;

/// A bot's decision maker: a rule-based strategy, or the LLM bot and its async calls
#[derive(Clone)]
pub enum BotBrain {
    Rules(Arc<dyn BotStrategy>),
    Llm(Arc<LlmBotStrategy>),
}

impl BotBrain {
    /// The strategy a difficulty plays with. `drl` and `ml` have no Rust strategy and
    /// play as `hard`.
    fn for_difficulty(difficulty: Option<BotDifficulty>) -> Arc<dyn BotStrategy> {
        match difficulty {
            Some(BotDifficulty::Easy) => Arc::new(EasyBotStrategy::new()),
            Some(BotDifficulty::Medium) => Arc::new(MediumBotStrategy::new()),
            Some(BotDifficulty::Thibot) => Arc::new(ThibotStrategy::new()),
            Some(BotDifficulty::HardVince) => Arc::new(VinceBotStrategy::new()),
            _ => Arc::new(HardBotStrategy::new()),
        }
    }

    fn select_hand_size(&self, state: &GameState, player_index: u8) -> u8 {
        let wanted = match self {
            Self::Rules(s) => s.select_hand_size(state, player_index),
            Self::Llm(s) => s.select_hand_size(state, player_index),
        };
        // The strategy picks, the rules bound it (select_hand_size.rs)
        let max = if state.is_golden_score { 10 } else { 7 };
        wanted.clamp(4, max)
    }

    async fn should_call_zapzap(&self, state: &GameState, player_index: u8) -> bool {
        match self {
            Self::Rules(s) => s.should_call_zapzap(state, player_index),
            Self::Llm(s) => s.should_call_zapzap_async(state, player_index).await,
        }
    }

    async fn select_cards(&self, state: &GameState, player_index: u8) -> Vec<u8> {
        match self {
            Self::Rules(s) => s.select_cards(state, player_index),
            Self::Llm(s) => s.select_cards_async(state, player_index).await,
        }
    }

    async fn decide_draw_source(&self, state: &GameState, player_index: u8) -> DrawSource {
        match self {
            Self::Rules(s) => s.decide_draw_source(state, player_index),
            Self::Llm(s) => s.decide_draw_source_async(state, player_index).await,
        }
    }
}

/// The bots of one party: one brain per bot user, built on the bot's first move
#[derive(Default)]
pub struct Roster {
    brains: HashMap<String, BotBrain>,
}

impl Roster {
    /// The brain of `user_id`, the same instance on every call for the whole game
    pub async fn brain(
        &mut self,
        state: &AppState,
        user_id: &str,
        difficulty: Option<BotDifficulty>,
    ) -> BotBrain {
        if let Some(brain) = self.brains.get(user_id) {
            return brain.clone();
        }
        let brain = if difficulty == Some(BotDifficulty::Llm) {
            let memory = state.get_llm_memory(user_id).await;
            BotBrain::Llm(Arc::new(LlmBotStrategy::new(
                state.llm_service.clone(),
                Some(memory),
            )))
        } else {
            BotBrain::Rules(BotBrain::for_difficulty(difficulty))
        };
        self.brains.insert(user_id.to_string(), brain.clone());
        brain
    }
}

/// One party's slot: the roster, locked while a loop runs, and the pending flag
#[derive(Default)]
struct PartySlot {
    pending: AtomicBool,
    roster: AsyncMutex<Roster>,
}

/// What ended a bot loop
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LoopEnd {
    /// A human is to move, or the round waits for its next-round call
    Waiting,
    /// The party has no game state or is over: its bots are dropped
    GameOver,
    /// The action cap was reached
    Capped,
}

/// The per-party bot loops of the server (one per `AppState`)
#[derive(Default)]
pub struct BotRunner {
    parties: Mutex<HashMap<String, Arc<PartySlot>>>,
}

impl BotRunner {
    pub fn new() -> Self {
        Self::default()
    }

    fn slot(&self, party_id: &str) -> Arc<PartySlot> {
        let mut parties = self.parties.lock().unwrap_or_else(|e| e.into_inner());
        parties.entry(party_id.to_string()).or_default().clone()
    }

    fn forget(&self, party_id: &str, slot: &Arc<PartySlot>) {
        let mut parties = self.parties.lock().unwrap_or_else(|e| e.into_inner());
        if parties.get(party_id).is_some_and(|s| Arc::ptr_eq(s, slot)) {
            parties.remove(party_id);
        }
    }

    /// Number of parties whose bots are kept in memory
    pub fn party_count(&self) -> usize {
        self.parties.lock().unwrap_or_else(|e| e.into_inner()).len()
    }
}

/// Trigger the bots of `party_id` after `delay`, in the background
pub fn spawn_bot_turns(state: &Arc<AppState>, party_id: String, delay: Duration) {
    let state = state.clone();
    tokio::spawn(async move {
        tokio::time::sleep(delay).await;
        if let Err(e) = trigger_bot_turns(&state, &party_id).await {
            tracing::error!("Bot turns of party {} failed: {}", party_id, e);
        }
    });
}

/// Let the bots of `party_id` play until a human is to move. Returns at once when a loop
/// already runs for the party: that loop goes round again before it ends.
pub async fn trigger_bot_turns(state: &Arc<AppState>, party_id: &str) -> Result<(), String> {
    let runner = &state.bot_runner;
    let slot = runner.slot(party_id);
    slot.pending.store(true, Ordering::SeqCst);
    loop {
        let Ok(mut roster) = slot.roster.try_lock() else {
            // The running loop sees `pending` before it lets go
            return Ok(());
        };
        while slot.pending.swap(false, Ordering::SeqCst) {
            let end = run_bot_loop(state, party_id, &mut roster).await;
            match end {
                Ok((LoopEnd::GameOver, _)) => {
                    drop(roster);
                    runner.forget(party_id, &slot);
                    return Ok(());
                }
                Ok(_) => {}
                Err(e) => {
                    slot.pending.store(false, Ordering::SeqCst);
                    return Err(e);
                }
            }
        }
        drop(roster);
        // A trigger that came between the last check and the unlock found the lock taken
        if !slot.pending.load(Ordering::SeqCst) {
            return Ok(());
        }
    }
}

/// Run the bots of `party_id` now, waiting for a running loop to end first (the manual
/// `trigger-bot` route). Returns the number of actions taken.
pub async fn run_bot_turns_now(state: &Arc<AppState>, party_id: &str) -> Result<usize, String> {
    let runner = &state.bot_runner;
    let slot = runner.slot(party_id);
    let mut roster = slot.roster.lock().await;
    slot.pending.store(false, Ordering::SeqCst);
    let (end, actions) = run_bot_loop(state, party_id, &mut roster).await?;
    drop(roster);
    if end == LoopEnd::GameOver {
        runner.forget(party_id, &slot);
    }
    Ok(actions)
}

/// Whether a human who is not eliminated sits in the party
async fn has_active_human(
    state: &AppState,
    party_id: &str,
    game_state: &GameState,
) -> Result<bool, String> {
    let players = state
        .party_repo
        .get_party_players(party_id)
        .await
        .map_err(|e| e.to_string())?;
    for player in &players {
        if game_state.is_eliminated(player.player_index) {
            continue;
        }
        if let Ok(Some(user)) = state.user_repo.find_by_id(&player.user_id).await {
            if user.user_type.as_str() == "human" {
                return Ok(true);
            }
        }
    }
    Ok(false)
}

/// Play bot moves until a human is to move or the round ends; the caller holds the
/// party's roster, so no other loop runs for this party meanwhile.
async fn run_bot_loop(
    state: &Arc<AppState>,
    party_id: &str,
    roster: &mut Roster,
) -> Result<(LoopEnd, usize), String> {
    match state.party_repo.find_by_id(party_id).await {
        Ok(Some(party)) if party.status == PartyStatus::Playing => {}
        Ok(_) => return Ok((LoopEnd::GameOver, 0)),
        Err(e) => return Err(e.to_string()),
    }
    let Some(initial) = state
        .party_repo
        .get_game_state(party_id)
        .await
        .map_err(|e| e.to_string())?
    else {
        return Ok((LoopEnd::GameOver, 0));
    };
    let max_actions = if has_active_human(state, party_id, &initial).await? {
        MAX_ACTIONS_WITH_HUMANS
    } else {
        MAX_ACTIONS_BOTS_ONLY
    };

    let mut actions = 0;
    for _ in 0..max_actions {
        let Some(game_state) = state
            .party_repo
            .get_game_state(party_id)
            .await
            .map_err(|e| e.to_string())?
        else {
            return Ok((LoopEnd::GameOver, actions));
        };
        if matches!(
            game_state.current_action,
            GameAction::Finished | GameAction::ZapZap
        ) {
            return Ok((LoopEnd::Waiting, actions));
        }

        let players = state
            .party_repo
            .get_party_players(party_id)
            .await
            .map_err(|e| e.to_string())?;
        let Some(current) = players
            .iter()
            .find(|p| p.player_index == game_state.current_turn)
        else {
            return Ok((LoopEnd::Waiting, actions));
        };
        let Some(user) = state
            .user_repo
            .find_by_id(&current.user_id)
            .await
            .map_err(|e| e.to_string())?
        else {
            return Ok((LoopEnd::Waiting, actions));
        };
        if user.user_type.as_str() != "bot" {
            return Ok((LoopEnd::Waiting, actions));
        }

        // An eliminated bot on turn: hand the turn on to the next active seat
        if game_state.is_eliminated(current.player_index) {
            let mut next_turn = (game_state.current_turn + 1) % game_state.player_count;
            let mut attempts = 0;
            while game_state.is_eliminated(next_turn) && attempts < game_state.player_count {
                next_turn = (next_turn + 1) % game_state.player_count;
                attempts += 1;
            }
            let mut updated = game_state.clone();
            updated.current_turn = next_turn;
            if let Err(e) = state.party_repo.save_game_state(party_id, &updated).await {
                tracing::error!("Failed to update game state: {}", e);
            }
            continue;
        }

        let player_index = current.player_index;
        let user_id = user.id.clone();
        let brain = roster.brain(state, &user_id, user.bot_difficulty).await;

        match game_state.current_action {
            GameAction::SelectHandSize => {
                let hand_size = brain.select_hand_size(&game_state, player_index);
                tracing::info!("Bot {} selecting hand size {}", user.username, hand_size);
                SelectHandSize::new(state.party_repo.clone())
                    .execute(SelectHandSizeInput {
                        party_id: party_id.to_string(),
                        user_id: user_id.clone(),
                        hand_size,
                    })
                    .await
                    .map_err(|e| e.to_string())?;
                broadcast_bot_event(
                    state,
                    party_id,
                    &user_id,
                    "selectHandSize",
                    serde_json::json!({"handSize": hand_size, "isBot": true}),
                );
            }
            GameAction::Play => {
                if brain.should_call_zapzap(&game_state, player_index).await {
                    tracing::info!("Bot {} calling ZapZap", user.username);
                    let result = CallZapZap::new(state.party_repo.clone())
                        .execute(CallZapZapInput {
                            party_id: party_id.to_string(),
                            user_id: user_id.clone(),
                        })
                        .await
                        .map_err(|e| e.to_string())?;
                    broadcast_bot_event(
                        state,
                        party_id,
                        &user_id,
                        "zapzap",
                        serde_json::json!({"isBot": true}),
                    );
                    trigger_llm_reflection(
                        state,
                        party_id,
                        game_state.round_number as u32,
                        Some(player_index),
                        result.counteracted,
                    )
                    .await;
                } else {
                    let cards = brain.select_cards(&game_state, player_index).await;
                    if cards.is_empty() {
                        return Err(format!("Bot {} has no valid play", user.username));
                    }
                    tracing::info!("Bot {} playing {:?}", user.username, cards);
                    PlayCards::new(state.party_repo.clone())
                        .execute(PlayCardsInput {
                            party_id: party_id.to_string(),
                            user_id: user_id.clone(),
                            card_ids: cards.clone(),
                        })
                        .await
                        .map_err(|e| e.to_string())?;
                    broadcast_bot_event(
                        state,
                        party_id,
                        &user_id,
                        "play",
                        serde_json::json!({"cardIds": cards, "isBot": true}),
                    );
                }
            }
            GameAction::Draw => {
                let (source, card_id) =
                    match brain.decide_draw_source(&game_state, player_index).await {
                        DrawSource::Deck => ("deck", None),
                        DrawSource::Discard(card) => ("played", Some(card)),
                    };
                tracing::info!("Bot {} drawing from {}", user.username, source);
                let drawn = DrawCard::new(state.party_repo.clone())
                    .execute(DrawCardInput {
                        party_id: party_id.to_string(),
                        user_id: user_id.clone(),
                        source: source.to_string(),
                        card_id,
                    })
                    .await;
                // A discard pick that fails falls back to the deck
                let source = match drawn {
                    Ok(_) => source,
                    Err(_) => {
                        DrawCard::new(state.party_repo.clone())
                            .execute(DrawCardInput {
                                party_id: party_id.to_string(),
                                user_id: user_id.clone(),
                                source: "deck".to_string(),
                                card_id: None,
                            })
                            .await
                            .map_err(|e| e.to_string())?;
                        "deck"
                    }
                };
                broadcast_bot_event(
                    state,
                    party_id,
                    &user_id,
                    "draw",
                    serde_json::json!({"source": source, "isBot": true}),
                );
            }
            GameAction::Finished | GameAction::ZapZap => {
                return Ok((LoopEnd::Waiting, actions));
            }
        }
        actions += 1;

        tokio::time::sleep(ACTION_PAUSE).await;
    }

    tracing::warn!("Bot loop of party {} hit its action cap", party_id);
    Ok((LoopEnd::Capped, actions))
}

fn broadcast_bot_event(
    state: &AppState,
    party_id: &str,
    user_id: &str,
    action: &str,
    data: serde_json::Value,
) {
    let event = GameEvent::new(
        "gameUpdate",
        Some(party_id.to_string()),
        Some(user_id.to_string()),
    )
    .with_action(action)
    .with_data(data);
    state.broadcast_event(event);
}

/// What a finished round meant for `player_index`, read from the round-end state
pub fn round_outcome(
    game_state: &GameState,
    player_index: u8,
    zapzap_caller_idx: Option<u8>,
    was_counteracted: bool,
) -> RoundOutcome {
    let hand = game_state.get_hand(player_index);
    let is_caller = zapzap_caller_idx == Some(player_index);
    // The points this round added to the player's total
    let round_score = game_state
        .round_scores
        .map(|scores| scores[player_index as usize]);
    let won = if is_caller {
        !was_counteracted
    } else if let Some(score) = round_score {
        // Every player tied at the lowest hand scores 0
        score == 0
    } else {
        game_state.lowest_hand_player_index == Some(player_index)
    };
    RoundOutcome {
        won,
        counteracted: is_caller && was_counteracted,
        score_change: round_score.map_or(0, |s| i16::try_from(s).unwrap_or(i16::MAX)),
        hand_points: calculate_hand_value(hand),
        final_hand: hand.to_vec(),
        is_golden_score: game_state.is_golden_score,
    }
}

/// After a round ends, every LLM bot of the party reflects on it, in the background
pub async fn trigger_llm_reflection(
    state: &Arc<AppState>,
    party_id: &str,
    round_number: u32,
    zapzap_caller_idx: Option<u8>,
    was_counteracted: bool,
) {
    let Some(ref llm_service) = state.llm_service else {
        return;
    };
    let game_state = match state.party_repo.get_game_state(party_id).await {
        Ok(Some(gs)) => gs,
        Ok(None) | Err(_) => return,
    };
    let players = match state.party_repo.get_party_players(party_id).await {
        Ok(p) => p,
        Err(_) => return,
    };

    for player in &players {
        let user = match state.user_repo.find_by_id(&player.user_id).await {
            Ok(Some(u)) => u,
            _ => continue,
        };
        if user.bot_difficulty != Some(BotDifficulty::Llm) {
            continue;
        }

        let memory = state.get_llm_memory(&player.user_id).await;
        let outcome = round_outcome(
            &game_state,
            player.player_index,
            zapzap_caller_idx,
            was_counteracted,
        );
        let reflect = ReflectOnRound::new(llm_service.clone());
        let input = ReflectOnRoundInput {
            bot_user_id: player.user_id.clone(),
            party_id: party_id.to_string(),
            round_number,
            outcome,
        };
        tokio::spawn(async move {
            let result = reflect.execute(input, memory).await;
            if result.success {
                tracing::info!(
                    "LLM reflection completed: {} insights generated",
                    result.insights_generated
                );
            } else if let Some(reason) = result.reason {
                tracing::debug!("LLM reflection skipped: {}", reason);
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::services::{execute_zapzap, initialize_round};

    #[test]
    fn test_round_outcome_records_the_real_score_change() {
        // Caller 0 holds 4 and is counteracted by players 1 and 2 (2 points each)
        let mut gs = initialize_round(4, 5, &[10, 20, 30, 40, 0, 0, 0, 0], 0, 3, 0, Some(1));
        let hands: [&[u8]; 4] = [&[1, 14], &[0, 13], &[26, 39], &[12, 25]];
        for (i, hand) in hands.iter().enumerate() {
            gs.hands[i].clear();
            gs.hands[i].extend(hand.iter().copied());
        }
        gs.current_turn = 0;
        gs.current_action = GameAction::Play;
        let before = gs.scores;
        let result = execute_zapzap(&mut gs).unwrap();

        for p in 0..4u8 {
            let outcome = round_outcome(&gs, p, Some(0), result.counteracted);
            let delta = gs.scores[p as usize] - before[p as usize];
            assert_eq!(outcome.score_change, delta as i16, "player {p}");
        }
        let caller = round_outcome(&gs, 0, Some(0), true);
        assert_eq!(caller.score_change, 4 + 15);
        assert!(caller.counteracted && !caller.won);
        // Both tied lowest hands won the round
        assert!(round_outcome(&gs, 1, Some(0), true).won);
        assert!(round_outcome(&gs, 2, Some(0), true).won);
        let loser = round_outcome(&gs, 3, Some(0), true);
        assert_eq!(loser.score_change, 26);
        assert!(!loser.won);
    }

    #[test]
    fn test_hand_size_is_bounded_by_the_rules() {
        let brain = BotBrain::Rules(Arc::new(VinceBotStrategy::new()));
        let mut gs = GameState::new(4);
        for _ in 0..20 {
            assert!((4..=7).contains(&brain.select_hand_size(&gs, 0)));
        }
        gs.is_golden_score = true;
        for _ in 0..20 {
            assert!((4..=10).contains(&brain.select_hand_size(&gs, 0)));
        }
    }
}
