//! The LLM bot against HardBots, over whole games, on AWS Bedrock (paid calls).
//!
//! ```text
//! cargo run --release --features bedrock --example llm_benchmark -- \
//!     <games> <players> <max_usd> <usd_per_million_in> <usd_per_million_out>
//! ```
//!
//! One LLM bot and `players - 1` HardBots play `games` games (the LLM bot's seat and the
//! first starter rotate), with the game rules the backend plays (`game_service.rs`), no
//! database, no pause and no reflection. The model comes from `AWS_BEDROCK_MODEL_ID` and
//! `AWS_BEDROCK_REGION`, as in the backend. No game starts once the spend reaches
//! `max_usd`. `BENCH_NO_LLM=1` plays the LLM seat with no service (its HardBot fallback),
//! free: the harness's baseline. `RUST_LOG=warn` shows each answer that falls back.

use std::sync::Arc;
use std::time::{Duration, Instant};

use zapzap_backend::domain::services::{
    check_eliminations, execute_draw, execute_play, execute_zapzap, hand_size_bounds,
    initialize_round, is_game_over,
};
use zapzap_backend::domain::value_objects::GameAction;
use zapzap_backend::infrastructure::bot::strategies::{
    BotStrategy, DrawSource, HardBotStrategy, LlmBotStrategy,
};
use zapzap_backend::infrastructure::services::{
    BedrockConfig, BedrockService, LlmService, LlmUsage,
};

/// Turns after which a round counts as stalled and the game is dropped
const MAX_TURNS_PER_ROUND: usize = 400;

struct Args {
    games: usize,
    players: u8,
    max_usd: f64,
    usd_in: f64,
    usd_out: f64,
}

fn args() -> Args {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let get = |i: usize, default: &str| a.get(i).cloned().unwrap_or_else(|| default.to_string());
    Args {
        games: get(0, "10").parse().expect("games"),
        players: get(1, "3").parse().expect("players"),
        max_usd: get(2, "0.3").parse().expect("max_usd"),
        usd_in: get(3, "0.15")
            .parse()
            .expect("usd per million input tokens"),
        usd_out: get(4, "0.60")
            .parse()
            .expect("usd per million output tokens"),
    }
}

fn cost(usage: LlmUsage, a: &Args) -> f64 {
    (usage.input_tokens as f64 * a.usd_in + usage.output_tokens as f64 * a.usd_out) / 1e6
}

/// How one game ended for the LLM bot
enum Outcome {
    Won,
    Lost,
    Stalled,
}

#[derive(Default)]
struct Tally {
    rounds: usize,
    llm_turns: usize,
    llm_time: Duration,
}

async fn play_game(
    llm: &LlmBotStrategy,
    llm_seat: u8,
    first_starter: u8,
    players: u8,
    tally: &mut Tally,
) -> Outcome {
    let hard = HardBotStrategy::new();
    let mut scores = [0u16; 8];
    let mut eliminated = 0u8;
    let mut round = 1u16;
    let mut starter = first_starter;

    loop {
        // The starter picks the hand size (the LLM bot uses its HardBot fallback for it)
        let probe = initialize_round(players, 4, &scores, eliminated, round, starter, None);
        let (min, max) = hand_size_bounds(&probe);
        let hand_size = hard.select_hand_size(&probe, starter).clamp(min, max);
        let mut state = initialize_round(
            players, hand_size, &scores, eliminated, round, starter, None,
        );
        let flipped = state.deck.pop().expect("a card to turn up");
        state.last_cards_played.push(flipped);
        state.current_action = GameAction::Play;
        tally.rounds += 1;

        let mut turns = 0;
        loop {
            turns += 1;
            if turns > MAX_TURNS_PER_ROUND {
                return Outcome::Stalled;
            }
            let seat = state.current_turn;
            let is_llm = seat == llm_seat;
            let started = Instant::now();

            let zapzap = if is_llm {
                llm.should_call_zapzap_async(&state, seat).await
            } else {
                hard.should_call_zapzap(&state, seat)
            };
            if zapzap {
                if is_llm {
                    tally.llm_turns += 1;
                    tally.llm_time += started.elapsed();
                }
                execute_zapzap(&mut state).expect("a ZapZap the rules allow");
                break;
            }

            let cards = if is_llm {
                llm.select_cards_async(&state, seat).await
            } else {
                hard.select_cards(&state, seat)
            };
            execute_play(&mut state, &cards).expect("a valid play");
            let source = if is_llm {
                llm.decide_draw_source_async(&state, seat).await
            } else {
                hard.decide_draw_source(&state, seat)
            };
            if is_llm {
                tally.llm_turns += 1;
                tally.llm_time += started.elapsed();
            }
            let drawn = match source {
                DrawSource::Deck => execute_draw(&mut state, false, None),
                DrawSource::Discard(card) => execute_draw(&mut state, true, Some(card)),
            };
            // A failed pick falls back to the deck, as the bot loop does
            if drawn.is_err() {
                execute_draw(&mut state, false, None).expect("a card to draw");
            }
        }

        check_eliminations(&mut state);
        if let Some(winner) = is_game_over(&state) {
            return if winner == llm_seat {
                Outcome::Won
            } else {
                Outcome::Lost
            };
        }
        scores = state.scores;
        eliminated = state.eliminated_mask;
        round += 1;
        // The next active seat starts the next round
        starter = (1..=players)
            .map(|k| (starter + k) % players)
            .find(|&s| !state.is_eliminated(s))
            .expect("an active seat");
    }
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "error".into()),
        )
        .init();
    let a = args();
    let no_llm = std::env::var("BENCH_NO_LLM").is_ok_and(|v| v == "1");

    let service = if no_llm {
        None
    } else {
        Some(Arc::new(
            BedrockService::new(BedrockConfig::default()).await,
        ))
    };
    let model = service
        .as_ref()
        .map_or("none (HardBot fallback)".to_string(), |s| {
            s.model_id().to_string()
        });
    let usage = || service.as_ref().map(|s| s.usage()).unwrap_or_default();

    let (mut won, mut lost, mut stalled) = (0, 0, 0);
    let mut tally = Tally::default();
    for game in 0..a.games {
        let spent = cost(usage(), &a);
        if spent >= a.max_usd {
            println!("budget reached ({spent:.4} USD): stopping before game {game}");
            break;
        }
        let llm = LlmBotStrategy::new(service.clone().map(|s| s as Arc<dyn LlmService>), None)
            .for_party(&format!("bench-{game}"));
        let seat = (game % a.players as usize) as u8;
        let starter = ((game / a.players as usize) % a.players as usize) as u8;
        let outcome = play_game(&llm, seat, starter, a.players, &mut tally).await;
        match outcome {
            Outcome::Won => won += 1,
            Outcome::Lost => lost += 1,
            Outcome::Stalled => stalled += 1,
        }
        let u = usage();
        println!(
            "game {game}: {} (seat {seat}), {} rounds so far, {} calls, {:.4} USD so far",
            match outcome {
                Outcome::Won => "won",
                Outcome::Lost => "lost",
                Outcome::Stalled => "stalled",
            },
            tally.rounds,
            u.calls,
            cost(u, &a)
        );
    }

    let played = won + lost;
    let u = usage();
    println!("model: {model}");
    println!(
        "games: {played} ({stalled} stalled), LLM bot won {won}: {:.0}% (1/{} = {:.0}% for an even match)",
        100.0 * won as f64 / played.max(1) as f64,
        a.players,
        100.0 / a.players as f64
    );
    println!(
        "rounds: {} ({:.1} a game), LLM turns: {} ({:.1} a game)",
        tally.rounds,
        tally.rounds as f64 / played.max(1) as f64,
        tally.llm_turns,
        tally.llm_turns as f64 / played.max(1) as f64
    );
    println!(
        "calls: {}, tokens in {} / out {} ({:.0} / {:.0} a call)",
        u.calls,
        u.input_tokens,
        u.output_tokens,
        u.input_tokens as f64 / u.calls.max(1) as f64,
        u.output_tokens as f64 / u.calls.max(1) as f64
    );
    println!(
        "mean LLM turn: {:.2} s; cost {:.4} USD, {:.4} USD a game",
        tally.llm_time.as_secs_f64() / tally.llm_turns.max(1) as f64,
        cost(u, &a),
        cost(u, &a) / played.max(1) as f64
    );
}
