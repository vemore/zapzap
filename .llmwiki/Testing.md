# Testing

> Scope: every test suite in the repo, how to run it, its current state, and what CI (`.github/workflows/ci.yml`) runs, skips and why — including the `scope` job.
> Related: [[Backend]] · [[NativeEngine]] · [[Frontend]] · [[Architecture]]
> Updated: 2026-09-26

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
| Flutter client (`frontend-flutter/test`) | `cd frontend-flutter && dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test` | green | yes, with `build web`, `build apk --debug` and `build apk --release`; the format check and the analyzer also in the commit hook |
| Flutter end to end (`frontend-flutter/integration_test/`) | `scripts/flutter_e2e.sh` (the Rust backend on a fresh database, then `flutter drive`), or by hand, below | green (2026-09-24) | yes (`flutter-e2e` job) |
| Docker images and the proxy config | `scripts/backend_image_smoke.sh` (the production compose's Rust `backend`, Bedrock feature, built and started until its health check passes; then uid 1000, the CA store and the size under 40 MB), `docker build frontend`, `docker build frontend-flutter` + `scripts/pwa_image_smoke.sh`, the proxy image (`nginx/Dockerfile`) and `nginx -t` in it, `docker compose config` of both compose files | green | yes |

### Rust backend (`zapzap-rust/`)
- Toolchain pinned to `1.92` with rustfmt + clippy — `zapzap-rust/rust-toolchain.toml:3-4`. The same version is used by CI (`dtolnay/rust-toolchain@1.92`, `rust` job) and the image's builder tag.
- Unit tests live next to the code (93 on 2026-09-25, 1 of them ignored). Count them in `zapzap-rust/` rather than trust a number here: `cargo test --lib -- --list | grep -c ': test$'` for the total, `grep -rc '#\[\(tokio::\)\?test\]' src | grep -v ':0$'` per file. The files: `application/auth/login_with_google.rs`, `application/bot/{create_bot,delete_bot,reflect_on_round,runner}.rs`, `application/game/next_round.rs`, `domain/entities/player.rs`, `domain/services/game_service.rs`, `domain/value_objects/{game_state,party_settings}.rs`, `infrastructure/app_state.rs` (the JWT secret), `infrastructure/auth/password.rs` (bcrypt at cost 10, the fixture of hashes the Node backend wrote; the ignored `print_fixture_hash` rewrites it), `infrastructure/bot/{card_analyzer,llm_memory}.rs`, `infrastructure/bot/strategies/{llm_bot,thibot,vince_bot}.rs`, `infrastructure/services/google_oauth.rs` (the key cache with an injected fetcher), `infrastructure/services/llm_service.rs` (the bounded startup probe, the cheap Bedrock health check), `infrastructure/services/session_manager.rs`. The Google and bot-admin races run on `RacingUserRepo` (`infrastructure/database/repositories/racing_user_repo.rs`, test-only), whose lookups can be made stale; tokens are signed with the test-only key `zapzap-rust/tests/fixtures/google_oauth_test_rsa.pem`, never checked against Google.
- Integration tests: `create_test_app_with_state` (`zapzap-rust/tests/api_tests.rs`) builds the application `main.rs` serves (`api::build_app`) with `DATABASE_URL=sqlite::memory:`, `JWT_SECRET=test-secret-key` and `BOT_ACTION_DELAY_MS=200` (bots pause 200 ms, not production's seconds) (`create_test_app_with_state` also hands back the `AppState`, to set a game state or read SSE events), then drives it with tower `oneshot`: auth and party basics, then the error contract — tests per party and game route family asserting the status and `code` (the Node backend's, kept) (`assert_error`, `api_tests.rs:539`), unreadable bodies answering 400, `partyCreated`, `isMyTurn`, adding a bot and the zapzap scores, on a started three-human party (`started_party`, `api_tests.rs:462`). Each test gets a fresh in-memory DB, whose tables `AppState::new()` creates (its `ensure_schema` call, `zapzap-rust/src/infrastructure/app_state.rs`). The security tests at the end (the router of `create_test_app_with_state` also serves `/suscribeupdate`): private join/details, game state, `nextRound`, `trigger-bot`, private history, admin 401/403, SSE per-user filtering and public-party lifecycle events (read the streamed body until a sentinel event), `/history/public` without private games, a deleted user's token refused, and `test_server_refuses_to_start_without_jwt_secret`, which runs the `zapzap-backend` binary (`CARGO_BIN_EXE_zapzap-backend`) in an empty directory without `JWT_SECRET`. Last, module `google_and_bot_admin`: `POST /api/auth/google` (missing credential, forged token, not configured, a full login with an injected key set) and the admin bot routes. Then the bodies of the three auth 401 codes, the `ROUTE_NOT_FOUND` 404 of an unknown path and of an unserved method (`test_unserved_method_answers_route_not_found`), the unknown `/api/admin` paths behind the auth and admin checks, and both health checks. Last, the `/state` and `nextRound` contracts: `test_state_sends_nodes_always_present_keys`, `test_state_last_action_of_select_play_and_draw` (a deck draw names no card), `test_state_last_action_of_a_reshuffling_draw`, `test_state_last_action_of_a_zapzap`, `test_next_round_answers_nodes_keys` and `test_next_round_at_the_end_of_the_game_answers_nodes_keys`, `test_next_round_after_the_game_ending_zapzap_is_refused` (see [[Api]]). Then the last items the Node/Rust comparison found: `test_admin_set_admin_bad_body_answers_nodes_400`, `test_join_full_started_party_answers_party_full`, `test_delete_party_by_a_non_member_answers_not_in_party`.
- Schema tests: `zapzap-rust/tests/schema_tests.rs` replays `zapzap-rust/tests/fixtures/node_built_schema.sql`, a frozen `sqlite_master` of a Node-built database (no `.js` file is read), and checks that `schema.sql` creates the same objects (`rust_schema_matches_the_node_built_schema`) and that the startup step leaves a filled Node-built DB unchanged (`schema_step_is_a_noop_on_a_node_built_database`), and that a failing step (an entrypoint-rebuilt `users` table without `google_id`) leaves the DB unchanged (`schema_step_failure_leaves_the_database_unchanged`). See [[Backend]].
- CI gate (`rust` job): `cargo fmt --check`, `cargo clippy --locked --all-targets -- -D warnings`, `cargo test --locked --lib --bins --tests` (unit and integration tests).

### Native engine (`native/`)
- Toolchain pinned to `1.92` — `native/rust-toolchain.toml:3`.
- Tests are inline, heaviest in `strategies/drl_strategy.rs` (10), `training/dueling_dqn.rs` (9), `training/collector.rs` (8), `fast_dqn.rs`, `lightweight_dqn.rs`, `training/replay_buffer.rs`, `training/sum_tree.rs` (7 each).
- `native/package.json` `"test": "cargo test"`; `npm run build` = `napi build --platform --release` (needed only for `scripts/train-native.js` and `scripts/genetic-optimize-thibot.js`, not for tests).
- `strategies::thibot::tests::test_zapzap_decision` was red until 2026-09-23: the test, not the strategy, was wrong. Its `GameState::new(4)` left every opponent with an empty hand, i.e. 0 points, which counteracts any call (GAME_RULES.md: lower *or equal*), so Thibot rightly refused a 3-point ZapZap. The fixture now deals the opponents five cards.
- CI gate (`native` job): `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test` (no `--locked`: `native/Cargo.lock` is untracked). The two `erasing_op` findings were `0 * 45 + i` / `i * 128 + 0` in a diagnostic test that deliberately indexes neuron 0, not bugs.

### Frontend (`frontend/`)
- vitest config inside `frontend/vite.config.js:19-30` (`happy-dom`, globals, setup `src/test/setup.js` mocking `EventSource` and `localStorage`). Details in [[Frontend]].
- Component and flow tests render the real components against a mocked `services/api` (`apiClient.get`/`post`), a mocked `useAuth` or a real `AuthProvider` over a mocked `services/auth`, and a mocked `useSSE`; `src/test/gameState.js` builds the `GET /game/:partyId/state` body the `GameBoard` and `GameFlow` tests serve.
- A mocked state load resolves outside `act()`: React commits the DOM, then runs the passive effects (`useEffect`) in a later task, so a `findBy…` can return and a `fireEvent` land in between, first under CI load. A component must not undo, in an effect, what a click right after the first render did: `PlayerHand` resets its selection on a hand-size change during render (`frontend/src/components/Game/PlayerHand.jsx`), and `PlayerHand.test.jsx` › "should keep a card clicked as soon as the hand appears" reproduces the window without load. `fireEvent` itself is wrapped in `act()`, so an assertion right after it sees the synchronous state it set.
- Lint: `npm run lint` exits 0; the 9 remaining findings are `react-hooks/exhaustive-deps` warnings, which do not fail it. Rule set and its JSX exceptions at `frontend/eslint.config.js`.
- CI gate (`frontend` job): Node 24, `npm ci`, `npm run lint`, `npx vitest run`, `npm run build`. The job keeps its `name:` "Frontend — build", which branch protection pins.

### Flutter end to end (`frontend-flutter/integration_test/`)
- `integration_test/play_round_test.dart`: the real client, no fake and no fixture, against
  a live backend — registers a fresh user (`e2e_<base-36 time>`), creates a party of three
  with two easy bots (`Bot — Facile`), starts it, then plays until the end-of-round screen
  shows: four cards when the hand size is its pick, the first suggestion chip
  (`handSuggestion-0`, the play taking the most points off, `suggestPlays` in
  `lib/utils/rules.dart`) — the first card when there is none — a draw from the deck,
  ZapZap as soon as it is enabled. It checks `roundOver`, the three
  `roundEndPlayer-<i>` rows, `roundEndMe`, the `zapZapBanner` (a round only ends on a
  call) and Next round (or Back to games). It drives widget keys only, in French
  (`locale: fr`, the bot option's label). Shedding the most points each turn brings the
  hand to ZapZap in about ten turns: the test allows 60 moves (`maxMoves`), with 5 min
  (`roundTimeout`) as a safety net and 30 s per screen; either limit fails with the steps
  taken and the text on screen.
- `test_driver/integration_test.dart` is the host side (`integrationDriver()`); the steps
  land in `frontend-flutter/build/integration_response_data.json`. `flutter test` runs
  `test/` only, so the `flutter` job does not run it (the `flutter-e2e` job does); `flutter analyze` covers it (dev dependencies
  `integration_test` and `flutter_driver`, from the SDK).
- **`scripts/flutter_e2e.sh`** runs it end to end, as CI does: in a `mktemp -d` directory
  it seeds the bot accounts (`DB_PATH=<dir>/e2e.db zapzap-backend seed`, which creates the
  file and its schema, [[Backend]] § Seeding), starts the Rust backend's debug build from
  `zapzap-rust/` with a generated `JWT_SECRET` (`openssl rand -hex 32`), waits for
  `/api/health` (60 s), starts chromedriver and waits for its `/status` (30 s), then runs
  the `flutter drive` of step 3 below, headless. It exits with `flutter drive`'s status,
  stops what it started by process id, prints the backend log's last 80 lines on a
  failure, and removes the directory. Environment: `E2E_BACKEND_BIN` (default
  `${CARGO_TARGET_DIR:-zapzap-rust/target}/debug/zapzap-backend`), `E2E_API_PORT` (9921),
  `E2E_DRIVER_PORT` (4461), `E2E_BOT_ACTION_DELAY_MS` (0: the backend's
  `BOT_ACTION_DELAY_MS`, the bots' pause between two actions, [[Backend]]), `CHROMEDRIVER` (default `$CHROMEWEBDRIVER/chromedriver`, which
  a GitHub runner sets, else `chromedriver` on the PATH). Needs `cargo build --locked` in
  `zapzap-rust/` and `flutter pub get`. Locally (2026-09-24, Chrome
  153): `CHROMEDRIVER=<cft>/chromedriver E2E_API_PORT=9551 E2E_DRIVER_PORT=9552
  scripts/flutter_e2e.sh`, about 80 s (2026-09-25), 45 s of it the web compile; the round
  takes 4 to 9 turns.
- **Procedure by hand** (checked 2026-09-24 with Chrome 153 against the Node backend of the time; the steps below use the Rust one):
  1. A backend with the bot accounts, on a port of your choice, on a throwaway database
     (`DB_PATH`, [[Architecture]]), from `zapzap-rust/`: `DB_PATH=/tmp/e2e.db cargo run --
     seed && JWT_SECRET=$(openssl rand -hex 32) DB_PATH=/tmp/e2e.db PORT=9921 cargo run`
     (its CORS layer is permissive; the test page is served from another port). Each run
     adds a user and a party, so reusing a development database works too.
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
| `image` | `image != 'false'` | `scripts/build_privacy_page.py --check` with pandoc at the version the script pins (the release `.deb` from GitHub): a committed `nginx/privacy.html` stale against `privacy_policy.md` fails the job ([[Deployment]] § The privacy policy); the proxy image `docker build -t zapzap-proxy:ci nginx`, then `nginx -t` in it; `docker compose config` of the root compose file and of `docker-compose.prod.yml` (each valid with a `JWT_SECRET`, refused without one); `scripts/backend_image_smoke.sh` (`docker compose build backend` — the production image, `CARGO_FEATURES=bedrock` —, then the container on an empty scratch database, own project and container name, until its compose health check (busybox `wget`) is `healthy`; then uid 1000 asserted for the container and for the image's own user, the system CA store present, and the image under 40 MB); `docker build -t zapzap-frontend:ci frontend`, `docker build -t zapzap-frontend-flutter:ci frontend-flutter`, then `scripts/pwa_image_smoke.sh` (35 checks on the running PWA image: `/app/`, the deep-link fallback, a missing file's 404, the manifest, the icons and their content types, the exact cache headers, CanvasKit served locally) | 60 min |
| `hooks` | `hooks != 'false'` | `scripts/hooks_selftest.sh` ([[Hooks]]), `scripts/deploy_nas_selftest.sh` ([[Deployment]]); JDK 17 and `astral-sh/setup-uv`, then pytest on `scripts/test_play_publish.py` (a fake Google service) and `scripts/test_verify_aab.py` (fake bundles signed by throwaway keystores, `VERIFY_AAB_REQUIRE_TOOLS=1` so a missing JDK fails rather than skips) ([[Release]]) | 10 min |
| `flutter` | `flutter != 'false'` | JDK 17 (`actions/setup-java`, Gradle cache), Flutter 3.47.2 (`subosito/flutter-action@v2`, pub cache), `pub get --enforce-lockfile`, `gen-l10n`, `analyze`, `test`, `build web --base-href /app/ --no-web-resources-cdn` (the flags the PWA image uses), `build apk --debug` (runner's Android SDK, `platforms;android-36` and `build-tools;36.0.0` installed by `sdkmanager`, Gradle heap capped at 4 GB), uploaded as the artifact `app-debug` (14 days); `build apk --release` (R8, and the debug-key fallback since CI has no `key.properties`); `build appbundle --release`, which must fail naming `key.properties` | 30 min |
| `flutter-e2e` | `e2e != 'false'` | Rust 1.92 (`Swatinem/rust-cache` on `zapzap-rust`), Flutter 3.47.2, `cargo build --locked` in `zapzap-rust`, `pub get --enforce-lockfile`, `gen-l10n`, `scripts/flutter_e2e.sh` (the runner's Chrome and chromedriver) | 30 min |

- **A job's `name:` is its check context, and five of them are pinned by branch
  protection**: `Rust backend — fmt, clippy, test`, `Native engine — fmt, build, test`,
  `Frontend — build`, `Images — backend and frontend build`, `Hooks — self-test`
  ([[ParallelDelivery]]). Renaming one is not cosmetic: the required context stops
  reporting, and every pull request is `BLOCKED` for ever with no failing check to show
  why. What a job grew to do belongs in a step name or a comment, not in `name:`. This bit
  #36, whose `image` job had been renamed to mention the Flutter PWA, and #41, which renamed
  `native`. A comment above each pinned `name:` in `ci.yml` repeats the warning, and the
  ship-parallel agent prompt forbids the rename. The
  `flutter` job's name and the `flutter-e2e` job's `Flutter end to end — a round against
  the Rust backend` are not pinned: adding them to branch protection is the user's
  call. Changing a pinned name
  on purpose means changing branch protection in the same breath, which is the user's
  setting to change.
- Every downstream `if:` starts with `!cancelled()` and tests `!= 'false'` so that a failed or output-less `scope` runs everything, and a job skipped by `if:` still reports Success for branch protection; no workflow-level `paths:` filter, because a filtered required check never reports (the comment above the `rust` job).
- Rust caching via `Swatinem/rust-cache@v2` per crate (`rust` and `native` jobs).

### The scope job (`scripts/ci_scope.sh`)
- On push/dispatch every flag is `true` (step "Which jobs this change needs"). On a PR it lists changed files with `gh api .../pulls/$PR/files --paginate`, including `previous_filename` so renames count on both sides; ≥ 3000 files → everything; otherwise pipes the list into `scripts/ci_scope.sh` — all in that step.
- `scripts/ci_scope.sh` is a pure function of stdin paths → `rust= native= frontend= image= hooks= flutter= e2e=`, in the order `ci.yml` declares the jobs (`e2e` last: the `flutter-e2e` job). Per path, first match wins; the last case is the catch-all:

| Pattern | Flags |
|---|---|
| `privacy_policy.md`, `scripts/build_privacy_page.py` | image (the privacy page check; before the `*.md` rule) |
| `*.md`, `.llmwiki/*`, `docs/*`, `LICENSE`, `image.png` | none |
| `zapzap-rust/*` | rust, image, e2e (production's backend: its image, a round played through the Flutter client) |
| `data/*` | rust (bot params; `zapzap-rust/data` → `../data`) |
| `native/*` | native |
| `frontend/*` | frontend, image |
| `frontend-flutter/*` | flutter, image (the PWA image is built from it, [[Deployment]]), e2e |
| `nginx/*` | image |
| `.claude/hooks/*`, `.claude/settings.json`, the scripts `hooks_selftest.sh` drives, `scripts/deploy_nas.sh`, its self-test and `deploy.env.example`, `rebuild.sh` | hooks |
| `scripts/verify_aab.sh`, `scripts/play_publish.py` and their `test_*.py` | hooks |
| `docker-compose.prod.yml` | image, hooks |
| `scripts/pwa_image_smoke.sh`, `scripts/backend_image_smoke.sh` | image |
| `scripts/flutter_e2e.sh` | e2e |
| `store_listing/*` (the Play Store listing), `scripts/generate_store_graphics.py`, `scripts/capture_store_screenshots.{sh,js}`, `scripts/compose_store_screenshots.py` | flutter (`frontend-flutter/test/store_listing_test.dart` checks the listing against Play's limits; the generators run by hand, `store_listing/README.md`) |
| root `package.json`, `package-lock.json` (Playwright only, [[ParallelDelivery]]) | none |
| anything else (`.github/`, `.claude/`, `scripts/`, new dirs) | everything |

- `scripts/ci_scope_selftest.sh` pins the classification with `check "<r n f i h fl e2e>" <paths...>` cases and runs first in the `scope` job (step "Scope classifier self-test"): a broken classifier fails `scope`, which makes every job run.
- Try locally: `git diff --name-only origin/master...HEAD | scripts/ci_scope.sh` (`ci_scope.sh:14`); `scripts/ci_scope_selftest.sh`.

### Tracked gaps (local wip entries, described)
- Bot strategies with identical `if/else` branches (`vince_bot.rs` thresholds, `thibot.rs` `select_hand_size`) currently silenced with `#[allow(clippy::if_same_then_else)]` to keep the Rust clippy gate green.

### Pre-commit gate
- `.claude/hooks/guard-bash.sh` runs the fast static half of CI before a commit, chosen by path: `cargo fmt --check` + clippy in `zapzap-rust`, `cargo fmt --check` + clippy in `native`, `npm run lint` and `npm run build` in `frontend`, `dart format --set-exit-if-changed` over `lib test` and `flutter analyze` (after an offline `pub get` and `gen-l10n`) in `frontend-flutter`. The test suites and the Flutter builds stay in CI. Table and setup refusals: [[Hooks]].

## Decisions & History
- 2026-09-25 (chore/store-listing): the Play Store listing's limits are a Dart test in the `flutter` job (`frontend-flutter/test/store_listing_test.dart`), not a new CI job or step: `ci.yml` was another pull request's in parallel, and a new job's name would have had to join the branch protection. `scripts/ci_scope.sh` sends `store_listing/*` and its generators to `flutter` instead of the catch-all.
- 2026-09-25 (fix/flutter-e2e-round-bounded): the Flutter end-to-end round no longer runs past its 5 min at random (#99, #102, #107, each green on rerun). Since the Rust backend honours `BOT_ACTION_DELAY_MS` (1000 ms by default) each bot turn took seconds, and the driver played the first card of its hand, whose points only drifted (47 after 58 turns on #102). The script starts the bots without a pause, and the driver deals four cards and plays the suggestion taking the most points off, so the round is held to a move budget rather than to a longer timeout.
- **2026-09-25 (chore/remove-node-backend): the Node backend is removed, and its suites with it.** The jest suites (`tests/unit`, `tests/integration`), the Node vs Rust parity suite (`tests/parity`), the Playwright suite (`tests/e2e`), the `node` and `parity` CI jobs, their scope flags and the Node image build of the `image` job are gone; a path under the former Node directories now runs everything. They can still be read at `232f168` (the last master commit holding `src/`, e.g. `git show 232f168:tests/parity/parity.test.js`) and `0bfd407` (the last commit whose `docker-compose.yml` builds the Node backend, the former rollback target).
- 2026-09-25 (feat/rust-seed-accounts): the `flutter-e2e` job runs no Node. `scripts/flutter_e2e.sh` seeds its bots with the backend binary it already built (`zapzap-backend seed`), so the job lost `setup-node` and the root `npm ci`, and `src/`, `app.js`, `logger.js` and the root `package*.json` no longer set the `e2e` flag. It removes the last Node dependency of the job ahead of the Node backend's removal.
- 2026-09-24 (fix/rust-parity-last-items): the parity player now checks the game end. It had treated the final nextRound 400 as a failure and stopped there on every game of both backends; the two agreed, so the comparison passed while `rules.game-over` and `rules.winner` never ran. A per-game counter asserted in `parity.test.js` keeps it from going silent again. No new difference came out of it.
- CI was introduced in commit 1e063d6 (squash of the chore/ci branch): "To start green, zapzap-rust/ and native/ are run through cargo fmt, and the backend's clippy findings are fixed ... or allowed where the code is a tuning knob (bot thresholds) or an API choice. The pre-existing red parts — the API integration tests with no schema, frontend lint and vitest, native clippy — are left out of the gates and tracked as local wip entries."
- Rust 1.92 pinned because the latest stable clippy added a lint 1.92 lacks (`sort_by_key`) and the image's former `rust:1.83` could not parse `base64ct` 1.8.1 (edition 2024) — commit message of the toolchain pin, folded into 1e063d6; comment `zapzap-rust/rust-toolchain.toml:1-2`.
- The scope classifier fails open by design: "Being wrong must cost a slow run, never an untested merge" (`scripts/ci_scope.sh:10-12`).
- The legacy Node suites were excluded from CI (`scripts/ci_scope.sh`) on the premise that the Rust backend is the target. Production still ran Node, so its changes reached production ungated.
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
- **2026-09-24 (test/flutter-e2e): the Flutter client is proved against a live backend**, locally. Widget tests use fixtures, and nothing had played a game through the client since the manual checks of 2026-09-23. Local first, against the Node backend production then ran; CI (a job starting the Rust backend) is its own entry. `flutter drive` on `web-server` rather than an emulator: Chrome is on every development machine, and the PWA is what production serves.
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
- **2026-09-24 (chore/switch-prod-to-rust): production runs the Rust backend, so CI tests the
  image production runs.** The `image` job used to build `zapzap-rust/` without the Bedrock
  feature, which is not what the root compose builds; it now builds the compose service
  itself and starts it until its health check passes (`scripts/backend_image_smoke.sh`), and
  keeps building the Node image, which a rollback needs. The `flutter-e2e` job moved to a flag
  of its own, `e2e`, set by `frontend-flutter/` **and** `zapzap-rust/`: a round played through
  the real client is the only end-to-end test of the production backend, and a debug build
  plus one round costs a few minutes, while the `flutter` flag would also have run the
  analyzer, the widget tests and the apk build on every backend change. `src/` sets it too:
  the job seeds its bots with `scripts/init-bots.js`, which loads the Node code. The smoke
  script reads no `.env` (`--env-file /dev/null`), so a developer's secrets never reach it.
