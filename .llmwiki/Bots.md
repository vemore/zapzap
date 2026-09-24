# Bots

> Scope: bot players in the Rust backend (`zapzap-rust/src/infrastructure/bot/`): difficulties, strategies, parameter provenance, LLM bot (Ollama / Bedrock) and its memory, how bot turns are triggered. Short pointer to the training-only strategies in `native/`.
> Related: [[Backend]] · [[Api]] · [[GameRules]] · [[NativeEngine]] · [[Architecture]]
> Updated: 2026-09-24

## Facts

### Bot users and difficulties
- A bot is a `users` row with `user_type = "bot"` and a `bot_difficulty` (`zapzap-rust/src/domain/entities/user.rs:15`, `:80`, constructor `new_bot` `:130`).
- `BotDifficulty` string values: `easy`, `medium`, `hard`, `hard_vince`, `thibot`, `drl`, `llm`, `ml` (`zapzap-rust/src/domain/entities/user.rs:44-66`).
- `GET /api/bots?difficulty=` accepts exactly those 8 values (lower-cased), else 400 "Invalid difficulty filter" (`zapzap-rust/src/api/routes/bots.rs:57-82`); lists via `user_repo.find_all_bots` (`bots.rs:89-91`). See [[Api]].
- Admins create and delete bots with `POST /api/bots` and `DELETE /api/bots/:botId` (since 2026-09-24, [[Api]]); `thibot` cannot be created that way (Node's list, `zapzap-rust/src/application/bot/create_bot.rs`). Bot users are otherwise seeded by the legacy Node script `scripts/init-bots.js` (EasyBot1/2, MediumBot1/2, HardBot1/2, Thibot1/2, `scripts/init-bots.js:24-31`); VinceBot and LlamaBot exist in the local DB but not in that script (created elsewhere in the Node era, commit 0185eb0 "create VinceBot").
- Bots join a party through `botIds` on party creation (`zapzap-rust/src/api/routes/party.rs:37`, `:280`).

### Strategy trait
- `BotStrategy` (sync): `select_hand_size`, `decide_action`, `select_cards`, `decide_draw_source`, `should_call_zapzap` (`zapzap-rust/src/infrastructure/bot/strategies/mod.rs:25-40`). `DrawSource::{Deck, Discard(card)}` (`mod.rs:51-54`).
- Shared helpers in `card_analyzer.rs`: `find_all_valid_plays` (`zapzap-rust/src/infrastructure/bot/card_analyzer.rs:266`), `would_complete_pair` (`:329`), `would_complete_sequence` (`:299`), `card_keep_score` (`:345`), `find_best_discard` (`:418`). The same module is used by the game rules (see [[GameRules]]).

### Difficulty → strategy mapping (runtime)
Mapping done inline, twice per trigger function, in `zapzap-rust/src/api/routes/game.rs` (manual trigger `:1108-1121`/`:1202-1215`, background trigger `:1520-1533`/`:1605-1618`):

| difficulty | strategy used | file |
|---|---|---|
| easy | `EasyBotStrategy` | `strategies/easy_bot.rs:16` |
| medium | `MediumBotStrategy` | `strategies/medium_bot.rs:17` |
| thibot | `ThibotStrategy` | `strategies/thibot.rs:124` |
| hard_vince | `VinceBotStrategy` | `strategies/vince_bot.rs:145` |
| llm | `LlmBotStrategy` (async path) | `strategies/llm_bot.rs:27` |
| hard, drl, ml, anything else | `HardBotStrategy` (catch-all `_`) | `strategies/hard_bot.rs:13` |

- `drl` and `ml` have **no Rust implementation**: they silently play as `hard` (`game.rs:1533`). The DRL/ML models in `data/` are only used by legacy Node (`src/infrastructure/bot/strategies/DRLBotStrategy.js`, `MLBotStrategy.js`) and native training ([[NativeEngine]]).
- Hand-size selection always uses `HardBotStrategy` whatever the difficulty (`game.rs:994`, `:1426`), so Easy's fixed 5, Thibot's 4 and Vince's 6-7 / 8-10 (`vince_bot.rs:576-582`) are dead code in the Rust backend.
- The trigger loop calls `should_call_zapzap`, never `decide_action` (`game.rs:1536`); in Hard/Medium the two disagree (e.g. Hard `decide_action` calls at ≤4 after round 3, `hard_bot.rs:52-55`, but `should_call_zapzap` only in golden score, `hard_bot.rs:129-132`).
- A new strategy instance is built for every single action (`game.rs:1520-1533`, `:1605-1618`), so stateful strategies lose their state between play and draw (see Thibot/Vince below).

### Rule-based strategies
- **Easy** (`easy_bot.rs`): random valid play (`:52-65`); ZapZap only if hand value ≤1 or one card (`:82-93`); draws from discard with probability 0.2 (`:72`).
- **Medium** (`medium_bot.rs`): 70% max-points play, 30% random (`:82`); discard if it completes a pair, or value ≤2 with 0.8 probability (`:105-117`); ZapZap at ≤3, one card, or ≤4 in golden score (`:124-149`).
- **Hard** (`hard_bot.rs`): hand size 4 in golden score else random 4-5 (`:28-38`); play maximising `points_removed*2 + cards_removed*3` (`:74-85`); discard if it completes a pair/sequence or is worth ≤2 (`:95-110`); ZapZap at ≤2, ≤4 in golden score, or one card (`:116-141`).

### Thibot (`strategies/thibot.rs`)
- Probability-based, tracks played/taken cards via `GameState.card_tracker` (`thibot.rs:1-9`; tracker `zapzap-rust/src/domain/value_objects/game_state.rs:62`).
- 33 tunable `ThibotParams` (`thibot.rs:23-68`); defaults hard-coded (`:70-115`), comment "44.25% winrate vs 40.55% baseline" (`:72`). Values equal the `optimized.params` block of `data/thibot_genetic_params.json` (e.g. jokerKeepScore 705, holdPairForThreeBonus 226, discardThreshold 8; file winRate 0.4425).
- Defensive mode when an opponent has ≤ `defensive_threshold` (3) cards: play max points (`thibot.rs:621-627`).
- ZapZap: always at 0 (`:719`), else `can_safely_zapzap` (`:159-204`).
- Coordinated play/draw: `select_cards` stores a target card in an `RwLock<CoordinatedDecision>` (`:630-637`) that `decide_draw_source` reads (`:660-664`). Because the backend recreates `ThibotStrategy::new()` for the draw (`game.rs:1613`), **this coordination never fires in the Rust backend**.

### VinceBot / hard_vince (`strategies/vince_bot.rs`)
- "11 strategic layers" (joker hoarding in golden score, card counting, opponent modelling, bad-hand fallback…) listed at `vince_bot.rs:1-14`.
- `VinceParams` defaults (`:81-128`) comment "optimized via genetic algorithm (74,000 games)"; they match `optimized.params` of `data/hard_vince_genetic_params.json` (goldenScoreJokerPenalty -393.857 → -393.86, highCardPairBreakingPenalty -168.99). `data/hard_vince_optimized_params.json` (grid search, `scripts/optimize-hard-vince.js:30`) is **not** used.
- Per-round `VinceMemory` in an `RwLock` (`:131-148`, update `:166-205`) — also reset every action by the per-action instantiation.
- ZapZap: 0 always; defensive if risk ≥ 0.13 and value ≤2; aggressive if avg opponent cards ≥ 5.38; else thresholds by round (`:586-631`).

### Parameter files in `data/`
- `data/thibot_genetic_params.json`, `data/hard_vince_genetic_params.json`: outputs of `scripts/genetic-optimize-thibot.js:33` (uses native engine, `:21`) and `scripts/genetic-optimize-hard-vince.js:33` (uses the legacy JS `HardVinceBotStrategy`, `:20`). Keys: baseline, optimized, config, generationStats, timestamp.
- **Nothing in `zapzap-rust/` reads any `data/*.json` params file** (no `with_params` caller); tuning is transferred by hand-copying values into `Default` impls.
- `data/ml_model_*.json`, `data/models/*.safetensors`, `data/models/default/` belong to legacy ML/DRL and native training ([[NativeEngine]]).
- `native/` maps `"hard_vince"` to its plain Hard strategy (`native/src/lib.rs:153`), so native simulations labelled hard_vince are not Vince.

### LLM bot
- `LlmBotStrategy` wraps an optional `LlmService` and a `HardBotStrategy` fallback (`llm_bot.rs:27-47`). Sync trait methods always use the fallback (`:614-641`); the trigger loop calls the async variants `should_call_zapzap_async` (`:393`), `select_cards_async` (`:292`), `decide_draw_source_async` (`:486`), each falling back on missing service or unparsable answer (e.g. `:298-300`, `:380-387`).
- Service selection at startup, priority Bedrock > Ollama > none (`zapzap-rust/src/infrastructure/app_state.rs:88-133`):
  - Bedrock only when compiled with feature `bedrock` (`zapzap-rust/Cargo.toml:60-62`) and `AWS_BEDROCK_ENABLED` or `AWS_ACCESS_KEY_ID` set (`app_state.rs:94-95`); `AWS_BEDROCK_REGION` default `us-east-1`, `AWS_BEDROCK_MODEL_ID` default `meta.llama3-3-70b-instruct-v1:0`, timeout 30 s (`zapzap-rust/src/infrastructure/services/llm_service.rs:178-184`).
  - Ollama when `OLLAMA_BASE_URL` or `ENABLE_LLM_BOTS` is set and `/api/tags` answers (`app_state.rs:119-129`, `llm_service.rs:154`); `OLLAMA_BASE_URL` default `http://localhost:11434`, `OLLAMA_MODEL` default `llama3.2`, timeout 60 s, temperature 0.3, max_tokens 512 (`llm_service.rs:44-54`); calls `POST {base}/api/generate` non-streaming (`:118-126`).
  - Otherwise LLM bots play exactly like Hard (`app_state.rs:132`).
- System prompt restates the rules (`llm_bot.rs:65-123`) — it says a counteracted caller gets "+20 points penalty" (`:100`), which is only true with 5 active players; the real rule is (active−1)×5 (`zapzap-rust/src/domain/services/game_service.rs:219`).
- Card notation in prompts: `RankSuit`, suits S/H/C/D, joker `JKR` (`llm_bot.rs:21`, `:147-154`); reflection prompt is in French with suits P/C/T/K (`zapzap-rust/src/application/bot/reflect_on_round.rs:136-166`, `:225`).

### LLM memory and reflection
- `LlmBotMemory` per bot, JSON file `{BOT_STRATEGIES_DIR}/{bot_user_id}.json`, default dir `data/bot-strategies` (`zapzap-rust/src/infrastructure/bot/llm_memory.rs:152-159`); atomic save via `.tmp` + rename (`:247-252`). `data/bot-strategies/` is untracked in git.
- Limits: 20 strategies, 5 per category, 50 recent decisions, 10 game summaries (`llm_memory.rs:48-51`). Categories: play_strategy, zapzap_timing, draw_decision, golden_score, opponent_reading (`:14-20`).
- Cached in `AppState.llm_memories`, loaded lazily (`app_state.rs:43`, `:158-175`).
- Decisions are recorded by the async LLM methods (`llm_bot.rs:372`, `:473`, `:601`). After a ZapZap (bot: `game.rs:1481`, `:1555`; human: `game.rs:679-719`), `trigger_llm_reflection` (`game.rs:1675`) spawns `ReflectOnRound` for every LLM bot in the party; it asks for 0-1 insight and stores it with confidence 0.5 (`reflect_on_round.rs:84-108`). `score_change` is always 0 ("Would need to calculate this", `game.rs:1736`).
- The memory write lock is held across the LLM call (`reflect_on_round.rs:58` → `:84`), blocking that bot's next decisions for up to the service timeout.
- The manual `trigger-bot` path never triggers reflection.

### How bot turns are triggered
- No scheduler and no startup recovery (`zapzap-rust/src/main.rs:20-63`): bots move only when some request spawns `trigger_bot_internal` (`game.rs:1313`):
  - after `GET /api/game/:id/state` (100 ms delay, `game.rs:343-350`) — i.e. every client poll;
  - after select-hand-size, play, draw (300 ms, `game.rs:436-441`, `:523-528`, `:610-615`) and next-round when the starter is a bot (`:803-808`).
- Loop: up to 50 iterations if an active human remains, else 500 (`game.rs:1332-1346`); stops on human turn or finished round; 200 ms between bot actions (`:1668`). Eliminated bots are skipped by advancing `current_turn` (`:1395-1411`). A failed discard draw falls back to deck (`:1638-1652`). Each action broadcasts a `gameUpdate` SSE with `isBot: true` (e.g. `:1446-1452`).
- Manual `POST /api/game/:partyId/trigger-bot` (auth required, no party-membership check; `zapzap-rust/src/api/routes/mod.rs:164-169`) runs the same logic synchronously, max 50 iterations, 100 ms pause (`game.rs:846-1309`).
- There is no per-party lock: concurrent polls can start several `trigger_bot_internal` loops for the same party; use-case turn checks (`NotYourTurn`) limit but do not prevent double reads of the same state.

### Native strategies (training only)
- `native/src/strategies/`: `hard_bot.rs`, `thibot.rs`, `drl_strategy.rs` (DuelingDQN inference) plus `RandomBotStrategy` in `mod.rs`; different trait (`select_play`, `should_zapzap`, `select_draw_source`, `select_hand_size`, `native/src/strategies/mod.rs:15-27`). Not linked into the backend. See [[NativeEngine]].

## Decisions & History
- Strategies were first written in JS (`src/infrastructure/bot/strategies/*.js`: Easy/Medium/Hard 2025-11/12, HardVince 2025-12-08 commit 6fab137, Thibot 2025-12-18 commit e445ed5, DRL/ML 2025-12-10 commit 40c795a) and ported to Rust in the backend rewrite e4f83da (2025-12-23); DRL and ML were not ported, hence the catch-all to Hard.
- Bedrock integration dates from 5838e7d (2025-12-10); LLM memory/reflection from 13e1514 and d43e199 (2025-12-20).
- Background triggering with 50/500 iteration caps replaced client-driven triggering in 8a3509b (2025-12-23: "adjust iteration limits based on player types"); the Node backend also had restart recovery of pending bot turns (c116041) that was not ported — polling of `GET state` now plays that role.
- Thibot coordination (cbdc7ac/00fb843, 2025-12-21) was designed for a long-lived strategy instance (JS factory); the Rust per-action instantiation silently disables it.
