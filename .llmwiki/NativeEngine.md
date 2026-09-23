# NativeEngine

> Scope: `native/` — the Rust cdylib (napi) simulation engine used offline for DRL training and genetic tuning of bots, plus the Node scripts in `scripts/` that drive it. Not used by either backend at runtime except the legacy Node Thibot's optional load.
> Related: [[Architecture]] · [[Bots]] · [[GameRules]] · [[Testing]]
> Updated: 2026-09-23

## Facts

### Crate and build
| Item | Value | Source |
|---|---|---|
| Crate | `zapzap-native` 0.1.0, edition 2021, `crate-type = ["cdylib"]` | `native/Cargo.toml:1-8` |
| Bindings | `napi` 2 (features `napi4`, `serde-json`), `napi-derive` 2, `napi-build` in `build.rs` | `native/Cargo.toml:12-13`, `native/build.rs:1-5` |
| ML | `burn` 0.16 (no default features) + `burn-ndarray`, `burn-autodiff` (CPU only; feature `cpu`, GPU "can be added later") | `native/Cargo.toml:20-23,36-39` |
| Other deps | `rand` 0.8 (small_rng), `smallvec`, `rayon`, `num_cpus`, `serde`, `safetensors` 0.4 | `native/Cargo.toml:16-33` |
| Release profile | `lto = true`, `opt-level = 3` | `native/Cargo.toml:41-43` |
| Toolchain | pinned `1.92` + rustfmt, clippy | `native/rust-toolchain.toml:3-4` |
| Node build | `npm run build` = `napi build --platform --release` (needs `@napi-rs/cli` ^2.18.0); `npm test` = `cargo test` | `native/package.json:14-21` |
| JS entry | `index.js` (napi loader, committed) + `index.d.ts` typings; built `*.node` is gitignored | `native/package.json:4-5`, `.gitignore:123` |
| Lockfile | `native/Cargo.lock` is gitignored and untracked (unlike `zapzap-rust/Cargo.lock`) | `.gitignore:122` |
| Lint | `#![deny(clippy::all)]` at crate root; CI and the commit hook run `cargo clippy --all-targets -- -D warnings` | `native/src/lib.rs:5`, `native` job of `.github/workflows/ci.yml`, `.claude/hooks/guard-bash.sh` |
| Ad-hoc JS checks | `native/benchmark.js`, `native/test-comparison.js`, `native/test-ml-components.js` (not wired into npm/CI) | `native/` |

Consumers: only `scripts/train-native.js` (`require('../native/index.js')`, `scripts/train-native.js:486`), `scripts/genetic-optimize-thibot.js:21`, and the legacy Node Thibot bot, which falls back to JS if the addon is missing (`src/infrastructure/bot/strategies/ThibotBotStrategy.js:20-23`). `zapzap-rust` does not depend on it.

### Modules (`native/src/`)
| Module | Role | Source |
|---|---|---|
| `card_analyzer` | card points/rank/suit, hand value, validation, play enumeration, keep/discard heuristics | `native/src/card_analyzer.rs` |
| `game_state` | compact `GameState`: `MAX_PLAYERS` 8, `MAX_HAND_SIZE` 10, `CardTracker` bitmask of cards taken from discard | `native/src/game_state.rs:8,10,40-47,50` |
| `headless_engine` | full game loop, scoring, golden score, transition collection | `native/src/headless_engine.rs` |
| `feature_extractor` | `FEATURE_DIM` = 45 features per decision | `native/src/feature_extractor.rs:10,20,262` |
| `lightweight_dqn` | pure-Rust inference net 45→256→128→64→32 (older, used by `dqn_*` exports) | `native/src/lightweight_dqn.rs:1-6` |
| `fast_dqn` | flat-array Dueling DQN matching the burn net (45→128→64, value 64→32→1, heads 64→32→[7,2,5,2]); ~14x faster than LightweightDQN | `native/src/fast_dqn.rs:1-13`, `native/src/strategies/drl_strategy.rs:11` |
| `strategies` | `BotStrategy` trait + Random, Hard, Thibot, DRL | `native/src/strategies/mod.rs:15-27` |
| `training` | burn DuelingDQN, PER buffer, SumTree, collector, trainer, model I/O | `native/src/training/mod.rs:1-28` |
| `trace_config` | global atomic trace flags: game, buffer, training, weights, features | `native/src/trace_config.rs:9-13` |

### Card and rule implementation (engine side)
- Card id: rank = `id % 13`, suit = `id / 13`, jokers `>= 52` (`JOKER_START`) → rank/suit 255 (`native/src/card_analyzer.rs:9,27-47`).
- Points: rank+1 (A=1..K=13), joker 0 for eligibility (`native/src/card_analyzer.rs:12,17-23,52-54`); end-of-round score joker = 25 unless `is_lowest` (`:58-73`).
- ZapZap eligibility: hand value `<= 5` (`native/src/card_analyzer.rs:76-78`).
- Sequence: >= 3 cards, same suit, gaps filled by jokers; all-joker set counts as valid (`native/src/card_analyzer.rs:103-144`).
- Hand size clamped to 4..7, or 4..10 in golden score (`native/src/headless_engine.rs:671-675`); only the round's starting player chooses it.
- ZapZap resolution: counteracted if any other player's hand value `<=` caller's; counteracted caller gets hand score + (active-1)×5, others except the lowest get their hand score; otherwise everyone but the caller scores (`native/src/headless_engine.rs:503-575`). Note: `calculate_hand_score(.., false)` is used for everyone, so jokers always count 25 in scoring (`:536-538`).
- Elimination at score `> 100`; golden score when exactly 2 remain (`native/src/headless_engine.rs:581-590`); golden-score winner = lowest hand, caller loses ties (`:635-654`, tests `:827-895`); otherwise lowest total wins (`:657-668`).
- Starting player rotates from previous starter, skipping eliminated (`native/src/headless_engine.rs:592-598`).
- Safety caps: 100 rounds per game (`native/src/headless_engine.rs:109,138`), 1000 turns per round (`:223,330`).

### Strategies
| Type string (napi) | Enum | Notes | Source |
|---|---|---|---|
| `random` (and any unknown string) | `Random` | plays first card, always zapzaps when eligible, always draws from deck, hand size 5 | `native/src/strategies/mod.rs:30-62` |
| `hard`, **`hard_vince`** | `Hard` | `hard_vince` is silently mapped to plain Hard; deterministic seed 12345; hand size 4-6 random in golden score | `native/src/lib.rs:154-157`, `native/src/strategies/hard_bot.rs:16,198-200` |
| `thibot` | `Thibot` | tracks played/taken cards; params in `static mut THIBOT_PARAMS` (genetically optimized: "44.25% winrate vs 40.55% baseline", 30 gens × 2000 games) mutated via `unsafe` | `native/src/strategies/thibot.rs:1-8,99-105,155,192-202` |
| `drl` | `DRL` | `DRLStrategy` over `FastDQN`, default epsilon 0.1, random init unless weights synced | `native/src/strategies/drl_strategy.rs:34-60` |

Hard and Thibot are re-instantiated with `::new()` on every decision (`native/src/headless_engine.rs:714-777`), so no per-game memory lives in the strategy object itself (card tracking is in `GameState`).

### Training (DRL)
- Network: Dueling DQN with 4 advantage heads, `ACTION_DIMS` = [7 handSize, 2 zapzap, 5 playType, 2 drawSource]; Q = V + (A − mean A) (`native/src/training/dueling_dqn.rs:17-22,101-218`). Comment says handSize "3-9 cards" but engine maps 4-10 → 0-6 (`dueling_dqn.rs:19` vs `native/src/headless_engine.rs:207`).
- `TrainingConfig::default`: input 45, hidden 128, value 64, advantage 32, lr 0.0005, gamma 0.99, tau 0.005, batch 64, grad clip 1.0, buffer 1_000_000, PER alpha 0.6, beta 0.4→1.0, per_epsilon 0.01, epsilon 1.0→0.01 over 100_000 steps, games_per_batch 100, train_interval 10, target_update_freq 1000, save_interval 10_000, workers = CPU count (`native/src/training/config.rs:43-81`). Presets `fast()` / `production()` (`:85-106`). Epsilon and beta decay linearly (`:109-118`).
- `trainer_create` (napi) builds its own config: buffer from JS, input 45, hidden 128/64/32, train_interval 10, save_interval 10000 (`native/src/lib.rs:704-738`); napi-side defaults (`NativeTrainingConfig::default`): total_games 100000, buffer 100000, epsilon_decay 50000 (`native/src/lib.rs:645-660`).
- Optimizer: Adam (0.9, 0.999, 1e-8) (`native/src/training/trainer.rs:83-87`). Adaptive batch per decision: handSize batch/4 (min 8), zapzap batch/8 (min 4) (`trainer.rs:131-140`).
- Replay: prioritized (SumTree, O(log n), IS weights) (`native/src/training/replay_buffer.rs:10-14`, `native/src/training/sum_tree.rs`).
- Rewards: engine uses `finalize_simple` — sparse, only last transition gets +1.0 (win) / −0.25 (loss) (`native/src/headless_engine.rs:152-158`, `native/src/training/collector.rs:159-184`). The collector module doc still describes dense potential-based shaping (`collector.rs:5-10`); `finalize_dense` exists but is unused by the engine (`collector.rs:223`).
- Weight sync to simulated DRL players each game via `set_drl_weights` (burn → FastDQN flat layout) (`native/src/lib.rs:313`, `native/src/headless_engine.rs:90`).
- Model I/O: single `weights` F32 tensor in `.safetensors`, JSON metadata under key `metadata` (`native/src/training/model_io.rs:93-135`). `trainer_save_model` writes `TrainingConfig::default()` as metadata, not the config actually used (`native/src/lib.rs:1056-1073`).
- Checked-in models: `data/models/rust-drl.safetensors`, `data/models/rust-drl-hard.safetensors` (+ untracked checkpoints), `data/models/default/{config,weights}.json` (legacy JS model) — `git ls-files data`.

### napi exports (`native/src/lib.rs`, camelCase in JS)
| Group | Functions | Lines |
|---|---|---|
| Cards | getCardPoints, getRank, getSuit, isJoker, calculateHandValue, calculateHandScore, canCallZapzap, isValidSameRank, isValidSequence, isValidPlay, findSameRankPlays, findSequencePlays, findAllValidPlays, findMaxPointPlay, benchmarkFindAllValidPlays | 27-123 |
| Simulation | runGame(strategies, seed?), runGamesBatch(strategies, n, baseSeed?) → {gamesPlayed, wins, avgRounds, totalTimeMs, gamesPerSecond}, runTrainingBatch(strategies, n, drlIdx, epsilon, baseSeed?), benchmarkSimulation(playerCount, gameCount) → number | 148-411 |
| Features | getFeatureDimension, extractFeatures, extractHandSizeFeatures, benchmarkFeatureExtraction | 421-499 |
| LightweightDQN | dqnInit, dqnPredict, dqnSelectAction, dqnGreedyAction, benchmarkDqnInference (global `DQN_INSTANCE`) | 529-590 |
| Trainer | trainerCreate → bool, trainerGetState, trainerAddTransition, trainerBufferSize, trainerTrainSteps, trainerRequestStop, trainerShouldStop, trainerGetWeights, trainerSetWeights(weights) (global `TRAINER`) | 698-875 |
| DRL strategy | drlStrategyInit, drlStrategySetEpsilon, drlStrategyGetAction | 886-930 |
| Model I/O | modelSave, modelSaveCheckpoint, modelLoad, modelLoadWithMetadata, modelExists, trainerSaveModel, modelGetMetadata | 996-1091 |
| Tuning/debug | setTraceConfig, thibotSetParams, thibotGetDefaultParams | 1109, 1194, 1236 |

### Driver scripts
**`scripts/train-native.js`** (native): modes `--train/-t`, `--bench`, default = batch simulation (`scripts/train-native.js:66-78`). Defaults: games 1000, strategies `hard,hard,hard,hard`, batch-size 64, lr 0.0005, epsilon 1.0→0.01 over 50000, gamma 0.99, tau 0.005, save-path `data/models/rust-drl`, save-interval 10000, games-per-batch 100 (`:36-63`); `--load/-l`, `--seed`, `--quiet`, `--trace=game,buffer,training,weights,features|all`, `--debug` (`:105-126`). Training requires a `drl` entry in `--strategies` (`:286-291`), passes bufferCapacity 1000000 and targetUpdateFreq 1000 (`:255-256`), trains `min(100, buffer/batch/4)` steps per batch once buffer ≥ 10×batch (`:329-339`), checkpoints to `<save-path>_checkpoint_<games>.safetensors` (`:372-374`).

**`scripts/genetic-optimize-thibot.js`** (native): fitness = win rate of `thibot` vs 3 `hard` via `runGamesBatch` (`scripts/genetic-optimize-thibot.js:305-326`). Defaults: generations 30, population 16 (forced even), elite 2, mutation 0.1, mutation-range 0.3, crossover 0.7, games 2000, output `data/thibot_genetic_params.json`, `--seed` (`:25-72`). Nothing reads the output file back; tuned values are hand-copied into `ThibotParams::default` / `THIBOT_PARAMS`.

**Not native** (legacy Node JS engine in `src/simulation/`): `scripts/run-simulation.js` (JS `SimulationRunner`/`ParallelDRLRunner`/curriculum; defaults games 10000, strategies `ml,hard,medium,easy`, workers min(12, CPUs), `--drl`, `--pretrain`, `--curriculum`; `scripts/run-simulation.js:15-22,29-40,110-130`), `scripts/genetic-optimize-hard-vince.js` (JS `HardVinceBotStrategy` + worker threads; same GA defaults, output `data/hard_vince_genetic_params.json`; `scripts/genetic-optimize-hard-vince.js:20,24-35`), `scripts/optimize-hard-vince.js` (parameter sweep). CLAUDE.md's `genetic-optimize-hard.js` does not exist.

### Known defects
- `--bench` is broken: calls `benchmarkSimulation(1000, [...])` against signature `(playerCount, gameCount)` and reads `.gamesPerSecond/.totalMs/.opsPerSecond` from functions that return a plain number (`scripts/train-native.js:191-206` vs `native/src/lib.rs:394,499,590`).
- `--load` cannot resume training: script calls `trainerSetWeights(trainerId, weights)` (first arg is the boolean from `trainerCreate`) while the export takes only `weights` (`scripts/train-native.js:260,277` vs `native/src/lib.rs:865`); and even when called correctly `DuelingDQN::set_weights_flat` is a documented no-op (`native/src/training/dueling_dqn.rs:318-324`).
- Double DQN / target network not implemented: target network is `#[allow(dead_code)]`, TD target uses the online network, soft update is a TODO; `tau` and `target_update_freq` have no effect (`native/src/training/trainer.rs:49-51,177-190,326-329`).
- `hard_vince` silently equals `hard` in the native engine (`native/src/lib.rs:155`), so any "vs hard_vince" native result is really vs hard.

### Tests
98 `#[test]` functions across 19 modules (`grep -rn '#\[test\]' native/src`). Run `cd native && cargo test` (see [[Testing]]); CI runs `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings` and `cargo test`, all without `--locked` (`native` job of `.github/workflows/ci.yml`).

## Decisions & History
- 2025-12-15: HardBotStrategy (`9a1d37f`), SumTree + DRL Trainer with parallel simulation (`5698009`), then switch to sparse terminal rewards "for improved learning efficiency" (`3ef3afd`) — explains the stale dense-reward doc in `collector.rs`.
- FastDQN was introduced to mirror the burn DuelingDQN layout for cheap in-simulation inference and weight sync (`6e2cc04`, `55c4378`; `native/src/fast_dqn.rs:3-13`).
- Thibot added (`e445ed5`), later coordination/safety timeout (`cbdc7ac`); golden-score-by-lowest-hand (`d5df375`) and starting-player rotation (`4ee11f8`) were applied to the engine at the same time as the backend.
- `rust-toolchain.toml` pins 1.92 so the commit hook and CI share one rustfmt/clippy (`native/rust-toolchain.toml:1`, commit `0773216`, squash-merged as `1e063d6`).
