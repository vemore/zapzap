# Backend

> Scope: the Rust backend in `zapzap-rust/` (axum 0.7, sqlx 0.8 sqlite, tokio) — layout, state, config, auth, SSE, sessions, bot triggering, LLM service, DB schema situation. Routes are in [[Api]].
> Related: [[Architecture]] · [[Api]] · [[Bots]] · [[Testing]] · [[GameRules]]
> Updated: 2026-09-24

## Facts

### Crate
- Package `zapzap-backend` 0.1.0, edition 2021 (`zapzap-rust/Cargo.toml:2`). Binary `main.rs` + library `lib.rs` exposing the same four modules (`zapzap-rust/src/lib.rs:4-7`) so `tests/` can build the router.
- Both roots carry `#![allow(dead_code)]` "for features under development" (`zapzap-rust/src/main.rs:2`, `zapzap-rust/src/lib.rs:2`).
- Only cargo feature: `bedrock = ["aws-config", "aws-sdk-bedrockruntime"]`, not default (`zapzap-rust/Cargo.toml:58-60`). The Dockerfile builds with plain `cargo build --release` (`zapzap-rust/Dockerfile:30`), so the image has **no Bedrock**.
- Password crates: `argon2 = "0.5"` and `bcrypt = "0.15"` "for verifying existing bcrypt hashes during migration" (`zapzap-rust/Cargo.toml:24-25`). `reqwest` with rustls is commented "for Google OAuth" (`zapzap-rust/Cargo.toml:45-46`) but no Google route exists (see [[Api]]).
- Clippy `should_implement_trait` allowed crate-wide (`zapzap-rust/Cargo.toml:54-56`). Release profile: `lto = true`, `codegen-units = 1`, `opt-level = 3` (`zapzap-rust/Cargo.toml:78-81`).
- Toolchain pinned to `1.92` with rustfmt + clippy (`zapzap-rust/rust-toolchain.toml:4`); Dockerfile builder `rust:1.92-slim-bookworm` (`zapzap-rust/Dockerfile:6`).

### Module layout (`zapzap-rust/src/`)
| Layer | Contents |
|---|---|
| `api/` | `routes/{admin,auth,bots,game,health,history,party,players,stats}.rs`, `error.rs` (typed `ApiError` and the `ApiJson` body extractor, see Error mapping), `middleware/auth_middleware.rs`, `sse.rs`, `dto/` (empty mod, 1 line) |
| `application/` | use cases: `auth/{login_user,register_user}`, `party/{create,list,get_details,join,leave,start,delete}_party`, `party/add_bot_to_party`, `game/{get_game_state,select_hand_size,play_cards,draw_card,call_zapzap,next_round}`, `bot/reflect_on_round`. `admin/`, `history/`, `stats/` are **empty directories** — those routes run raw SQL in the handlers |
| `domain/` | `entities/` (User, Party, Round, Player), `value_objects/` (GameState 679 lines, PartySettings), `repositories/` (traits), `services/game_service.rs` |
| `infrastructure/` | `app_state.rs`, `auth/{jwt_service,password}`, `bot/{card_analyzer,llm_memory,strategies/*}`, `database/repositories/{user_repo,party_repo}`, `services/{llm_service,session_manager}` |
| `training/` | **empty directory**, untracked by git |

### Startup (`zapzap-rust/src/main.rs`)
- `dotenvy::dotenv()` loads `.env` (`:23`). Tracing filter from `RUST_LOG`, default `zapzap_backend=debug,tower_http=debug` (`:28-29`).
- Router: `/api` nested from `create_api_router` (`:40`), `/suscribeupdate` SSE (`:41`), `/health` (`:42-45`), `CorsLayer::permissive()` (`:46`), `TraceLayer` (`:47`). No timeout layer although `tower-http` `timeout` feature is enabled.
- Binds `0.0.0.0:$PORT`, default 9999 (`:51-56`).

### Configuration (environment variables)
| Var | Default | Where |
|---|---|---|
| `PORT` | `9999` | `zapzap-rust/src/main.rs:51-54` |
| `RUST_LOG` | `zapzap_backend=debug,tower_http=debug` | `zapzap-rust/src/main.rs:28-29` |
| `DATABASE_URL`, then `DB_PATH` | `sqlite:./data/zapzap.db` (a `sqlite:` prefix is added if missing) | `zapzap-rust/src/infrastructure/app_state.rs:47-56` |
| `JWT_SECRET` | `zapzap-secret-key-change-in-production` (hardcoded fallback, no warning logged) | `zapzap-rust/src/infrastructure/app_state.rs:67-68` |
| `AWS_BEDROCK_ENABLED` or `AWS_ACCESS_KEY_ID` (presence) | unset → no Bedrock; only with `bedrock` feature | `zapzap-rust/src/infrastructure/app_state.rs:89-90` |
| `AWS_BEDROCK_REGION` | `us-east-1` | `zapzap-rust/src/infrastructure/services/llm_service.rs:180` |
| `AWS_BEDROCK_MODEL_ID` | `meta.llama3-3-70b-instruct-v1:0` | `zapzap-rust/src/infrastructure/services/llm_service.rs:181-182` |
| `OLLAMA_BASE_URL` or `ENABLE_LLM_BOTS` (presence enables Ollama) | unset → no LLM | `zapzap-rust/src/infrastructure/app_state.rs:114-115` |
| `OLLAMA_BASE_URL` (value) | `http://localhost:11434` | `zapzap-rust/src/infrastructure/services/llm_service.rs:47-48` |
| `OLLAMA_MODEL` | `llama3.2` | `zapzap-rust/src/infrastructure/services/llm_service.rs:49` |
| `BOT_STRATEGIES_DIR` | `data/bot-strategies` (LLM bot memory JSON per bot id) | `zapzap-rust/src/infrastructure/bot/llm_memory.rs:155-156` |

- `zapzap-rust/docker-compose.yml` sets `PORT=9999`, `DATABASE_URL=sqlite:/app/data/zapzap.db`, `JWT_SECRET=${JWT_SECRET:-zapzap-secret-key-change-in-production}` (same default as the code), mounts `../data:/app/data`, healthcheck `curl -f http://localhost:9999/api/health`.
- Ollama config: timeout 60 s, temperature 0.3, max_tokens 512 (`llm_service.rs:50-52`); Bedrock: timeout 30 s (`llm_service.rs:183`).

### AppState (`zapzap-rust/src/infrastructure/app_state.rs`)
- Fields (`:17-42`): `db: SqlitePool`, `jwt_service`, `session_manager`, `user_repo`, `party_repo`, `event_sender`/`event_receiver` (async-broadcast), `llm_service: Option<Arc<dyn LlmService>>`, `llm_memories` (per-bot `LlmBotMemory` map).
- DB: `SqlitePool::connect(&db_url)` (`:61`) — no `create_if_missing`, so the file must already exist (it may be empty: the tables are created, see below).
- LLM priority Bedrock > Ollama > None; each is kept only if `health_check()` succeeds at startup (`:84-129`). With no LLM, LLM bots use a fallback strategy (see [[Bots]]).
- `get_llm_memory` lazily creates and `load()`s a bot's memory (`:148-165`).

### Database schema situation
- **The Rust backend creates its schema at startup**: `AppState::new()` calls `schema::ensure_schema(&db)` right after connecting (`zapzap-rust/src/infrastructure/app_state.rs:64`), which runs `zapzap-rust/src/infrastructure/database/schema.sql` through `sqlx::raw_sql` (`schema.rs`).
- `schema.sql` is the Node DDL verbatim: the `createSchema()` string of `src/infrastructure/database/sqlite/DatabaseConnection.js:69-240` (users, parties, party_players, rounds, game_state, round_scores, game_results, player_game_results, game_actions, 19 indexes) plus the two users indexes of its `runMigrations()` (`idx_users_google_id`, `idx_users_email`). Every statement is `IF NOT EXISTS`, so on a database the Node backend built it changes nothing.
- No sqlx migrations and no `_sqlx_migrations` table: the production DB has none, and `sqlx::migrate!` would start managing it. The Node `ALTER TABLE ... ADD COLUMN` steps and the password_hash table rebuild are not ported — they upgrade databases created by older Node versions, and every database the current Node code has opened (production's included) already went through them.
- `zapzap-rust/tests/schema_tests.rs` holds both halves: `rust_schema_matches_node_schema` builds a DB the way a fresh Node one is built — the `createSchema()` DDL, then `runMigrations()`'s `ALTER TABLE ... ADD COLUMN` statements (a duplicate column ignored, as Node does) and `CREATE INDEX` calls, all read from the `.js` file at compile time — and one from `schema.sql` and compares `sqlite_master` statement for statement; `schema_step_is_a_noop_on_a_node_built_database` fills a Node-built file DB (with the extra `idx_users_username`/`idx_users_user_type` of `scripts/docker-entrypoint.js`), runs `AppState::new()` and `ensure_schema` again, and checks that schema and rows are unchanged. A Node schema change without the same change in `schema.sql` turns it red.
- The older `src/infrastructure/database/schemas/schema.sql` (subset + `schema_version`) is loaded only by the legacy `src/infrastructure/database/sqlite/connection.js:78`, not by `DatabaseConnection.js`.
- Rust writes: parties/party_players/rounds/game_state/game_actions/round_scores/game_results/player_game_results in `zapzap-rust/src/infrastructure/database/repositories/party_repo.rs:253-730`; users upsert in `user_repo.rs:136` (includes `google_id`, `email` columns).

### Auth
- JWT HS256 (`Header::default()`), claims `userId`, `username`, `isAdmin` (default false), `exp`, `iat` (`zapzap-rust/src/infrastructure/auth/jwt_service.rs:7-15`). Lifetime `7 * 24 * 60 * 60` s = 7 days (`:28`). `decode_without_verify` exists, unused (`:60`).
- `auth_middleware` requires `Authorization: Bearer <token>`, else bare 401 with empty body (`zapzap-rust/src/api/middleware/auth_middleware.rs:16-42`). `optional_auth_middleware` attaches claims if valid (`:45-64`). `admin_middleware` (`:67-83`) is **never mounted**; admin handlers check `claims.is_admin` themselves, so admin rights come from the token (revocation takes effect only after the 7-day expiry).
- Passwords: new hashes Argon2 default params (`zapzap-rust/src/infrastructure/auth/password.rs:11`); `verify` dispatches on prefix `$argon2` vs `$2` (bcrypt, legacy Node hashes), anything else → `UnknownFormat` (`:38-50`). Login rehashes bcrypt to Argon2 after a successful login (`zapzap-rust/src/application/auth/login_user.rs:71-77`).

### Event broadcaster / SSE
- `broadcast(1000)` with `set_overflow(true)`: when full, oldest events are dropped instead of blocking (`app_state.rs:80-81`). `broadcast_event` uses `try_broadcast` and only logs errors (`:168-186`).
- `GameEvent` JSON: `type`, `partyId`, `userId`, optional `action`, flattened `data`, `timestamp` ms (`app_state.rs:190-204`). Event types emitted: `partyUpdate` (actions `partyCreated`, `playerJoined` — also when the owner adds a bot, with the bot as `userId` —, `playerLeft`, `partyStarted`, `partyDeleted`), `gameUpdate` (`selectHandSize`, `play`, `draw`, `zapzap`, `roundStarted`, `gameFinished`), `userConnected`, `userDisconnected`.
- `GET /suscribeupdate?token=<jwt>` (`zapzap-rust/src/api/sse.rs:18`): token optional, passed in the query string. Sends an initial `connected` event (`:52`), then each GameEvent as SSE event `event` (`:73`), a `heartbeat` comment every 20 s (`:58`), plus axum default keep-alive (`:95`). **Every client receives every party's events**; filtering is client-side.
- On a receiver error (e.g. lagging) the stream breaks and the client must reconnect (`sse.rs:76-80`).

### Session manager
- In-memory `RwLock<HashMap<user_id, UserSession>>` (`zapzap-rust/src/infrastructure/services/session_manager.rs:35-37`), lost on restart. `connect` on SSE open with status `lobby` (`:47-59`), `disconnect` on stream end (`:62`).
- `update_status` (`:68`) is never called, so every session stays `lobby` with `partyId: null`. One user with two tabs: the first tab closing removes the session.
- `GET /api/players/connected` returns at most 5 sessions, newest first (`zapzap-rust/src/api/routes/players.rs:39`).

### Bot triggering
- No bot scheduler: bots are driven by `trigger_bot_internal` (`zapzap-rust/src/api/routes/game.rs:1209`) spawned with `tokio::spawn` after `GET state` (100 ms delay, `:367-373`), `selectHandSize`, `play`, `draw`, `nextRound` (300 ms, `:434`, `:487`, `:542`, `:699`). It loops while the current player is a bot, sleeping 200 ms between actions (`:1564`).
- Iteration cap: 50 if an active human remains, 500 if only bots (`game.rs:1242`). Hand size for bots always chosen by `HardBotStrategy` (`game.rs:1322`).
- **No per-party lock**: every state poll spawns a new loop, so concurrent loops can act on the same bot turn (read-modify-write on `game_state`).
- Manual `POST /api/game/:partyId/trigger-bot` (`game.rs:742`) duplicates the loop inline with a cap of 50 (`:752`).
- After a human ZapZap, `trigger_llm_reflection` (`game.rs:1571`) runs `ReflectOnRound` for each LLM bot if an LLM service exists; `score_change` is hard-coded 0 (`game.rs:1632`).
- Pending bot turns are not recovered at startup (the Node `BotOrchestrator.recoverPendingBotTurns`, `src/infrastructure/bot/BotOrchestrator.js:59`, has no Rust equivalent); the next `GET state` restarts them.

### Error mapping
- The party and game handlers return `Result<_, ApiError>` (`zapzap-rust/src/api/error.rs`): one `From<UseCaseError> for ApiError` per use case maps each variant to Node's status and `code`; no handler reads an error's message. A repository failure is a 500 in Node's shape (`{error: "Failed to …", code: "<ROUTE>_ERROR", details}`), logged by `IntoResponse`.
- JSON bodies go through `ApiJson<T>`: a body that does not parse (malformed JSON, a missing or mistyped field) answers 400 `{error, code, details}` with the code the route gives a missing field (`ApiBody::INVALID_CODE`), never axum's 422 plain text; a request without a JSON content type reads as `{}`, as Express does.
- The auth, admin, bots, stats and history handlers still build their errors inline (no message matching there).

## Decisions & History
- 2026-09-24 (fix/rust-api-errors-contract): the substring matching of error messages was replaced by typed errors, after six of its branches were found answering 500 for client errors ([[Api]] keeps the list of cases where Rust answers a 4xx and Node a 500). The play and draw use cases gained typed variants (`CardNotInHand`, `DeckEmpty`, `NoCardsAvailable`, `CardNotAvailable`) checked before the domain call, so that no error code depends on the domain's message strings.
- Backend rewritten from Node/Express to Rust in `e4f83da` (2025-12-23), keeping the Node JSON shapes ("matching JS behavior" comments, `zapzap-rust/src/api/routes/auth.rs:83`) and the SQLite file, which explains the bcrypt fallback and the absence of Rust-side schema creation.
- 2026-09-23 (fix/rust-api-schema): the backend got its own schema step so that `tests/api_tests.rs` could run on an in-memory DB and join CI. The Node DDL was copied rather than written as sqlx migrations, because a migration runner on the production file (no `_sqlx_migrations` table) would either refuse it or re-run `CREATE TABLE` on it; `IF NOT EXISTS` DDL is a no-op there. The same change made `POST /api/party` without `name` answer 400 `MISSING_PARTY_NAME` like Node (it answered axum's 422), which `test_create_party_missing_name` had caught.
- `8a3509b` added the background bot triggers and the 50/500 iteration limit; `c9ac7a7` enabled broadcaster overflow after SSE sends blocked on a full channel (commit title).
- `1e063d6` (2026-09-22, PR #21) added CI, committed `Cargo.lock` (was gitignored though the Dockerfile copies it), stopped tracking `data/zapzap.db`, ran `cargo fmt`, fixed clippy findings and pinned Rust 1.92 because newer clippy added lints and `rust:1.83` could not parse `base64ct` 1.8.1.
