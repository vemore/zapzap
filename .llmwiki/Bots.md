# Bots

> Scope: bot players in the Rust backend (`zapzap-rust/src/infrastructure/bot/`): difficulties, strategies, parameter provenance, LLM bot (Ollama / Bedrock) and its memory, how bot turns are triggered. Short pointer to the training-only strategies in `native/`.
> Related: [[Backend]] · [[Api]] · [[GameRules]] · [[NativeEngine]] · [[Architecture]]
> Updated: 2026-09-25

## Facts

### Bot users and difficulties
- A bot is a `users` row with `user_type = "bot"` and a `bot_difficulty` (`zapzap-rust/src/domain/entities/user.rs:15`, `:80`, constructor `new_bot` `:130`).
- `BotDifficulty` string values: `easy`, `medium`, `hard`, `hard_vince`, `thibot`, `drl`, `llm`, `ml` (`zapzap-rust/src/domain/entities/user.rs:44-66`).
- `GET /api/bots?difficulty=` accepts exactly those 8 values (lower-cased), else 400 "Invalid difficulty filter" (`zapzap-rust/src/api/routes/bots.rs:57-82`); lists via `user_repo.find_all_bots` (`bots.rs:89-91`). See [[Api]].
- Admins create and delete bots with `POST /api/bots` and `DELETE /api/bots/:botId` (since 2026-09-24, [[Api]]); `thibot` cannot be created that way (Node's list, `zapzap-rust/src/application/bot/create_bot.rs`). Bot users are otherwise seeded by the legacy Node script `scripts/init-bots.js` (EasyBot1/2, MediumBot1/2, HardBot1/2, Thibot1/2, `scripts/init-bots.js:24-31`); VinceBot and LlamaBot exist in the local DB but not in that script (created elsewhere in the Node era, commit 0185eb0 "create VinceBot").
- Bots join a party through `botIds` on party creation (`zapzap-rust/src/api/routes/party.rs:33`, `:291`), or later one at a time: the owner of a waiting party fills a free seat with `POST /api/party/:partyId/bots {botId}` (`party.rs:572`, use case `zapzap-rust/src/application/party/add_bot_to_party.rs`; Rust only, see [[Api]]).

### Strategy trait
- `BotStrategy` (sync): `select_hand_size`, `decide_action`, `select_cards`, `decide_draw_source`, `should_call_zapzap` (`zapzap-rust/src/infrastructure/bot/strategies/mod.rs:25-40`). `DrawSource::{Deck, Discard(card)}` (`mod.rs:51-54`).
- Shared helpers in `card_analyzer.rs`: `find_all_valid_plays` (`zapzap-rust/src/infrastructure/bot/card_analyzer.rs:266`), `would_complete_pair` (`:329`), `would_complete_sequence` (`:299`), `card_keep_score` (`:345`), `find_best_discard` (`:418`). The same module is used by the game rules (see [[GameRules]]).

### Difficulty → strategy mapping (runtime)
Mapping done once, in `BotBrain::for_difficulty` (`zapzap-rust/src/application/bot/runner.rs`):

| difficulty | strategy used | file |
|---|---|---|
| easy | `EasyBotStrategy` | `strategies/easy_bot.rs:16` |
| medium | `MediumBotStrategy` | `strategies/medium_bot.rs:17` |
| thibot | `ThibotStrategy` | `strategies/thibot.rs:124` |
| hard_vince | `VinceBotStrategy` | `strategies/vince_bot.rs:145` |
| llm | `LlmBotStrategy` (async path) | `strategies/llm_bot.rs:27` |
| hard, drl, ml, anything else | `HardBotStrategy` (catch-all `_`) | `strategies/hard_bot.rs:13` |

- `drl` and `ml` have **no Rust implementation**: they silently play as `hard` (the catch-all of `for_difficulty`). The DRL/ML models in `data/` are only used by legacy Node (`src/infrastructure/bot/strategies/DRLBotStrategy.js`, `MLBotStrategy.js`) and native training ([[NativeEngine]]).
- Each bot picks its own hand size (`BotBrain::select_hand_size`): Easy 5, Medium/Hard 4-5, Thibot 4, Vince 6-7 / 8-10 in Golden Score (`vince_bot.rs:576-582`), clamped to what `SelectHandSize` accepts (4-7, 4-10 in Golden Score); the LLM bot uses its Hard fallback.
- The trigger loop calls `should_call_zapzap`, never `decide_action`; in Hard/Medium the two disagree (e.g. Hard `decide_action` calls at ≤4 after round 3, `hard_bot.rs:52-55`, but `should_call_zapzap` only in golden score, `hard_bot.rs:129-132`).
- **One strategy instance per bot per party, for the whole game**: the party's `Roster` (`runner.rs`) builds a bot's brain on its first move and returns the same instance afterwards, so what a strategy remembers survives from its play to its draw and across turns and rounds (tests `test_a_bot_keeps_its_strategy_for_the_game`, `zapzap-rust/tests/rules_and_bots_tests.rs`, and `test_draw_follows_the_play_on_the_same_instance`, `thibot.rs`). The roster lives as long as the party plays, in memory: a restart starts the strategies afresh.

### Rule-based strategies
- **Easy** (`easy_bot.rs`): random valid play (`:52-65`); ZapZap only if hand value ≤1 or one card (`:82-93`); draws from discard with probability 0.2 (`:72`).
- **Medium** (`medium_bot.rs`): 70% max-points play, 30% random (`:82`); discard if it completes a pair, or value ≤2 with 0.8 probability (`:105-117`); ZapZap at ≤3, one card, or ≤4 in golden score (`:124-149`).
- **Hard** (`hard_bot.rs`): hand size 4 in golden score else random 4-5 (`:28-38`); play maximising `points_removed*2 + cards_removed*3` (`:74-85`); discard if it completes a pair/sequence or is worth ≤2 (`:95-110`); ZapZap at ≤2, ≤4 in golden score, or one card (`:116-141`).

### Thibot (`strategies/thibot.rs`)
- Probability-based, tracks played/taken cards via `GameState.card_tracker` (`thibot.rs:1-9`; tracker `zapzap-rust/src/domain/value_objects/game_state.rs:112`).
- 33 tunable `ThibotParams` (`thibot.rs:23-68`); defaults hard-coded (`:70-115`), comment "44.25% winrate vs 40.55% baseline" (`:72`). Values equal the `optimized.params` block of `data/thibot_genetic_params.json` (e.g. jokerKeepScore 705, holdPairForThreeBonus 226, discardThreshold 8; file winRate 0.4425).
- Defensive mode when an opponent has ≤ `defensive_threshold` (3) cards: play max points (`thibot.rs:621-627`).
- ZapZap: always at 0 (`:719`), else `can_safely_zapzap` (`:159-204`).
- Coordinated play/draw: `select_cards` stores a target card in an `RwLock<CoordinatedDecision>` that `decide_draw_source` reads (`coordinated_target()` exposes it). The backend keeps the instance between the play and the draw (see above), so the draw follows the plan when the target is still drawable. The plan is made on `last_cards_played` *before* the play, which a later play of the round moves to the discard pile: only on the first play of a round is the target still there at the draw.

### VinceBot / hard_vince (`strategies/vince_bot.rs`)
- "11 strategic layers" (joker hoarding in golden score, card counting, opponent modelling, bad-hand fallback…) listed at `vince_bot.rs:1-14`.
- `VinceParams` defaults (`:81-128`) comment "optimized via genetic algorithm (74,000 games)"; they match `optimized.params` of `data/hard_vince_genetic_params.json` (goldenScoreJokerPenalty -393.857 → -393.86, highCardPairBreakingPenalty -168.99). `data/hard_vince_optimized_params.json` (grid search, `scripts/optimize-hard-vince.js:30`) is **not** used.
- Per-round `VinceMemory` in an `RwLock` (`:131-148`, update `:166-205`), reset by the strategy itself when the round number changes; kept between actions since the strategy lives for the game.
- ZapZap: 0 always; defensive if risk ≥ 0.13 and value ≤2; aggressive if avg opponent cards ≥ 5.38; else thresholds by round (`:586-631`).

### Parameter files in `data/`
- `data/thibot_genetic_params.json`, `data/hard_vince_genetic_params.json`: outputs of `scripts/genetic-optimize-thibot.js:33` (uses native engine, `:21`) and `scripts/genetic-optimize-hard-vince.js:33` (uses the legacy JS `HardVinceBotStrategy`, `:20`). Keys: baseline, optimized, config, generationStats, timestamp.
- **Nothing in `zapzap-rust/` reads any `data/*.json` params file** (no `with_params` caller); tuning is transferred by hand-copying values into `Default` impls.
- `data/ml_model_*.json`, `data/models/*.safetensors`, `data/models/default/` belong to legacy ML/DRL and native training ([[NativeEngine]]).
- `native/` maps `"hard_vince"` to its plain Hard strategy (`native/src/lib.rs:153`), so native simulations labelled hard_vince are not Vince.

### LLM bot
- `LlmBotStrategy` wraps an optional `LlmService` and a `HardBotStrategy` fallback (`llm_bot.rs:27-47`). Sync trait methods always use the fallback (`:614-641`); the trigger loop calls the async variants `should_call_zapzap_async` (`:393`), `select_cards_async` (`:292`), `decide_draw_source_async` (`:486`), each falling back on missing service or unparsable answer (e.g. `:298-300`, `:380-387`).
- Service selection at startup, priority Bedrock > Ollama > none (`AppState::new`, `zapzap-rust/src/infrastructure/app_state.rs:120-162`). Each service has a switch and a key (`llm_enabled`): the switch, when present, decides alone — on unless empty, `false` or `0`; only without it does the key, set and not empty, turn the service on (tests `test_llm_switch_present_decides_alone`, `test_llm_switch_absent_falls_back_on_the_key`).
  - Bedrock only when compiled with feature `bedrock` (`zapzap-rust/Cargo.toml:60-62`; image build arg `CARGO_FEATURES=bedrock`), switch `AWS_BEDROCK_ENABLED`, key `AWS_ACCESS_KEY_ID` (so `AWS_BEDROCK_ENABLED=false` keeps Bedrock off even with AWS keys); `AWS_BEDROCK_REGION` default `us-east-1`, `AWS_BEDROCK_MODEL_ID` default `meta.llama3-3-70b-instruct-v1:0`, timeout 30 s (`zapzap-rust/src/infrastructure/services/llm_service.rs:178-184`).
  - Ollama with switch `ENABLE_LLM_BOTS`, key `OLLAMA_BASE_URL`, when `/api/tags` answers (`llm_service.rs:154`); `OLLAMA_BASE_URL` default `http://localhost:11434`, `OLLAMA_MODEL` default `llama3.2`, timeout 60 s, temperature 0.3, max_tokens 512 (`llm_service.rs:44-54`); calls `POST {base}/api/generate` non-streaming (`:118-126`).
  - Otherwise LLM bots play exactly like Hard.
- System prompt restates the rules (`build_system_prompt_base`, `llm_bot.rs`). Its counteract penalty text is built from `COUNTERACT_PENALTY_PER_OPPONENT` (`zapzap-rust/src/domain/services/game_service.rs`), the constant scoring charges with (`counteract_penalty`: (active − 1) × 5); the ZapZap question states the penalty for the current number of active players. `test_prompt_counteract_penalty_matches_scoring` pins the two together; the French reflection prompt takes the same constant.
- Card notation in prompts: `RankSuit`, suits S/H/C/D, joker `JKR` (`llm_bot.rs:21`, `:147-154`); reflection prompt is in French with suits P/C/T/K (`zapzap-rust/src/application/bot/reflect_on_round.rs:136-166`, `:225`).

### LLM memory and reflection
- `LlmBotMemory` per bot, JSON file `{BOT_STRATEGIES_DIR}/{bot_user_id}.json`, default dir `data/bot-strategies` (read once into `AppState.bot_strategies_dir`, `zapzap-rust/src/infrastructure/app_state.rs`); atomic save via `.tmp` + rename (`llm_memory.rs` `save`). `data/bot-strategies/` is gitignored.
- A directory that cannot be created or written (root-owned on the NAS, the image runs as uid 1000) never fails a bot turn: `load` warns and starts empty, and `save_or_keep`, which the reflection calls, warns once and keeps the memory in the process (lost at restart). Tests: `test_llm_bots_play_on_when_the_strategies_dir_is_not_writable` (`zapzap-rust/tests/rules_and_bots_tests.rs`), `test_reflection_in_a_read_only_strategies_dir_keeps_the_insights_in_memory` (`reflect_on_round.rs`).
- Limits: 20 strategies, 5 per category, 50 recent decisions, 10 game summaries (`llm_memory.rs:48-51`). Categories: play_strategy, zapzap_timing, draw_decision, golden_score, opponent_reading (`:14-20`).
- Cached in `AppState.llm_memories`, loaded lazily (`app_state.rs:72`, `:187-205`).
- Decisions are recorded by the async LLM methods, keyed by party and round (`"{party}:{round}"`, `llm_memory.rs` `round_key`): the same bot in two parties keeps two sets, and a reflection reads and clears only its own party's round. After a ZapZap (a bot's, in the bot loop; a human's, from `game.rs`), `trigger_llm_reflection` (`zapzap-rust/src/application/bot/runner.rs`) spawns `ReflectOnRound` for every LLM bot in the party; it asks for 0-1 insight and stores it with confidence 0.5. The outcome comes from `round_outcome`: `score_change` is the points the round added to the bot's total (`round_scores`), and every player tied at the lowest hand counts as having won the round (test `test_round_outcome_records_the_real_score_change`).
- Reflection copies the round's decisions under a read lock and releases the memory before the LLM call; it takes the write lock only to store the insight and save (test `test_reflection_releases_the_memory_during_the_llm_call`, a held mock LLM).

### How bot turns are triggered
- No scheduler and no startup recovery (`zapzap-rust/src/main.rs`): bots move only when a request triggers them — `GET /api/game/:id/state` (100 ms delay), select-hand-size, play, draw and next-round (300 ms) call `spawn_bot_turns` (`zapzap-rust/src/application/bot/runner.rs`). Details, the per-party lock and the caps: [[Backend]] "Bot triggering".
- **One bot loop at a time per party**: a trigger that arrives while the party's loop runs marks the party pending and returns; the running loop goes round again. Test `test_concurrent_triggers_run_one_bot_loop` fires six state polls and six triggers at once on a bot's turn and sees one play and one draw per bot.
- Loop: stops on a human's turn or a finished round; a pause of `BOT_ACTION_DELAY_MS` after each bot action (1000 ms by default, as Node; production sets 2000). Eliminated bots are skipped by advancing `current_turn`. A failed discard draw falls back to the deck. Each action broadcasts a `gameUpdate` SSE with `isBot: true`.
- Manual `POST /api/game/:partyId/trigger-bot` (party members only, `require_party_member`; route `zapzap-rust/src/api/routes/mod.rs:174`) runs the same loop through the same lock (`run_bot_turns_now`), after the running loop if any; a trigger that came meanwhile is served after it.

### Native strategies (training only)
- `native/src/strategies/`: `hard_bot.rs`, `thibot.rs`, `drl_strategy.rs` (DuelingDQN inference) plus `RandomBotStrategy` in `mod.rs`; different trait (`select_play`, `should_zapzap`, `select_draw_source`, `select_hand_size`, `native/src/strategies/mod.rs:15-27`). Not linked into the backend. See [[NativeEngine]].

## Decisions & History
- 2026-09-24 (fix/rust-before-switch): the pause between bot actions comes from `BOT_ACTION_DELAY_MS`, as on Node, because production sets 2000 ms so that players can follow the bots, and Rust's fixed 200 ms made them a blur. An unwritable strategies directory is a warning rather than an error: the memory is a learning aid, not state a game needs.
- 2026-09-24 (fix/rust-rules-and-bots): strategies are kept per bot for the game and bot loops serialised per party ([[Backend]]); hand size delegated to each strategy, bounded by `hand_size_bounds` (`game_service.rs`: 4-7, 4-10 in Golden Score, and at most (54 − 1) / active players, which `SelectHandSize` enforces too); the LLM prompt's "+20" replaced by text built from the scoring constant; reflection no longer holds the memory lock during the LLM call and records the real score change. `data/*params.json` are still not read (the `Default` impls carry the same values).
- Strategies were first written in JS (`src/infrastructure/bot/strategies/*.js`: Easy/Medium/Hard 2025-11/12, HardVince 2025-12-08 commit 6fab137, Thibot 2025-12-18 commit e445ed5, DRL/ML 2025-12-10 commit 40c795a) and ported to Rust in the backend rewrite e4f83da (2025-12-23); DRL and ML were not ported, hence the catch-all to Hard.
- Bedrock integration dates from 5838e7d (2025-12-10); LLM memory/reflection from 13e1514 and d43e199 (2025-12-20).
- Background triggering with 50/500 iteration caps replaced client-driven triggering in 8a3509b (2025-12-23: "adjust iteration limits based on player types"); the Node backend also had restart recovery of pending bot turns (c116041) that was not ported — polling of `GET state` now plays that role.
- Thibot coordination (cbdc7ac/00fb843, 2025-12-21) was designed for a long-lived strategy instance (JS factory); the Rust per-action instantiation silently disables it.
