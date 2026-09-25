# Testing

> Scope: every test suite in the repo, how to run it, its current state, and what CI (`.github/workflows/ci.yml`) runs, skips and why — including the `scope` job.
> Related: [[Backend]] · [[NativeEngine]] · [[Frontend]] · [[Architecture]]
> Updated: 2026-09-25

## Facts

### Suites at a glance
| Suite | Run | State 2026-09-22 | In CI |
|---|---|---|---|
| Rust backend unit tests (`#[cfg(test)]` in `zapzap-rust/src`) | `cd zapzap-rust && cargo test --lib --bins` | green | yes |
| Rust backend API tests (`zapzap-rust/tests/api_tests.rs`, 98 tests on 2026-09-25) | `cargo test --test api_tests` | green | yes |
| Rust backend schema tests (`zapzap-rust/tests/schema_tests.rs`, 3 tests on 2026-09-25) | `cargo test --test schema_tests` | green | yes |
| Rust backend rules and bots tests (`zapzap-rust/tests/rules_and_bots_tests.rs`, 10 tests on 2026-09-25: eliminated starter, starter wrap, tied lowest hands, repeated card, hand size with 8 players, concurrent bot triggers, a trigger during a manual loop, one strategy per bot) | `cargo test --test rules_and_bots_tests` | green | yes |
| Native engine (`native/src`, 98 `#[test]`) | `cd native && cargo test` | green (2026-09-23) | yes, nothing skipped |
| Native clippy | `cargo clippy --all-targets -- -D warnings` | clean (2026-09-23) | yes |
| Frontend vitest (`frontend/src/**/__tests__`) | `cd frontend && npx vitest run` | green since 2026-09-23 (294 tests, 21 files) | yes |
| Frontend lint | `npm run lint` | green since 2026-09-23 (0 errors, 9 `react-hooks/exhaustive-deps` warnings) | yes, and in the commit hook |
| Frontend build | `npm run build` | green | yes |
| Flutter client (`frontend-flutter/test`) | `cd frontend-flutter && dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test` | green | yes, with `build web` and `build apk --debug`; the format check and the analyzer also in the commit hook |
| Flutter end to end (`frontend-flutter/integration_test/`) | `scripts/flutter_e2e.sh` (the Rust backend on a fresh database, then `flutter drive`), or by hand against either backend, below | green (2026-09-24) | yes (`flutter-e2e` job) |
| Node backend jest (`tests/unit`, `tests/integration`) | `npm test` (root) | green, 23 suites, 329 tests (2026-09-25) | yes (`node` job) |
| Backend parity, Node vs Rust (`tests/parity`, `node --test`, outside jest) | `cd zapzap-rust && cargo build --release`, then `npm run test:parity` (root), about 30 s | green with the differences `tests/parity/divergences.json` lists, all `node-bug` (2026-09-24) | yes (`parity` job) |
| Legacy Playwright e2e (`tests/e2e`) | `npm run test:e2e` | not tracked | no |
| Docker images and the proxy config | `docker build zapzap-rust`, `docker build .` (the Node backend production runs), `docker build frontend`, `docker build frontend-flutter` + `scripts/pwa_image_smoke.sh`, `nginx -t` on `nginx/nginx.conf` | green | yes |

### Rust backend (`zapzap-rust/`)
- Toolchain pinned to `1.92` with rustfmt + clippy — `zapzap-rust/rust-toolchain.toml:3-4`. The same version is used by CI (`dtolnay/rust-toolchain@1.92`, `rust` job) and the image's builder tag.
- Unit tests live next to the code (93 on 2026-09-25, 1 of them ignored). Count them in `zapzap-rust/` rather than trust a number here: `cargo test --lib -- --list | grep -c ': test$'` for the total, `grep -rc '#\[\(tokio::\)\?test\]' src | grep -v ':0$'` per file. The files: `application/auth/login_with_google.rs`, `application/bot/{create_bot,delete_bot,reflect_on_round,runner}.rs`, `application/game/next_round.rs`, `domain/entities/player.rs`, `domain/services/game_service.rs`, `domain/value_objects/{game_state,party_settings}.rs`, `infrastructure/app_state.rs` (the JWT secret), `infrastructure/auth/password.rs` (bcrypt at Node's cost, the Node-compat fixture; the ignored `print_fixture_hash` rewrites it), `infrastructure/bot/{card_analyzer,llm_memory}.rs`, `infrastructure/bot/strategies/{llm_bot,thibot,vince_bot}.rs`, `infrastructure/services/google_oauth.rs` (the key cache with an injected fetcher), `infrastructure/services/llm_service.rs` (the bounded startup probe, the cheap Bedrock health check), `infrastructure/services/session_manager.rs`. The Google and bot-admin races run on `RacingUserRepo` (`infrastructure/database/repositories/racing_user_repo.rs`, test-only), whose lookups can be made stale; tokens are signed with the test-only key `zapzap-rust/tests/fixtures/google_oauth_test_rsa.pem`, never checked against Google.
- Integration tests: `create_test_app_with_state` (`zapzap-rust/tests/api_tests.rs`) builds the application `main.rs` serves (`api::build_app`) with `DATABASE_URL=sqlite::memory:`, `JWT_SECRET=test-secret-key` and `BOT_ACTION_DELAY_MS=200` (bots pause 200 ms, not production's seconds) (`create_test_app_with_state` also hands back the `AppState`, to set a game state or read SSE events), then drives it with tower `oneshot`: auth and party basics, then the error contract — tests per party and game route family asserting Node's status and `code` (`assert_error`, `api_tests.rs:539`), unreadable bodies answering 400, `partyCreated`, `isMyTurn`, adding a bot and the zapzap scores, on a started three-human party (`started_party`, `api_tests.rs:462`). Each test gets a fresh in-memory DB, whose tables `AppState::new()` creates (its `ensure_schema` call, `zapzap-rust/src/infrastructure/app_state.rs`). The security tests at the end (the router of `create_test_app_with_state` also serves `/suscribeupdate`): private join/details, game state, `nextRound`, `trigger-bot`, private history, admin 401/403, SSE per-user filtering and public-party lifecycle events (read the streamed body until a sentinel event), `/history/public` without private games, a deleted user's token refused, and `test_server_refuses_to_start_without_jwt_secret`, which runs the `zapzap-backend` binary (`CARGO_BIN_EXE_zapzap-backend`) in an empty directory without `JWT_SECRET`. Last, module `google_and_bot_admin`: `POST /api/auth/google` (missing credential, forged token, not configured, a full login with an injected key set) and the admin bot routes. Then Node's bodies for the three auth 401 codes, the `ROUTE_NOT_FOUND` 404 of an unknown path and of an unserved method (`test_unserved_method_answers_route_not_found`), the unknown `/api/admin` paths behind the auth and admin checks, and both health checks. Last, the `/state` and `nextRound` contracts: `test_state_sends_nodes_always_present_keys`, `test_state_last_action_of_select_play_and_draw` (a deck draw names no card), `test_state_last_action_of_a_reshuffling_draw`, `test_state_last_action_of_a_zapzap`, `test_next_round_answers_nodes_keys` and `test_next_round_at_the_end_of_the_game_answers_nodes_keys`, `test_next_round_after_the_game_ending_zapzap_is_refused` (see [[Api]]). Then the last parity items: `test_admin_set_admin_bad_body_answers_nodes_400`, `test_join_full_started_party_answers_party_full`, `test_delete_party_by_a_non_member_answers_not_in_party`.
- Schema tests: `zapzap-rust/tests/schema_tests.rs` reads the Node DDL from `src/infrastructure/database/sqlite/DatabaseConnection.js` at compile time (`include_str!`) and checks that `schema.sql` creates the same objects (`rust_schema_matches_node_schema`) and that the startup step leaves a filled Node-built DB unchanged (`schema_step_is_a_noop_on_a_node_built_database`), and that a failing step (an entrypoint-rebuilt `users` table without `google_id`) leaves the DB unchanged (`schema_step_failure_leaves_the_database_unchanged`). See [[Backend]].
- CI gate (`rust` job): `cargo fmt --check`, `cargo clippy --locked --all-targets -- -D warnings`, `cargo test --locked --lib --bins --tests` (unit and integration tests).
- `scripts/ci_scope.sh` sends a change to `src/` to `node` and `image`, and a change to `src/infrastructure/database/sqlite/DatabaseConnection.js` (the Node DDL `schema_tests` reads) to `rust` as well, so a PR that edits only the Node schema still runs the parity test.

### Native engine (`native/`)
- Toolchain pinned to `1.92` — `native/rust-toolchain.toml:3`.
- Tests are inline, heaviest in `strategies/drl_strategy.rs` (10), `training/dueling_dqn.rs` (9), `training/collector.rs` (8), `fast_dqn.rs`, `lightweight_dqn.rs`, `training/replay_buffer.rs`, `training/sum_tree.rs` (7 each).
- `native/package.json` `"test": "cargo test"`; `npm run build` = `napi build --platform --release` (needed only for the Node scripts, not for tests).
- `strategies::thibot::tests::test_zapzap_decision` was red until 2026-09-23: the test, not the strategy, was wrong. Its `GameState::new(4)` left every opponent with an empty hand, i.e. 0 points, which counteracts any call (GAME_RULES.md: lower *or equal*), so Thibot rightly refused a 3-point ZapZap. The fixture now deals the opponents five cards.
- CI gate (`native` job): `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test` (no `--locked`: `native/Cargo.lock` is untracked). The two `erasing_op` findings were `0 * 45 + i` / `i * 128 + 0` in a diagnostic test that deliberately indexes neuron 0, not bugs.
- Other ad-hoc Node checks in `native/`: `benchmark.js`, `test-comparison.js`, `test-ml-components.js` (not part of any suite).

### Frontend (`frontend/`)
- vitest config inside `frontend/vite.config.js:19-30` (`happy-dom`, globals, setup `src/test/setup.js` mocking `EventSource` and `localStorage`). Details in [[Frontend]].
- Component and flow tests render the real components against a mocked `services/api` (`apiClient.get`/`post`), a mocked `useAuth` or a real `AuthProvider` over a mocked `services/auth`, and a mocked `useSSE`; `src/test/gameState.js` builds the `GET /game/:partyId/state` body the `GameBoard` and `GameFlow` tests serve.
- A mocked state load resolves outside `act()`: React commits the DOM, then runs the passive effects (`useEffect`) in a later task, so a `findBy…` can return and a `fireEvent` land in between, first under CI load. A component must not undo, in an effect, what a click right after the first render did: `PlayerHand` resets its selection on a hand-size change during render (`frontend/src/components/Game/PlayerHand.jsx`), and `PlayerHand.test.jsx` › "should keep a card clicked as soon as the hand appears" reproduces the window without load. `fireEvent` itself is wrapped in `act()`, so an assertion right after it sees the synchronous state it set.
- Lint: `npm run lint` exits 0; the 9 remaining findings are `react-hooks/exhaustive-deps` warnings, which do not fail it. Rule set and its JSX exceptions at `frontend/eslint.config.js`.
- CI gate (`frontend` job): Node 24, `npm ci`, `npm run lint`, `npx vitest run`, `npm run build`. The job keeps its `name:` "Frontend — build", which branch protection pins.

### Node backend (root; production runs it)
- `npm test` → `jest` (`package.json:10`); `jest.config.js` sets `clearMocks`, `collectCoverage: true` (writes `coverage/` at the root on every run), `coverageProvider: "v8"`, `roots: ["<rootDir>/tests"]` and ignores `<rootDir>/tests/e2e/`. Without those two, jest also collected `frontend/`'s vitest files, the Playwright spec and every copy under `.claude/worktrees/` (~600 suites). Tests: `tests/unit/**` (entities, use cases, JwtService, DB connection, SSE presence over a real `createApp` on port 0 — `tests/unit/api/presence.test.js`) and `tests/integration/**` (repositories, migrations) — all against `src/`, the code production runs.
- The repository suites (`tests/integration/repositories/`) open `src/infrastructure/database/sqlite/DatabaseConnection.js`, the class `src/api/bootstrap.js` opens in production, with its schema. `connection.test.js` and `migrations.test.js` test `src/infrastructure/database/sqlite/connection.js`, an older connection whose only caller is `src/infrastructure/di/container.js`, which nothing requires.
- The integration suites write SQLite files under `data/` (`data/test-*.db`) and delete them after.
- `npm run test:e2e` → Playwright (`package.json:11-15`): `testDir: './tests/e2e/scenarios'` (only `smoke.spec.js`, 8 tests), 1 worker, 30 s timeout, `headless: false`, chromium only (`playwright.config.js:10-88`). It starts `node tests/e2e/setup/test-server.js` on 9999 — an Express server wiring the legacy `src/` DI container (`tests/e2e/setup/test-server.js:6-18`) — and `npm run dev` in `frontend/` on 5173 (`playwright.config.js:91-110`). It therefore tests the React frontend against the **Node** backend — which is, in fact, the one in production ([[Deployment]]).
- `node scripts/test-api.js` hits `http://localhost:9999` (`scripts/test-api.js:9`); usable against either backend.
- CI runs jest in the `node` job (Node 20, the major of the production image) and builds the root `Dockerfile` in the `image` job. The Playwright suite runs nowhere.

### Backend parity (`tests/parity/`)
- **What**: the same HTTP scenarios against the Node backend (the reference: production
  runs it) and the Rust backend (the target), compared. `parity.test.js` starts `node
  app.js` and the release binary (`zapzap-rust/target/release/zapzap-backend`,
  `PARITY_RUST_BIN` overrides it) on two free ports, each on its own scratch SQLite file
  (Node `DB_PATH`, Rust `DATABASE_URL=sqlite:<file>?mode=rwc`) under `/dev/shm` when it
  exists (fsync on a disk triples the time), the same `JWT_SECRET` and `ADMIN_PASSWORD`,
  both with their cwd in the temp dir (no `.env` read, Node's logs land there); it waits
  for `/api/health` (and Node's `Port: <n>` line: a port found free can be taken by
  another process), and kills both at the end. Node creates the `admin` account at
  startup (`src/api/bootstrap.js`); Rust has no such step, so the suite registers it and
  sets `is_admin` in SQL.
- **Scenarios** (`scenarios.js`): auth (register, duplicate, validation, login, missing
  and bad token); parties (create with and without name/settings, list, details, join,
  full, leave, start, too few players, a non-member reading the state, a private party's
  invite code, the owner leaving, delete); illegal moves (hand size missing, out of range,
  out of turn, by a non-member; a card not in hand, an invalid combination, a card twice,
  out of turn, draw before play, zapzap with a high hand, nextRound too early); 16 games
  of three human players to their end, played side by side; history, stats (leaderboard
  `minGames=0`), `/api/bots`, health, an unknown route (under `/api` and at the root) and a served path
  asked with an unserved method; admin (users, parties,
  statistics, set/revoke admin, delete a user, stop and delete a party, an unknown admin
  path and an unserved method without a token, as a non-admin and as the admin). No bots: both
  backends play them on their own with no off switch, and they add randomness. Each step
  leaves both backends in the same state whatever they answered, so one difference does
  not cascade. Node cannot create a private party (its owner fails its own invite-code
  check), so that party is created public and made private in SQL on both.
- **The player** (`lib/game.js`), the same on both: on its turn it picks hand size 4,
  calls ZapZap as soon as its hand is worth 5 or less, otherwise plays what sheds the
  most points (all its cards of one rank, or its highest card), and draws from the deck
  (the first draw of a round takes the last played card).
- **Compared** (`lib/recorder.js`, `lib/compare.js`): per step, the HTTP status, the error
  `code`, and the recursive set of `path:type` of the body (`lib/shape.js`: player-index
  and id map keys collapse to `#`/`<id>`, a null counts as absent, an array one side only
  ever returned empty is not compared element-wise), plus chosen values normalized
  (UUIDs, JWTs, ISO dates, invite codes become placeholders; keys sorted). A step called
  many times (every play of 16 games) is compared on the union of what it returned.
  Dealt cards are never compared: no seed can be shared. Rust deals when the party
  starts, Node when the hand size is chosen: the state in the hand-size phase is compared
  without its hands.
- **GAME_RULES.md, per backend**: turn order after each action, 54 cards after the deal,
  distinct card ids, hand sizes, the round's scores recomputed from the revealed hands
  (lowest hand 0 — every tied lowest hand —, others their points with Jokers at 25, a
  counteracted caller its points plus 5 per other active player), eliminations above 100,
  the next round's starter skipping eliminated players, Golden Score and the winner, a
  repeated card refused. A broken rule is the difference `invariant:<rule>@<backend>`.
- **The game end**: both backends end the game inside the zapzap of its last round, so
  the player reads it from the `/state` of that finished round (`gameState.gameFinished`
  and `party.status == "finished"`, and Rust's zapzap answer when it says so), checks it
  against GAME_RULES.md (`rules.game-over`: over exactly after a Golden Score round or
  with one player left), checks `gameState.winner` (`rules.winner`), and expects the
  nextRound that follows to answer 400 (`rules.no-round-after-game-over`, recorded as
  `game.nextRound.after-game-over`). Every game must reach its end (`game.reached-end`),
  and `parity.test.js` fails unless `rules.winner` ran in each of the 16 games on both
  backends. Until 2026-09-24 the player stopped at that 400 and never checked the end.
- **`divergences.json`** lists every known difference: `{id, class, wip, why,
  sometimes?}`. `class` is `node-bug` (Node is wrong — a 500 on a client error, leaked
  hands, a route promising a field it never sends, unauthenticated bot routes — and Rust
  rightly differs) or `pending` (Rust must change); `wip` names the local entry that
  owns it. The suite fails on a difference not listed and on a listed one that no longer
  occurs — fixing Rust means deleting its lines. `sometimes: true` marks a difference that
  hangs on a random deal (a tie for the lowest hand): it may be absent from a run. A
  failure prints each difference with both responses, normalized.
- Run: `npm run test:parity`; `PARITY_DUMP=<file>` writes every difference found as JSON,
  `PARITY_TIMING=1` prints each scenario's time.

### Flutter end to end (`frontend-flutter/integration_test/`)
- `integration_test/play_round_test.dart`: the real client, no fake and no fixture, against
  a live backend — registers a fresh user (`e2e_<base-36 time>`), creates a party of three
  with two easy bots (`Bot — Facile`), starts it, then plays until the end-of-round screen
  shows: the hand size when it is its pick, the first card of the hand, a draw from the
  deck, ZapZap as soon as it is enabled. It checks `roundOver`, the three
  `roundEndPlayer-<i>` rows, `roundEndMe`, the `zapZapBanner` (a round only ends on a
  call) and Next round (or Back to games). It drives widget keys only, in French
  (`locale: fr`, the bot option's label). A round is a few dozen turns; the test gives it
  5 min (`roundTimeout`) and each screen 30 s, and a timeout fails with the steps taken and
  the text on screen.
- `test_driver/integration_test.dart` is the host side (`integrationDriver()`); the steps
  land in `frontend-flutter/build/integration_response_data.json`. `flutter test` runs
  `test/` only, so the `flutter` job does not run it (the `flutter-e2e` job does); `flutter analyze` covers it (dev dependencies
  `integration_test` and `flutter_driver`, from the SDK).
- **`scripts/flutter_e2e.sh`** runs it end to end, as CI does: in a `mktemp -d` directory
  it seeds the bot accounts (`DB_PATH=<dir>/e2e.db node scripts/init-bots.js`, the Node
  DDL, which the Rust backend takes as is), starts the Rust backend's debug build from
  `zapzap-rust/` with a generated `JWT_SECRET` (`openssl rand -hex 32`), waits for
  `/api/health` (60 s), starts chromedriver and waits for its `/status` (30 s), then runs
  the `flutter drive` of step 3 below, headless. It exits with `flutter drive`'s status,
  stops what it started by process id, prints the backend log's last 80 lines on a
  failure, and removes the directory. Environment: `E2E_BACKEND_BIN` (default
  `${CARGO_TARGET_DIR:-zapzap-rust/target}/debug/zapzap-backend`), `E2E_API_PORT` (9921),
  `E2E_DRIVER_PORT` (4461), `CHROMEDRIVER` (default `$CHROMEWEBDRIVER/chromedriver`, which
  a GitHub runner sets, else `chromedriver` on the PATH). Needs `cargo build --locked` in
  `zapzap-rust/`, `npm ci` at the root and `flutter pub get`. Locally (2026-09-24, Chrome
  153): `CHROMEDRIVER=<cft>/chromedriver E2E_API_PORT=9551 E2E_DRIVER_PORT=9552
  scripts/flutter_e2e.sh`, about 3.5 min, one minute of it the web compile.
- **Procedure by hand** (checked 2026-09-24, Chrome 153, Node backend):
  1. A backend with the bot accounts, on a port of your choice, on a throwaway database
     (`DB_PATH`, [[Architecture]]): `npm ci && DB_PATH=/tmp/e2e.db npm run init-bots &&
     DB_PATH=/tmp/e2e.db PORT=9921 NODE_ENV=development node app.js` (development allows
     any `http://localhost:` origin, `src/api/server.js:32-45`; the test page is served
     from another port). Each run adds a user and a party, so reusing a development
     database works too.
  2. A chromedriver of Chrome's major version, on a free port:
     `npx @puppeteer/browsers install chromedriver@<google-chrome --version>`, then
     `chromedriver --port=4461`.
  3. From `frontend-flutter/`:
     `flutter drive --driver=test_driver/integration_test.dart
     --target=integration_test/play_round_test.dart -d web-server --browser-name=chrome
     --driver-port=4461 --browser-dimension=390x844
     --dart-define=API_BASE_URL=http://localhost:9921` — headless, a phone-sized page.
     It ends on `All tests passed.`, in about 1.5 min (most of it the compile).
  4. Kill both by port (`lsof -ti:9921 | xargs kill`, the same for 4461).
- On the web a focused text field swallows the next tap, so a dropdown tapped just after
  typing never opens: the test types the party's name after choosing the seats.

### CI workflow (`.github/workflows/ci.yml`)
- Triggers: push to `master`, any pull request, manual dispatch (`on:`). PR runs are cancelled when superseded, master runs never (`concurrency:`). `permissions: contents: read` (workflow level).

| Job | Condition | Steps | Timeout |
|---|---|---|---|
| `scope` | always | self-test, then flags | 5 min |
| `rust` | `needs.scope.outputs.rust != 'false'` | fmt, clippy -D warnings, unit and integration tests | 30 min |
| `native` | `native != 'false'` | fmt, clippy -D warnings, tests | 30 min |
| `frontend` | `frontend != 'false'` | npm ci, lint, vitest, build | 15 min |
| `image` | `image != 'false'` | `nginx -t` on `nginx/nginx.conf`, `docker build -t zapzap-rust-backend:ci zapzap-rust`, `docker build -t zapzap-node-backend:ci .` (the root `Dockerfile` production runs: `node:20-alpine`, npm 10, `npm ci --only=production` — a lockfile only a newer npm accepts fails here), `docker build -t zapzap-frontend:ci frontend`, `docker build -t zapzap-frontend-flutter:ci frontend-flutter`, then `scripts/pwa_image_smoke.sh` (35 checks on the running PWA image: `/app/`, the deep-link fallback, a missing file's 404, the manifest, the icons and their content types, the exact cache headers, CanvasKit served locally) | 60 min |
| `hooks` | `hooks != 'false'` | `scripts/hooks_selftest.sh` ([[Hooks]]) | 10 min |
| `flutter` | `flutter != 'false'` | JDK 17 (`actions/setup-java`, Gradle cache), Flutter 3.47.2 (`subosito/flutter-action@v2`, pub cache), `pub get --enforce-lockfile`, `gen-l10n`, `analyze`, `test`, `build web --base-href /app/ --no-web-resources-cdn` (the flags the PWA image uses), `build apk --debug` (runner's Android SDK) | 30 min |
| `flutter-e2e` | `flutter != 'false'` | Rust 1.92 (`Swatinem/rust-cache` on `zapzap-rust`), Node 20, Flutter 3.47.2, `cargo build --locked` in `zapzap-rust`, `npm ci`, `pub get --enforce-lockfile`, `gen-l10n`, `scripts/flutter_e2e.sh` (the runner's Chrome and chromedriver) | 30 min |
| `node` | `node != 'false'` | Node 20 (`actions/setup-node`, npm cache), `npm ci`, `npm test` | 15 min |
| `parity` | `parity != 'false'` | Rust 1.92 (`Swatinem/rust-cache` on `zapzap-rust`), Node 20, `cargo build --release --locked` in `zapzap-rust`, `npm ci`, `npm run test:parity` | 30 min |

- **A job's `name:` is its check context, and five of them are pinned by branch
  protection**: `Rust backend — fmt, clippy, test`, `Native engine — fmt, build, test`,
  `Frontend — build`, `Images — backend and frontend build`, `Hooks — self-test`
  ([[ParallelDelivery]]). Renaming one is not cosmetic: the required context stops
  reporting, and every pull request is `BLOCKED` for ever with no failing check to show
  why. What a job grew to do belongs in a step name or a comment, not in `name:`. This bit
  #36, whose `image` job had been renamed to mention the Flutter PWA, and #41, which renamed
  `native`. A comment above each pinned `name:` in `ci.yml` repeats the warning, and the
  ship-parallel agent prompt forbids the rename. The `node` job's
  `Node backend — jest`, the `parity` job's `Backend parity — Node vs Rust`, the
  `flutter` job's name and the `flutter-e2e` job's `Flutter end to end — a round against
  the Rust backend` are not pinned: adding them to branch protection is the user's
  call. Changing a pinned name
  on purpose means changing branch protection in the same breath, which is the user's
  setting to change.
- Every downstream `if:` starts with `!cancelled()` and tests `!= 'false'` so that a failed or output-less `scope` runs everything, and a job skipped by `if:` still reports Success for branch protection; no workflow-level `paths:` filter, because a filtered required check never reports (the comment above the `rust` job).
- Rust caching via `Swatinem/rust-cache@v2` per crate (`rust` and `native` jobs).

### The scope job (`scripts/ci_scope.sh`)
- On push/dispatch every flag is `true` (step "Which jobs this change needs"). On a PR it lists changed files with `gh api .../pulls/$PR/files --paginate`, including `previous_filename` so renames count on both sides; ≥ 3000 files → everything; otherwise pipes the list into `scripts/ci_scope.sh` — all in that step.
- `scripts/ci_scope.sh` is a pure function of stdin paths → `rust= native= frontend= image= hooks= flutter= node= parity=`, in the order `ci.yml` declares the jobs. Per path, first match wins; the last case is the catch-all:

| Pattern | Flags |
|---|---|
| `*.md`, `.llmwiki/*`, `docs/*`, `LICENSE`, `image.png` | none |
| `zapzap-rust/src/infrastructure/auth/*`, `zapzap-rust/tests/fixtures/bcrypt_node_compat.json` | rust, node, image, parity (jest's `RustBcryptCompat.test.js` checks that Node verifies the hashes Rust writes) |
| `zapzap-rust/*` | rust, image, parity |
| `data/*` | rust (bot params; `zapzap-rust/data` → `../data`) |
| `native/*` | native |
| `frontend/*` | frontend, image |
| `frontend-flutter/*` | flutter, image (the PWA image is built from it, [[Deployment]]) |
| `nginx/*` | image |
| `.claude/hooks/*`, `.claude/settings.json`, the scripts `hooks_selftest.sh` drives, `deploy.sh`, `rebuild.sh` | hooks |
| `scripts/pwa_image_smoke.sh` | image |
| `src/infrastructure/database/sqlite/DatabaseConnection.js` | rust, node, image, parity (`zapzap-rust/tests/schema_tests.rs` compares it with the Rust schema) |
| Node backend: `src/*`, `app.js`, `logger.js`, root `package.json`, `package-lock.json` | node, image, parity (the root `Dockerfile` copies them) |
| `views/*`, `public/*`, root `Dockerfile`, `.dockerignore` | image |
| `tests/parity/*` | parity |
| `tests/*`, `jest.config.js` | node |
| `playwright.config.js`, `eslint.config.mjs` | none |
| anything else (`.github/`, `.claude/`, `scripts/`, new dirs) | everything |

- `scripts/ci_scope_selftest.sh` pins the classification with `check "<r n f i h fl no pa>" <paths...>` cases and runs first in the `scope` job (step "Scope classifier self-test"): a broken classifier fails `scope`, which makes every job run.
- Try locally: `git diff --name-only origin/master...HEAD | scripts/ci_scope.sh` (`ci_scope.sh:14`); `scripts/ci_scope_selftest.sh`.

### Tracked gaps (local wip entries, described)
- Bot strategies with identical `if/else` branches (`vince_bot.rs` thresholds, `thibot.rs` `select_hand_size`) currently silenced with `#[allow(clippy::if_same_then_else)]` to keep the Rust clippy gate green.

### Pre-commit gate
- `.claude/hooks/guard-bash.sh` runs the fast static half of CI before a commit, chosen by path: `cargo fmt --check` + clippy in `zapzap-rust`, `cargo fmt --check` + clippy in `native`, `npm run lint` and `npm run build` in `frontend`, `dart format --set-exit-if-changed` over `lib test` and `flutter analyze` (after an offline `pub get` and `gen-l10n`) in `frontend-flutter`. The test suites and the Flutter builds stay in CI. Table and setup refusals: [[Hooks]].

## Decisions & History
- 2026-09-24 (fix/rust-parity-last-items): the parity player now checks the game end. It had treated the final nextRound 400 as a failure and stopped there on every game of both backends; the two agreed, so the comparison passed while `rules.game-over` and `rules.winner` never ran. A per-game counter asserted in `parity.test.js` keeps it from going silent again. No new difference came out of it.
- CI was introduced in commit 1e063d6 (squash of the chore/ci branch): "To start green, zapzap-rust/ and native/ are run through cargo fmt, and the backend's clippy findings are fixed ... or allowed where the code is a tuning knob (bot thresholds) or an API choice. The pre-existing red parts — the API integration tests with no schema, frontend lint and vitest, native clippy — are left out of the gates and tracked as local wip entries."
- Rust 1.92 pinned because the latest stable clippy added a lint 1.92 lacks (`sort_by_key`) and the image's former `rust:1.83` could not parse `base64ct` 1.8.1 (edition 2024) — commit message of the toolchain pin, folded into 1e063d6; comment `zapzap-rust/rust-toolchain.toml:1-2`.
- The scope classifier fails open by design: "Being wrong must cost a slow run, never an untested merge" (`scripts/ci_scope.sh:10-12`).
- The legacy Node suites were excluded from CI (`scripts/ci_scope.sh`) on the premise that the Rust backend is the target. Production still runs Node, so its changes reached production ungated.
- **2026-09-23: the Node backend is gated** (user decision). #39 went green and then failed to build on the NAS (npm 10 in `node:20-alpine` rejected a lockfile npm 11 accepted): the `image` job now builds the root `Dockerfile`. jest was 59/314 red on master, every failure test drift, none a bug in `src/`: messages translated to French, `handSize` moved out of `PartySettings` to a per-round choice, `JoinParty` no longer auto-starting a full party (commit 9712a26: the owner starts it), a single card being a legal play, mocks missing `updateLastLogin`/`recordGameAction`, and the repository suites opening the older `connection.js` whose schema lacks `users.user_type`. The tests were realigned with the code, none deleted or skipped, and the `node` job runs them. `deploy.sh` and `rebuild.sh` were classified as `hooks`, so a change to them no longer rebuilds every image.
- 2026-09-23 (fix/rust-api-schema): `--tests` joined the `rust` job once the backend created its own schema; `api_tests` had also caught `POST /api/party` without `name` answering 422 instead of Node's 400 `MISSING_PARTY_NAME`, fixed in the handler rather than in the test.
- **Frontend lint and vitest made green and gated (2026-09-23).** The 122 red tests were written against an older UI: English labels (the auth forms are French now), class-name hooks (`.player-card`, `.player-row`) that no longer exist, a prop-driven `GameBoard` that became the `/game/:partyId` route loading its own state, `ActionButtons`' `onDraw` split into `onDrawFromDeck`/`onDrawFromDiscard`, and a hand size that moved from party creation to `HandSizeSelector`. They were rewritten against the current components with their intent kept; the five counteract assertions were aligned on `GAME_RULES.md`'s `hand + (active players − 1) × 5`, which the code already applied. Only the three `CreateParty` hand-size tests were dropped (the field is gone), replaced by `HandSizeSelector.test.jsx`.
- **2026-09-24 (test/backend-parity): the Rust backend is compared with the Node one in CI.**
  The switch to Rust needs to know every way Rust answers differently from production. The
  user decided: Node is the reference except where it is buggy (a 500 on a client error,
  leaked hands or deck, a wrong rule, unauthenticated admin-like routes), where Rust keeps
  the correct behaviour and the difference is `node-bug`; the rest is `pending`, each with
  a wip entry; the job fails on an unlisted difference and on a listed one that went away,
  so the list stays true. Human-only games (bots play on their own with no off switch)
  with a deterministic player; dealt cards are not compared (no shared seed), so a game
  is compared by the shapes of its responses and each backend is checked against
  GAME_RULES.md on its own. A single game left keys to chance (a counteract, an
  elimination's rotation): 16 games side by side make them all but certain, and the one
  difference that hangs on a rare deal (a tie for the lowest hand) is marked
  `sometimes`. `node --test`, no dependency, kept out of `npm test` (`jest.config.js`
  ignores `tests/parity/`). The Node backend now reads `DB_PATH`, which the scratch
  databases needed.
- **2026-09-24 (test/flutter-e2e): the Flutter client is proved against a live backend**, locally. Widget tests use fixtures, and nothing had played a game through the client since the manual checks of 2026-09-23. Local first, against the Node backend production runs; CI (a job starting the Rust backend) is its own entry. `flutter drive` on `web-server` rather than an emulator: Chrome is on every development machine, and the PWA is what production serves.
- **2026-09-24 (chore/flutter-e2e-ci): the Flutter end-to-end test runs in CI**, job
  `flutter-e2e`, against the Rust backend (the target) rather than the Node one the local
  procedure used: since #42 it builds its own schema and since #73 it only needs a
  `JWT_SECRET`, so the job needs no database file. The bots are still seeded by the Node
  script, which is what the local procedure and production use. A debug build: it compiles
  faster than the parity job's release build and plays a round of easy bots just as well.
  The job runs on the `flutter` flag only (a pull request touching `frontend-flutter/`,
  and master): a backend change that breaks the client shows on master, and the parity
  suite covers the HTTP contract on every backend change. A deliberately failing assertion
  turned the job red before merge (the pull request cites the run).
- **2026-09-24 (fix/react-flaky-tests): two React flakes were one component bug.** The
  GameFlow full turn posted `cardIds: [13]` instead of `[0, 13]` (CI runs 35871008309,
  36035892492) and GameBoard's selection test saw A♠ unselected (36021063517): the first
  card clicked was lost. `PlayerHand` cleared its selection in a `useEffect` on
  `hand.length`; after a load rendered outside `act()`, that mount effect could run after
  the first click and wipe it (seen with a sequence counter: click, reset, click). The
  reset moved into render, which runs before any click can; raising timeouts would not
  have helped, since the lost click never comes back. Reproduced with 16 vitest processes
  pinned to one CPU (`taskset -c 0`); 50 runs in a row of each file pass that way since.
