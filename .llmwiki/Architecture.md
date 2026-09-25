# Architecture

> Scope: the four code bases of the repository (zapzap-rust, frontend, frontend-flutter, native), how they talk to each other, the shared `data/` directory, SQLite location, SSE, docker-compose files.
> Related: [[Deployment]] · [[Backend]] · [[Api]] · [[Frontend]] · [[FrontendFlutter]] · [[NativeEngine]] · [[Bots]] · [[Testing]] · [[GameRules]]
> Updated: 2026-09-25

## Facts

### The four parts

| Part | Path | Stack | Role | Status |
|------|------|-------|------|--------|
| Rust backend | `zapzap-rust/` | axum 0.7, tokio, sqlx 0.8 (sqlite), jsonwebtoken 9, argon2 + bcrypt (`zapzap-rust/Cargo.toml:10-25`) | HTTP API + SSE on port 9999, bots, persistence | **Production** backend since 2026-09-24 (the root compose's `backend` service, [[Deployment]]); the only backend since 2026-09-25. Binary `zapzap-backend` (`zapzap-rust/Cargo.toml:2`) |
| Frontend | `frontend/` | React 19 + react-router-dom 7 + Vite + Tailwind, `@react-oauth/google` (`frontend/package.json:16-42`) | SPA, served by nginx in its container | Current |
| Flutter client | `frontend-flutter/` | Flutter 3.47.2 / Dart 3.13, Provider, go_router, `http`, gen-l10n (`frontend-flutter/pubspec.yaml`) | Android app and PWA; the PWA is served under `/app/` on the production domain, from its own image (`frontend-flutter/Dockerfile`) | **Playable**: the session, the party list, create-party, the lobby, the game board and the end of a round and of a game, the history and the statistics, the admin shell with its users tab; no Google sign-in, no admin parties or statistics yet. [[FrontendFlutter]], [[Deployment]] |
| Native engine | `native/` | Rust `cdylib` via napi 2 (`native/Cargo.toml:8`, `native/Cargo.toml:12-13`), npm name `zapzap-native` (`native/package.json:2`) | Headless game simulation, DRL training, genetic optimisation; driven by the Node scripts `scripts/train-native.js` and `scripts/genetic-optimize-thibot.js` | Offline tooling only |

- The frontend is React (`frontend/src/main.jsx`, `frontend/src/App.jsx`), not the "Vanilla JS" an old `CLAUDE.md` described.
- Both Rust crates pin toolchain 1.92 (`zapzap-rust/rust-toolchain.toml:4`, `native/rust-toolchain.toml:3`); the backend image uses `rust:1.92-slim-bookworm` (`zapzap-rust/Dockerfile:6`).
- `native/` is **not** linked into the Rust backend: the backend implements game logic and bot strategies itself (`zapzap-rust/src/domain/`, `zapzap-rust/src/infrastructure/bot/`).
- The root `package.json` holds only `playwright`, the headless browser fallback of [[ParallelDelivery]]; no code base runs from it.

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
- Optional `?token=<JWT>`: when valid the stream is registered in the session manager, and the user's first stream broadcasts `userConnected`; when the client goes away the stream's guard unregisters it, and the user's last stream broadcasts `userDisconnected` (`StreamGuard`, `zapzap-rust/src/api/sse.rs`; streams counted per user).
- Stream sends an initial `connected` event, a `heartbeat` comment every 20 s, and each broadcast as SSE event name `event` with JSON payload, with `X-Accel-Buffering: no` (`zapzap-rust/src/api/sse.rs`). A game's moves and every event of a private party reach only its players' streams; events without a party and a public party's lifecycle events (joined, left, started, deleted, finished) reach every stream ([[Backend]]).
- Broadcaster: `async-broadcast` channel of capacity 1000 with overflow enabled (drop oldest instead of blocking) (`zapzap-rust/src/infrastructure/app_state.rs:112-115`).
- Frontend: `useSSE` hook (`frontend/src/hooks/useSSE.js`); `PartyLobby` and `GameBoard` open the stream at `sseUrl()` (`frontend/src/services/sse.js`), which carries the user's token since #94 — without it the backend, which filters per user, would send them none of a game's moves nor any private-party event. Details: [[Backend]], [[Frontend]].
- Flutter client: one connection per signed-in session, with the token (`frontend-flutter/lib/services/sse_client.dart`), reconnecting 3 s after a drop. [[FrontendFlutter]].
- The PWA is same-origin with the API (`/app/` on the production domain), so its SSE stream and API calls need no CORS grant. [[Deployment]].

### SQLite database

- URL: `DATABASE_URL`, else `DB_PATH`, else `sqlite:./data/zapzap.db`; `sqlite:` prefix added if missing (`database_url`, `zapzap-rust/src/infrastructure/app_state.rs:246`). Docker sets `DATABASE_URL=sqlite:/app/data/zapzap.db` (`zapzap-rust/Dockerfile:62`, `docker-compose.yml`, `zapzap-rust/docker-compose.yml:11`). The server and `zapzap-backend seed` open the same file.
- The schema: created at startup from `zapzap-rust/src/infrastructure/database/schema.sql` (`ensure_schema`, `zapzap-rust/src/infrastructure/app_state.rs:97`), all `IF NOT EXISTS`, so it is a no-op on an existing database — production's was built by the Node backend. `zapzap-rust/tests/schema_tests.rs` checks it against a frozen Node-built schema, `zapzap-rust/tests/fixtures/node_built_schema.sql` ([[Backend]]). A database older than the Node backend's last migrations is not upgraded by anything any more; the schema step fails on it as a whole, leaving it unchanged (`zapzap-rust/tests/schema_tests.rs`).
- `data/zapzap.db` is git-ignored (`.gitignore`, "Database" section) since commit 1e063d6.

### `data/` directory

`zapzap-rust/data` is a symlink to `../data`, so the backend and the scripts share one directory.

| Content | Producer | Consumer |
|---------|----------|----------|
| `zapzap.db` | the backend's schema step, then the backend at runtime | the backend |
| `hard_vince_genetic_params.json`, `thibot_genetic_params.json` | the genetic optimisers (`scripts/genetic-optimize-thibot.js` for Thibot) | nothing yet: the Rust backend does not read them (no reference in `zapzap-rust/src`), see [[Bots]] |
| `models/rust-drl.safetensors`, `models/rust-drl-hard.safetensors` | `scripts/train-native.js` (default save path `data/models/rust-drl`, `scripts/train-native.js:56`) via `native/src/training/model_io.rs` | native engine / DRL bot, see [[NativeEngine]] |
| `bot-strategies/<botUserId>.json` (gitignored) | LLM bot memory | Rust backend, dir overridable by `BOT_STRATEGIES_DIR` (`zapzap-rust/src/infrastructure/bot/llm_memory.rs:157`) |

### Docker / compose

| File | Services |
|------|----------|
| `docker-compose.yml` (root, local and CI; production runs `docker-compose.prod.yml`) | `backend` built from `zapzap-rust/Dockerfile` with the build arg `CARGO_FEATURES=bedrock`, container `zapzap-backend`, no published port; `frontend`; `frontend-flutter` from `./frontend-flutter` (container `zapzap-frontend-flutter`); `nginx` = `zapzap-proxy`. Env `PORT`, `DATABASE_URL`, `JWT_SECRET` (required), `RUST_LOG`, `GOOGLE_OAUTH_CLIENT_ID`, `BOT_ACTION_DELAY_MS`, `BOT_STRATEGIES_DIR`, the `AWS_*` LLM variables passed only when set ([[Deployment]] has the table) |
| `zapzap-rust/docker-compose.yml` | `backend` from `zapzap-rust/Dockerfile` (multi-stage, debian bookworm-slim runtime, non-root uid 1000, curl healthcheck on `/api/health`), container **`zapzap-rust-backend`**, publishes 9999; `frontend` from `../frontend`; `frontend-flutter` from `../frontend-flutter`; `nginx` from `../nginx/nginx.conf`. Env `PORT`, `DATABASE_URL`, `JWT_SECRET` (required, no default: `${JWT_SECRET:?...}`), `RUST_LOG`, `BOT_STRATEGIES_DIR=/app/data/bot-strategies`, `BOT_ACTION_DELAY_MS` (default 1000), and the LLM variables `AWS_BEDROCK_ENABLED`, `AWS_BEDROCK_REGION`, `AWS_BEDROCK_MODEL_ID`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `OLLAMA_BASE_URL`, `OLLAMA_MODEL`, `ENABLE_LLM_BOTS`, each passed only when set on the host; build arg `CARGO_FEATURES` (`zapzap-rust/docker-compose.yml`) |

- Both compose files mount the shared `data/` (`./data` resp. `../data`) at `/app/data`.
- In both, `nginx` waits for `backend` and `frontend` to be healthy but **not** for `frontend-flutter`: `/app/` is resolved per request through Docker's DNS, so a broken PWA is a 502 on `/app/` and never an outage of `/` and `/api/`. [[Deployment]].
- The Rust image is built without the `bedrock` feature unless the build arg `CARGO_FEATURES=bedrock` asks for it (`zapzap-rust/Dockerfile`; the root compose sets it, the Rust compose passes the host's `CARGO_FEATURES`, empty by default). Which LLM variable turns which service on: [[Bots]] "LLM bot".
- Production runs `docker-compose.prod.yml`: the root compose's four services and environment, as registry images `192.168.1.25:5050/zapzap-*:<short sha>` built and pushed by `scripts/deploy_nas.sh` — the proxy as an image of its own, `zapzap-proxy` (`nginx/Dockerfile`, the conf baked in) —, no `build:`, `data/` of the NAS deploy directory. The Rust compose names its own container `zapzap-rust-backend`. [[Deployment]].

## Decisions & History

- 2025-11-06 `2eb575d`: the Node backend was reworked to clean architecture with the React frontend; this is the code now called legacy.
- 2025-12-15 `9a1d37f`: `native/` first appears (with the hard bot strategy); later DRL/genetic commits grow it into the training engine that complements the JS `src/simulation/` runners.
- 2025-12-23 `e4f83da` "rewrite backend in Rust": `zapzap-rust/` mirrors the Node layers (api / application / domain / infrastructure) and reads the DB the Node code had created, which is why no migrations were written (the `migrate!` line was left commented). Same day: background bot triggering (`8a3509b`) and broadcaster overflow mode (`c9ac7a7`, avoids blocking senders when SSE clients lag).
- 2026-09-22 `1e063d6`: CI added, `Cargo.lock` committed, `data/zapzap.db` untracked, Rust pinned to 1.92.
- 2026-09-23 `fix/rust-api-schema`: the Rust backend creates the Node schema itself (`IF NOT EXISTS`, no sqlx migrations), so it no longer needs a DB the Node side initialised. [[Backend]].
- 2026-09-23 `feat/flutter-pwa-deploy`: the PWA gets its own image and compose service, and the proxy a `/app/` route — one more container in the topology above. [[Deployment]].
- 2026-09-22 `feat/flutter-scaffold`: `frontend-flutter/` created — a Flutter client (Android + PWA) to reach parity with the React one; React stays on `/`, the PWA goes under `/app/` so the API is same-origin. [[FrontendFlutter]].
- 2026-09-24 `chore/switch-prod-to-rust`: production switches to the Rust backend — the root compose's `backend` service builds `zapzap-rust/` (Bedrock feature) under the same names; the Node backend stays as the rollback. [[Deployment]].
- **The Node backend is removed (2026-09-25, chore/remove-node-backend).** Five code bases become four: `src/`, `app.js`, the root `Dockerfile`, its JS bots and ML models (`data/ml_model_*.json`, `data/models/default/`, `data/hard_vince_optimized_params.json`) and the scripts that upgraded old schemas are gone. Its code can still be read at `232f168` (the last master commit holding `src/`, e.g. `git show 232f168:src/infrastructure/database/sqlite/DatabaseConnection.js`) and `0bfd407` (the last commit whose `docker-compose.yml` builds it, the former rollback target).
- 2026-09-25 `feat/deploy-through-registry`: production leaves the root compose for `docker-compose.prod.yml` (registry images, no build on the NAS); the proxy gets its own image. [[Deployment]].
