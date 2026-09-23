# Testing

> Scope: every test suite in the repo, how to run it, its current state, and what CI (`.github/workflows/ci.yml`) runs, skips and why — including the `scope` job.
> Related: [[Backend]] · [[NativeEngine]] · [[Frontend]] · [[Architecture]]
> Updated: 2026-09-23

## Facts

### Suites at a glance
| Suite | Run | State 2026-09-22 | In CI |
|---|---|---|---|
| Rust backend unit tests (`#[cfg(test)]` in `zapzap-rust/src`) | `cd zapzap-rust && cargo test --lib --bins` | green | yes |
| Rust backend API tests (`zapzap-rust/tests/api_tests.rs`, 10 tests) | `cargo test --test api_tests` | green | yes |
| Rust backend schema tests (`zapzap-rust/tests/schema_tests.rs`, 2 tests) | `cargo test --test schema_tests` | green | yes |
| Native engine (`native/src`, 98 `#[test]`) | `cd native && cargo test` | 97 pass, 1 fail | yes, failing test skipped |
| Native clippy | `cargo clippy --all-targets` | deny-level errors | no |
| Frontend vitest (`frontend/src/**/__tests__`) | `cd frontend && npx vitest run` | 122/279 fail (13 files) | no |
| Frontend lint | `npm run lint` | 59 errors, 9 warnings | no |
| Frontend build | `npm run build` | green | yes |
| Flutter client (`frontend-flutter/test`) | `cd frontend-flutter && flutter analyze && flutter test` | green | yes, with `build web` and `build apk --debug` |
| Node backend jest (`tests/unit`, `tests/integration`) | `npm test` (root) | green, 19 suites, 316 tests (2026-09-23) | yes (`node` job) |
| Legacy Playwright e2e (`tests/e2e`) | `npm run test:e2e` | not tracked | no |
| Docker images and the proxy config | `docker build zapzap-rust`, `docker build .` (the Node backend production runs), `docker build frontend`, `docker build frontend-flutter` + `scripts/pwa_image_smoke.sh`, `nginx -t` on `nginx/nginx.conf` | green | yes |

### Rust backend (`zapzap-rust/`)
- Toolchain pinned to `1.92` with rustfmt + clippy — `zapzap-rust/rust-toolchain.toml:3-4`. The same version is used by CI (`dtolnay/rust-toolchain@1.92`, `rust` job) and the image's builder tag.
- Unit tests (34 `#[test]`/`#[tokio::test]`) live next to the code: `domain/services/game_service.rs` (6), `infrastructure/bot/card_analyzer.rs` (5), `strategies/thibot.rs` (4), `strategies/vince_bot.rs` (4), `domain/value_objects/game_state.rs` (3), `application/bot/reflect_on_round.rs` (3), `bot/llm_memory.rs` (3), `auth/password.rs` (2), `strategies/llm_bot.rs` (2), `services/llm_service.rs` (2).
- Integration tests: `zapzap-rust/tests/api_tests.rs:19-31` builds the axum router with `DATABASE_URL=sqlite::memory:` and `JWT_SECRET=test-secret-key`, then drives it with tower `oneshot` (register, login, create/list party — `api_tests.rs:111-348`). Each test gets a fresh in-memory DB, whose tables `AppState::new()` creates (`zapzap-rust/src/infrastructure/app_state.rs:64`).
- Schema tests: `zapzap-rust/tests/schema_tests.rs` reads the Node DDL from `src/infrastructure/database/sqlite/DatabaseConnection.js` at compile time (`include_str!`) and checks that `schema.sql` creates the same objects (`rust_schema_matches_node_schema`) and that the startup step leaves a filled Node-built DB unchanged (`schema_step_is_a_noop_on_a_node_built_database`). See [[Backend]].
- CI gate (`rust` job): `cargo fmt --check`, `cargo clippy --locked --all-targets -- -D warnings`, `cargo test --locked --lib --bins --tests` (unit and integration tests).
- `scripts/ci_scope.sh` sends a change to `src/` to `node` and `image`, and a change to `src/infrastructure/database/sqlite/DatabaseConnection.js` (the Node DDL `schema_tests` reads) to `rust` as well, so a PR that edits only the Node schema still runs the parity test.

### Native engine (`native/`)
- Toolchain pinned to `1.92` — `native/rust-toolchain.toml:3`.
- Tests are inline, heaviest in `strategies/drl_strategy.rs` (10), `training/dueling_dqn.rs` (9), `training/collector.rs` (8), `fast_dqn.rs`, `lightweight_dqn.rs`, `training/replay_buffer.rs`, `training/sum_tree.rs` (7 each).
- `native/package.json` `"test": "cargo test"`; `npm run build` = `napi build --platform --release` (needed only for the Node scripts, not for tests).
- Known red: `strategies::thibot::tests::test_zapzap_decision` (`native/src/strategies/thibot.rs:919`). Open question whether the strategy or the test is wrong.
- CI gate (`native` job): `cargo fmt --check`, then `cargo test -- --skip strategies::thibot::tests::test_zapzap_decision`. No clippy: `cargo clippy --all-targets` reports "this operation has no effect" (5), `erasing_op` "will always return zero" (2, possibly a real bug), needless range loops, identical `if` blocks, too many arguments.
- Other ad-hoc Node checks in `native/`: `benchmark.js`, `test-comparison.js`, `test-ml-components.js` (not part of any suite).

### Frontend (`frontend/`)
- vitest config inside `frontend/vite.config.js:19-30` (`happy-dom`, globals, setup `src/test/setup.js` mocking `EventSource` and `localStorage`). Details in [[Frontend]].
- Failures likely come from tests written against an older UI/API shape (e.g. `src/__tests__/compliance/README.compliance.test.js` checks rules "specified in README.md (lines 315-428)").
- Lint errors are mostly `no-unused-vars` (e.g. `frontend/src/utils/validation.js:45`, `:166`), rule set at `frontend/eslint.config.js:26`.
- CI gate (`frontend` job): Node 24, `npm ci`, `npm run build` only; comment above the build step: lint and `vitest run` "are red on master today ... they join this job once green".

### Node backend (root; production runs it)
- `npm test` → `jest` (`package.json:10`); `jest.config.js` sets `clearMocks`, `collectCoverage: true` (writes `coverage/` at the root on every run), `coverageProvider: "v8"`, `roots: ["<rootDir>/tests"]` and ignores `<rootDir>/tests/e2e/`. Without those two, jest also collected `frontend/`'s vitest files, the Playwright spec and every copy under `.claude/worktrees/` (~600 suites). Tests: `tests/unit/**` (entities, use cases, JwtService, DB connection) and `tests/integration/**` (repositories, migrations) — all against `src/`, the code production runs.
- The repository suites (`tests/integration/repositories/`) open `src/infrastructure/database/sqlite/DatabaseConnection.js`, the class `src/api/bootstrap.js` opens in production, with its schema. `connection.test.js` and `migrations.test.js` test `src/infrastructure/database/sqlite/connection.js`, an older connection whose only caller is `src/infrastructure/di/container.js`, which nothing requires.
- The integration suites write SQLite files under `data/` (`data/test-*.db`) and delete them after.
- `npm run test:e2e` → Playwright (`package.json:11-15`): `testDir: './tests/e2e/scenarios'` (only `smoke.spec.js`, 8 tests), 1 worker, 30 s timeout, `headless: false`, chromium only (`playwright.config.js:10-88`). It starts `node tests/e2e/setup/test-server.js` on 9999 — an Express server wiring the legacy `src/` DI container (`tests/e2e/setup/test-server.js:6-18`) — and `npm run dev` in `frontend/` on 5173 (`playwright.config.js:91-110`). It therefore tests the React frontend against the **Node** backend — which is, in fact, the one in production ([[Deployment]]).
- `node scripts/test-api.js` hits `http://localhost:9999` (`scripts/test-api.js:9`); usable against either backend.
- CI runs jest in the `node` job (Node 20, the major of the production image) and builds the root `Dockerfile` in the `image` job. The Playwright suite runs nowhere.

### CI workflow (`.github/workflows/ci.yml`)
- Triggers: push to `master`, any pull request, manual dispatch (`on:`). PR runs are cancelled when superseded, master runs never (`concurrency:`). `permissions: contents: read` (workflow level).

| Job | Condition | Steps | Timeout |
|---|---|---|---|
| `scope` | always | self-test, then flags | 5 min |
| `rust` | `needs.scope.outputs.rust != 'false'` | fmt, clippy -D warnings, unit and integration tests | 30 min |
| `native` | `native != 'false'` | fmt, tests (1 skipped) | 30 min |
| `frontend` | `frontend != 'false'` | npm ci, build | 15 min |
| `image` | `image != 'false'` | `nginx -t` on `nginx/nginx.conf`, `docker build -t zapzap-rust-backend:ci zapzap-rust`, `docker build -t zapzap-node-backend:ci .` (the root `Dockerfile` production runs: `node:20-alpine`, npm 10, `npm ci --only=production` — a lockfile only a newer npm accepts fails here), `docker build -t zapzap-frontend:ci frontend`, `docker build -t zapzap-frontend-flutter:ci frontend-flutter`, then `scripts/pwa_image_smoke.sh` (35 checks on the running PWA image: `/app/`, the deep-link fallback, a missing file's 404, the manifest, the icons and their content types, the exact cache headers, CanvasKit served locally) | 60 min |
| `hooks` | `hooks != 'false'` | `scripts/hooks_selftest.sh` ([[Hooks]]) | 10 min |
| `flutter` | `flutter != 'false'` | JDK 17 (`actions/setup-java`, Gradle cache), Flutter 3.47.2 (`subosito/flutter-action@v2`, pub cache), `pub get --enforce-lockfile`, `gen-l10n`, `analyze`, `test`, `build web --base-href /app/ --no-web-resources-cdn` (the flags the PWA image uses), `build apk --debug` (runner's Android SDK) | 30 min |
| `node` | `node != 'false'` | Node 20 (`actions/setup-node`, npm cache), `npm ci`, `npm test` | 15 min |

- **A job's `name:` is its check context, and five of them are pinned by branch
  protection**: `Rust backend — fmt, clippy, test`, `Native engine — fmt, build, test`,
  `Frontend — build`, `Images — backend and frontend build`, `Hooks — self-test`
  ([[ParallelDelivery]]). Renaming one is not cosmetic: the required context stops
  reporting, and every pull request is `BLOCKED` for ever with no failing check to show
  why. What a job grew to do belongs in a step name or a comment, not in `name:`. This bit
  #36, whose `image` job had been renamed to mention the Flutter PWA. The `node` job's
  `Node backend — jest` and the `flutter` job's name are not pinned: adding them to branch
  protection is the user's call. Changing a pinned name
  on purpose means changing branch protection in the same breath, which is the user's
  setting to change.
- Every downstream `if:` starts with `!cancelled()` and tests `!= 'false'` so that a failed or output-less `scope` runs everything, and a job skipped by `if:` still reports Success for branch protection; no workflow-level `paths:` filter, because a filtered required check never reports (the comment above the `rust` job).
- Rust caching via `Swatinem/rust-cache@v2` per crate (`rust` and `native` jobs).

### The scope job (`scripts/ci_scope.sh`)
- On push/dispatch every flag is `true` (step "Which jobs this change needs"). On a PR it lists changed files with `gh api .../pulls/$PR/files --paginate`, including `previous_filename` so renames count on both sides; ≥ 3000 files → everything; otherwise pipes the list into `scripts/ci_scope.sh` — all in that step.
- `scripts/ci_scope.sh` is a pure function of stdin paths → `rust= native= frontend= image= hooks= flutter= node=`, in the order `ci.yml` declares the jobs. Per path, first match wins; the last case is the catch-all:

| Pattern | Flags |
|---|---|
| `*.md`, `.llmwiki/*`, `docs/*`, `LICENSE`, `image.png` | none |
| `zapzap-rust/*` | rust, image |
| `data/*` | rust (bot params; `zapzap-rust/data` → `../data`) |
| `native/*` | native |
| `frontend/*` | frontend, image |
| `frontend-flutter/*` | flutter, image (the PWA image is built from it, [[Deployment]]) |
| `nginx/*` | image |
| `.claude/hooks/*`, `.claude/settings.json`, the scripts `hooks_selftest.sh` drives, `deploy.sh`, `rebuild.sh` | hooks |
| `scripts/pwa_image_smoke.sh` | image |
| `src/infrastructure/database/sqlite/DatabaseConnection.js` | rust, node, image (`zapzap-rust/tests/schema_tests.rs` compares it with the Rust schema) |
| Node backend: `src/*`, `app.js`, `logger.js`, root `package.json`, `package-lock.json` | node, image (the root `Dockerfile` copies them) |
| `views/*`, `public/*`, root `Dockerfile`, `.dockerignore` | image |
| `tests/*`, `jest.config.js` | node |
| `playwright.config.js`, `eslint.config.mjs` | none |
| anything else (`.github/`, `.claude/`, `scripts/`, new dirs) | everything |

- `scripts/ci_scope_selftest.sh` pins the classification with `check "<r n f i h fl no>" <paths...>` cases and runs first in the `scope` job (step "Scope classifier self-test"): a broken classifier fails `scope`, which makes every job run.
- Try locally: `git diff --name-only origin/master...HEAD | scripts/ci_scope.sh` (`ci_scope.sh:14`); `scripts/ci_scope_selftest.sh`.

### Tracked gaps (local wip entries, described)
- Native thibot ZapZap-decision test red: decide which side is wrong, remove the `--skip`.
- Native clippy errors: fix (start with the two `erasing_op`), then gate clippy in CI.
- Frontend vitest red (122/279) and frontend lint red (59 errors): triage/clean, then add to the `frontend` job.
- Bot strategies with identical `if/else` branches (`vince_bot.rs` thresholds, `thibot.rs` `select_hand_size`) currently silenced with `#[allow(clippy::if_same_then_else)]` to keep the Rust clippy gate green.

### Pre-commit gate
- `.claude/hooks/guard-bash.sh` runs the fast static half of CI before a commit, chosen by path: `cargo fmt --check` + clippy in `zapzap-rust`, `cargo fmt --check` in `native`, `npm run build` in `frontend`, `flutter analyze` (after an offline `pub get` and `gen-l10n`) in `frontend-flutter`. The test suites and the Flutter builds stay in CI. Table and setup refusals: [[Hooks]].

## Decisions & History
- CI was introduced in commit 1e063d6 (squash of the chore/ci branch): "To start green, zapzap-rust/ and native/ are run through cargo fmt, and the backend's clippy findings are fixed ... or allowed where the code is a tuning knob (bot thresholds) or an API choice. The pre-existing red parts — the API integration tests with no schema, frontend lint and vitest, native clippy — are left out of the gates and tracked as local wip entries."
- Rust 1.92 pinned because the latest stable clippy added a lint 1.92 lacks (`sort_by_key`) and the image's former `rust:1.83` could not parse `base64ct` 1.8.1 (edition 2024) — commit message of the toolchain pin, folded into 1e063d6; comment `zapzap-rust/rust-toolchain.toml:1-2`.
- The scope classifier fails open by design: "Being wrong must cost a slow run, never an untested merge" (`scripts/ci_scope.sh:10-12`).
- The legacy Node suites were excluded from CI (`scripts/ci_scope.sh`) on the premise that the Rust backend is the target. Production still runs Node, so its changes reached production ungated.
- **2026-09-23: the Node backend is gated** (user decision). #39 went green and then failed to build on the NAS (npm 10 in `node:20-alpine` rejected a lockfile npm 11 accepted): the `image` job now builds the root `Dockerfile`. jest was 59/314 red on master, every failure test drift, none a bug in `src/`: messages translated to French, `handSize` moved out of `PartySettings` to a per-round choice, `JoinParty` no longer auto-starting a full party (commit 9712a26: the owner starts it), a single card being a legal play, mocks missing `updateLastLogin`/`recordGameAction`, and the repository suites opening the older `connection.js` whose schema lacks `users.user_type`. The tests were realigned with the code, none deleted or skipped, and the `node` job runs them. `deploy.sh` and `rebuild.sh` were classified as `hooks`, so a change to them no longer rebuilds every image.
- 2026-09-23 (fix/rust-api-schema): `--tests` joined the `rust` job once the backend created its own schema; `api_tests` had also caught `POST /api/party` without `name` answering 422 instead of Node's 400 `MISSING_PARTY_NAME`, fixed in the handler rather than in the test.
