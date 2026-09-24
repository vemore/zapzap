# Architecture

> Scope: the five code bases of the repository (zapzap-rust, frontend, frontend-flutter, native, legacy src/), how they talk to each other, the shared `data/` directory, SQLite location, SSE, docker-compose files.
> Related: [[Deployment]] · [[Backend]] · [[Api]] · [[Frontend]] · [[FrontendFlutter]] · [[NativeEngine]] · [[Bots]] · [[Testing]] · [[GameRules]]
> Updated: 2026-09-24

## Facts

### The five parts

| Part | Path | Stack | Role | Status |
|------|------|-------|------|--------|
| Rust backend | `zapzap-rust/` | axum 0.7, tokio, sqlx 0.8 (sqlite), jsonwebtoken 9, argon2 + bcrypt (`zapzap-rust/Cargo.toml:10-25`) | HTTP API + SSE on port 9999, bots, persistence | **Target** backend, **not deployed yet** (production runs the Node one, [[Deployment]]). Binary `zapzap-backend` (`zapzap-rust/Cargo.toml:2`) |
| Frontend | `frontend/` | React 19 + react-router-dom 7 + Vite + Tailwind, `@react-oauth/google` (`frontend/package.json:16-42`) | SPA, served by nginx in its container | Current |
| Flutter client | `frontend-flutter/` | Flutter 3.47.2 / Dart 3.13, Provider, go_router, `http`, gen-l10n (`frontend-flutter/pubspec.yaml`) | Android app and PWA; the PWA is served under `/app/` on the production domain, from its own image (`frontend-flutter/Dockerfile`) | **Playable**: the session, the party list, create-party, the lobby, the game board and the end of a round and of a game, the history and the statistics, the admin shell with its users tab; no Google sign-in, no admin parties or statistics yet. [[FrontendFlutter]], [[Deployment]] |
| Native engine | `native/` | Rust `cdylib` via napi 2 (`native/Cargo.toml:8`, `native/Cargo.toml:12-13`), npm name `zapzap-native` (`native/package.json:2`) | Headless game simulation, DRL training, genetic optimisation; loaded by Node scripts in `scripts/` | Offline tooling only |
| Legacy backend | `src/`, `app.js` | Node/Express, clean architecture (`src/domain`, `src/use-cases`, `src/infrastructure`, `src/api`) | Former API server (entry `app.js:14-20`, `src/api/server.js`) | **Legacy, yet the one in production** (checked 2026-09-22, [[Deployment]]); no CI job, no gate. Owns the upgrades of old schemas (`runMigrations()`) |

- Old `CLAUDE.md` describes the frontend as "Vanilla JS"; it is React (`frontend/src/main.jsx`, `frontend/src/App.jsx`).
- Both Rust crates pin toolchain 1.92 (`zapzap-rust/rust-toolchain.toml:4`, `native/rust-toolchain.toml:3`); the backend image uses `rust:1.92-slim-bookworm` (`zapzap-rust/Dockerfile:6`).
- `native/` is **not** linked into the Rust backend: the backend reimplements game logic and bot strategies itself (`zapzap-rust/src/domain/`, `zapzap-rust/src/infrastructure/bot/`). The legacy Node backend does load the native module optionally (`src/infrastructure/bot/strategies/ThibotBotStrategy.js:20-21`).

### Runtime topology

```
browser ──> zapzap-proxy (nginx:alpine, :80)
              ├─ /api/*          -> backend:9999          (nginx/nginx.conf:28-46)
              ├─ /suscribeupdate -> backend:9999          (SSE, unbuffered, 86400s timeouts, nginx/nginx.conf:49-86)
              ├─ /app/*          -> frontend-flutter:80   (Flutter PWA, base href /app/, nginx/nginx.conf:91-113)
              └─ /               -> frontend:80           (nginx serving the Vite build)
```

- Backend router: `/api` nested router, `/suscribeupdate` SSE, `/health`; `CorsLayer::permissive()` (`build_app`, `zapzap-rust/src/api/mod.rs:21-35`, served by `main.rs`). Binds `0.0.0.0:$PORT`, default 9999 (`zapzap-rust/src/main.rs:45-50`). Route list: [[Api]].
- Dev mode: Vite proxies `/api` and `/suscribeupdate` to `http://localhost:9999` (`frontend/vite.config.js:7-17`).

### Real-time updates (SSE)

- Endpoint `GET /suscribeupdate` (spelling is historical and must be kept, frontend and nginx use it) — `zapzap-rust/src/api/mod.rs:24`, handler `zapzap-rust/src/api/sse.rs:18`.
- Optional `?token=<JWT>`: when valid the user is registered in the session manager and a `userConnected` event is broadcast (`zapzap-rust/src/api/sse.rs:23-39`); `userDisconnected` on stream end (`zapzap-rust/src/api/sse.rs:86-92`).
- Stream sends an initial `connected` event, a `heartbeat` comment every 20 s, and each broadcast as SSE event name `event` with JSON payload, with `X-Accel-Buffering: no` (`zapzap-rust/src/api/sse.rs`). A game's moves and every event of a private party reach only its players' streams; events without a party and a public party's lifecycle events (joined, left, started, deleted, finished) reach every stream ([[Backend]]).
- Broadcaster: `async-broadcast` channel of capacity 1000 with overflow enabled (drop oldest instead of blocking) (`zapzap-rust/src/infrastructure/app_state.rs:112-115`).
- Frontend: `useSSE` hook (`frontend/src/hooks/useSSE.js:37`); `PartyLobby` and `GameBoard` connect **without** token (`frontend/src/components/Party/PartyLobby.jsx:43`, `frontend/src/components/Game/GameBoard.jsx:147`), only `ConnectedPlayers` passes it (`frontend/src/components/Party/ConnectedPlayers.jsx:80`). Against the Rust backend those two tokenless streams miss a game's moves and every private-party event, since it filters per user; the switch needs them to pass the token (tracked in `wip/`). Details: [[Backend]], [[Frontend]].
- Flutter client: one connection per signed-in session, with the token (`frontend-flutter/lib/services/sse_client.dart`), reconnecting 3 s after a drop. [[FrontendFlutter]].
- The PWA is same-origin with the API (`/app/` on the production domain), so its SSE stream and API calls need no CORS grant. [[Deployment]].

### SQLite database

- Rust backend URL: `DATABASE_URL`, else `DB_PATH`, else `sqlite:./data/zapzap.db`; `sqlite:` prefix added if missing (`zapzap-rust/src/infrastructure/app_state.rs:82-92`). Docker sets `DATABASE_URL=sqlite:/app/data/zapzap.db` (`zapzap-rust/Dockerfile:62`, `zapzap-rust/docker-compose.yml:11`).
- Node backend file: `DB_PATH`, else `data/zapzap.db` of the checkout (`src/api/bootstrap.js:87`, `src/infrastructure/database/sqlite/DatabaseConnection.js:13`); `scripts/init-bots.js` reads `DB_PATH` too. The root image sets `DB_PATH=/app/data/zapzap.db` (`Dockerfile:27`), the path the default already resolved to. A local server on a throwaway database: `DB_PATH=/tmp/x.db PORT=9941 node app.js`.
- **Both backends create the same schema**: the Node code in `src/infrastructure/database/sqlite/DatabaseConnection.js:69-240` (users, parties, party_players, rounds, game_state, round_scores, game_results, player_game_results, game_actions) plus its `runMigrations()`, the Rust backend at startup from a verbatim copy, `zapzap-rust/src/infrastructure/database/schema.sql` (`zapzap-rust/src/infrastructure/app_state.rs:64`). All `IF NOT EXISTS`, so the Rust step is a no-op on a Node-built DB; `zapzap-rust/tests/schema_tests.rs` keeps the two identical ([[Backend]]). Older Node databases are upgraded by the Node side only (`runMigrations()`, `scripts/docker-entrypoint.js`).
- `data/zapzap.db` is git-ignored (`.gitignore`, "Database" section) since commit 1e063d6.

### `data/` directory

`zapzap-rust/data` is a symlink to `../data`, so both backends and the scripts share one directory.

| Content | Producer | Consumer |
|---------|----------|----------|
| `zapzap.db` | schema bootstrap by either backend (same DDL), Rust backend at runtime | Rust backend |
| `hard_vince_genetic_params.json`, `hard_vince_optimized_params.json`, `thibot_genetic_params.json` | `scripts/genetic-optimize-hard-vince.js`, `scripts/optimize-hard-vince.js`, `scripts/genetic-optimize-thibot.js` | the same scripts / legacy JS strategies; the Rust backend does not read them (no reference in `zapzap-rust/src`), see [[Bots]] |
| `ml_model_*.json` (16 files, up to ~41 MB) | legacy JS ML training | `src/infrastructure/bot/ml/ModelStorage.js:14` (default dir `./data`) |
| `models/rust-drl.safetensors`, `models/rust-drl-hard.safetensors`, `models/default/{config,weights}.json` | `scripts/train-native.js` (default save path `data/models/rust-drl`, `scripts/train-native.js:56`) via `native/src/training/model_io.rs` | native engine / DRL bot, see [[NativeEngine]] |
| `bot-strategies/<botUserId>.json` (untracked) | LLM bot memory | Rust backend, dir overridable by `BOT_STRATEGIES_DIR` (`zapzap-rust/src/infrastructure/bot/llm_memory.rs:153-157`) |

### Docker / compose

| File | Era | Services |
|------|-----|----------|
| `docker-compose.yml` (root) | Node | `backend` built from root `Dockerfile` (node:20-alpine, `CMD node scripts/docker-entrypoint.js`, `Dockerfile:1-37`), container `zapzap-backend`; `frontend`; `frontend-flutter` from `./frontend-flutter` (container `zapzap-frontend-flutter`); `nginx` = `zapzap-proxy`. Passes `GOOGLE_OAUTH_CLIENT_ID`, `BOT_ACTION_DELAY_MS`, `AWS_BEDROCK_*` (`docker-compose.yml:9-23`) |
| `zapzap-rust/docker-compose.yml` | Rust | `backend` from `zapzap-rust/Dockerfile` (multi-stage, debian bookworm-slim runtime, non-root uid 1000, curl healthcheck on `/api/health`), container **`zapzap-rust-backend`**, publishes 9999; `frontend` from `../frontend`; `frontend-flutter` from `../frontend-flutter`; `nginx` from `../nginx/nginx.conf`. Env `PORT`, `DATABASE_URL`, `JWT_SECRET` (required, no default: `${JWT_SECRET:?...}`), `RUST_LOG`, `BOT_STRATEGIES_DIR=/app/data/bot-strategies`, and the LLM variables `AWS_BEDROCK_ENABLED`, `AWS_BEDROCK_REGION`, `AWS_BEDROCK_MODEL_ID`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `OLLAMA_BASE_URL`, `OLLAMA_MODEL`, `ENABLE_LLM_BOTS`, each passed only when set on the host; build arg `CARGO_FEATURES` (`zapzap-rust/docker-compose.yml`) |

- Both compose files mount the shared `data/` (`./data` resp. `../data`) at `/app/data`.
- In both, `nginx` waits for `backend` and `frontend` to be healthy but **not** for `frontend-flutter`: `/app/` is resolved per request through Docker's DNS, so a broken PWA is a 502 on `/app/` and never an outage of `/` and `/api/`. [[Deployment]].
- The Rust image is built without the `bedrock` feature unless the build arg `CARGO_FEATURES=bedrock` asks for it (`zapzap-rust/Dockerfile`; the Rust compose passes the host's `CARGO_FEATURES`, empty by default). Which LLM variable turns which service on: [[Bots]] "LLM bot".
- Production's `zapzap-backend` container runs `node scripts/docker-entrypoint.js` from the root compose (checked on the NAS 2026-09-22); the Rust compose would name it `zapzap-rust-backend`. [[Deployment]].

### Legacy backend (brief)

- Express app, DI container in `src/infrastructure/di`, routes in `src/api/routes/*Routes.js`, SSE also at `/suscribeupdate` with `?token=` (`src/api/server.js:69-109`).
- Still the only place that upgrades an old SQLite schema (`runMigrations()`), and the home of the JS bot strategies and the JS simulation runners (`src/simulation/`). `POST /api/auth/google` is served by both backends since 2026-09-24 ([[Api]]).
- Tests: jest + playwright (see [[Testing]]).

## Decisions & History

- 2025-11-06 `2eb575d`: the Node backend was reworked to clean architecture with the React frontend; this is the code now called legacy.
- 2025-12-15 `9a1d37f`: `native/` first appears (with the hard bot strategy); later DRL/genetic commits grow it into the training engine that complements the JS `src/simulation/` runners.
- 2025-12-23 `e4f83da` "rewrite backend in Rust": `zapzap-rust/` mirrors the Node layers (api / application / domain / infrastructure) and reads the DB the Node code had created, which is why no migrations were written (the `migrate!` line was left commented). Same day: background bot triggering (`8a3509b`) and broadcaster overflow mode (`c9ac7a7`, avoids blocking senders when SSE clients lag).
- 2026-09-22 `1e063d6`: CI added, `Cargo.lock` committed, `data/zapzap.db` untracked, Rust pinned to 1.92.
- 2026-09-23 `fix/rust-api-schema`: the Rust backend creates the Node schema itself (`IF NOT EXISTS`, no sqlx migrations), so it no longer needs a DB the Node side initialised. [[Backend]].
- 2026-09-23 `feat/flutter-pwa-deploy`: the PWA gets its own image and compose service, and the proxy a `/app/` route — one more container in the topology above. [[Deployment]].
- 2026-09-22 `feat/flutter-scaffold`: `frontend-flutter/` created — a Flutter client (Android + PWA) to reach parity with the React one; React stays on `/`, the PWA goes under `/app/` so the API is same-origin. [[FrontendFlutter]].
