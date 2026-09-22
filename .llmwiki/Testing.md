# Testing

> Scope: every test suite in the repo, how to run it, its current state, and what CI (`.github/workflows/ci.yml`) runs, skips and why — including the `scope` job.
> Related: [[Backend]] · [[NativeEngine]] · [[Frontend]] · [[Architecture]]
> Updated: 2026-09-22

## Facts

### Suites at a glance
| Suite | Run | State 2026-09-22 | In CI |
|---|---|---|---|
| Rust backend unit tests (`#[cfg(test)]` in `zapzap-rust/src`) | `cd zapzap-rust && cargo test --lib --bins` | green | yes |
| Rust backend API tests (`zapzap-rust/tests/api_tests.rs`, 10 tests) | `cargo test --test api_tests` | 7/10 fail (500 instead of 201) | no |
| Native engine (`native/src`, 98 `#[test]`) | `cd native && cargo test` | 97 pass, 1 fail | yes, failing test skipped |
| Native clippy | `cargo clippy --all-targets` | deny-level errors | no |
| Frontend vitest (`frontend/src/**/__tests__`) | `cd frontend && npx vitest run` | 122/279 fail (13 files) | no |
| Frontend lint | `npm run lint` | 59 errors, 9 warnings | no |
| Frontend build | `npm run build` | green | yes |
| Legacy Node jest (`tests/unit`, `tests/integration`) | `npm test` (root) | not tracked | no |
| Legacy Playwright e2e (`tests/e2e`) | `npm run test:e2e` | not tracked | no |
| Docker images | `docker build zapzap-rust`, `docker build frontend` | green | yes |

### Rust backend (`zapzap-rust/`)
- Toolchain pinned to `1.92` with rustfmt + clippy — `zapzap-rust/rust-toolchain.toml:3-4`. The same version is used by CI (`dtolnay/rust-toolchain@1.92`, `ci.yml:95`) and the image's builder tag.
- Unit tests (34 `#[test]`/`#[tokio::test]`) live next to the code: `domain/services/game_service.rs` (6), `infrastructure/bot/card_analyzer.rs` (5), `strategies/thibot.rs` (4), `strategies/vince_bot.rs` (4), `domain/value_objects/game_state.rs` (3), `application/bot/reflect_on_round.rs` (3), `bot/llm_memory.rs` (3), `auth/password.rs` (2), `strategies/llm_bot.rs` (2), `services/llm_service.rs` (2).
- Integration tests: `zapzap-rust/tests/api_tests.rs:19-31` builds the axum router with `DATABASE_URL=sqlite::memory:` and `JWT_SECRET=test-secret-key`, then drives it with tower `oneshot` (register, login, create/list party — `api_tests.rs:111-348`). They fail because `AppState::new()` never creates tables: the migration call is commented out (`zapzap-rust/src/infrastructure/app_state.rs:64`) and there is no `migrations/` directory. See [[Backend]] for the schema situation.
- CI gate (`ci.yml:101-106`): `cargo fmt --check`, `cargo clippy --locked --all-targets -- -D warnings`, `cargo test --locked --lib --bins` (the `--lib --bins` leaves `tests/` out; comment at `ci.yml:103-105`).

### Native engine (`native/`)
- Toolchain pinned to `1.92` — `native/rust-toolchain.toml:3`.
- Tests are inline, heaviest in `strategies/drl_strategy.rs` (10), `training/dueling_dqn.rs` (9), `training/collector.rs` (8), `fast_dqn.rs`, `lightweight_dqn.rs`, `training/replay_buffer.rs`, `training/sum_tree.rs` (7 each).
- `native/package.json` `"test": "cargo test"`; `npm run build` = `napi build --platform --release` (needed only for the Node scripts, not for tests).
- Known red: `strategies::thibot::tests::test_zapzap_decision` (`native/src/strategies/thibot.rs:919`). Open question whether the strategy or the test is wrong.
- CI gate (`ci.yml:126-128`): `cargo fmt --check`, then `cargo test -- --skip strategies::thibot::tests::test_zapzap_decision`. No clippy: `cargo clippy --all-targets` reports "this operation has no effect" (5), `erasing_op` "will always return zero" (2, possibly a real bug), needless range loops, identical `if` blocks, too many arguments.
- Other ad-hoc Node checks in `native/`: `benchmark.js`, `test-comparison.js`, `test-ml-components.js` (not part of any suite).

### Frontend (`frontend/`)
- vitest config inside `frontend/vite.config.js:19-30` (`happy-dom`, globals, setup `src/test/setup.js` mocking `EventSource` and `localStorage`). Details in [[Frontend]].
- Failures likely come from tests written against an older UI/API shape (e.g. `src/__tests__/compliance/README.compliance.test.js` checks rules "specified in README.md (lines 315-428)").
- Lint errors are mostly `no-unused-vars` (e.g. `frontend/src/utils/validation.js:45`, `:166`), rule set at `frontend/eslint.config.js:26`.
- CI gate (`ci.yml:141-149`): Node 24, `npm ci`, `npm run build` only; comment `ci.yml:147-148`: lint and `vitest run` "are red on master today ... they join this job once green".

### Legacy Node backend (root)
- `npm test` → `jest` (`package.json:10`); `jest.config.js:18,21,27,35` sets `clearMocks`, `collectCoverage: true` (writes `coverage/` at the root on every run), `coverageProvider: "v8"`. Tests: `tests/unit/**` (entities, use cases, JwtService, DB connection) and `tests/integration/**` (repositories, migrations) — all against `src/` (legacy).
- `npm run test:e2e` → Playwright (`package.json:11-15`): `testDir: './tests/e2e/scenarios'` (only `smoke.spec.js`, 8 tests), 1 worker, 30 s timeout, `headless: false`, chromium only (`playwright.config.js:10-88`). It starts `node tests/e2e/setup/test-server.js` on 9999 — an Express server wiring the legacy `src/` DI container (`tests/e2e/setup/test-server.js:6-18`) — and `npm run dev` in `frontend/` on 5173 (`playwright.config.js:91-110`). It therefore tests the React frontend against the **Node** backend — which is, in fact, the one in production ([[Deployment]]).
- `node scripts/test-api.js` hits `http://localhost:9999` (`scripts/test-api.js:9`); usable against either backend.
- None of this runs in CI; `scripts/ci_scope.sh:46-48` classifies `src/`, `tests/`, `views/`, `public/` and root JS configs as "no job".

### CI workflow (`.github/workflows/ci.yml`)
- Triggers: push to `master`, any pull request, manual dispatch (`ci.yml:3-7`). PR runs are cancelled when superseded, master runs never (`ci.yml:11-13`). `permissions: contents: read` (`ci.yml:15-16`).

| Job | Condition | Steps | Timeout |
|---|---|---|---|
| `scope` | always | self-test, then flags | 5 min (`ci.yml:27`) |
| `rust` | `needs.scope.outputs.rust != 'false'` | fmt, clippy -D warnings, unit tests | 30 min |
| `native` | `native != 'false'` | fmt, tests (1 skipped) | 30 min |
| `frontend` | `frontend != 'false'` | npm ci, build | 15 min |
| `image` | `image != 'false'` | `docker build -t zapzap-rust-backend:ci zapzap-rust`, `docker build -t zapzap-frontend:ci frontend` (`ci.yml:159-162`) | 40 min |

- Every downstream `if:` starts with `!cancelled()` and tests `!= 'false'` so that a failed or output-less `scope` runs everything, and a job skipped by `if:` still reports Success for branch protection; no workflow-level `paths:` filter, because a filtered required check never reports (`ci.yml:75-81`).
- Rust caching via `Swatinem/rust-cache@v2` per crate (`ci.yml:98-100,123-125`).

### The scope job (`scripts/ci_scope.sh`)
- On push/dispatch every flag is `true` (`ci.yml:58-62`). On a PR it lists changed files with `gh api .../pulls/$PR/files --paginate`, including `previous_filename` so renames count on both sides (`ci.yml:63-64`); ≥ 3000 files → everything (`ci.yml:68-72`); otherwise pipes the list into `scripts/ci_scope.sh` (`ci.yml:73`).
- `scripts/ci_scope.sh` is a pure function of stdin paths → `rust= native= frontend= image=` (`ci_scope.sh:1-14,56`). Per path, first match wins (`ci_scope.sh:27-53`, catch-all at `:50-52`):

| Pattern | Flags |
|---|---|
| `*.md`, `.llmwiki/*`, `docs/*`, `LICENSE`, `image.png` | none |
| `zapzap-rust/*` | rust, image |
| `data/*` | rust (bot params; `zapzap-rust/data` → `../data`) |
| `native/*` | native |
| `frontend/*` | frontend, image |
| `nginx/*` | image |
| legacy: `src/*`, `tests/*`, `views/*`, `public/*`, `app.js`, `logger.js`, jest/playwright/eslint configs, root `package*.json` | none |
| anything else (`.github/`, `.claude/`, `scripts/`, new dirs) | everything |

- `scripts/ci_scope_selftest.sh` pins the classification with `check "<r n f i>" <paths...>` cases and runs first in the `scope` job (`ci.yml:43-44`): a broken classifier fails `scope`, which makes every job run.
- Try locally: `git diff --name-only origin/master...HEAD | scripts/ci_scope.sh` (`ci_scope.sh:14`); `scripts/ci_scope_selftest.sh`.

### Tracked gaps (local wip entries, described)
- Rust API tests have no schema: give the backend a self-created schema (sqlx migrations or the Node DDL from `src/infrastructure/database/`), then re-add `--tests` to the `rust` job.
- Native thibot ZapZap-decision test red: decide which side is wrong, remove the `--skip`.
- Native clippy errors: fix (start with the two `erasing_op`), then gate clippy in CI.
- Frontend vitest red (122/279) and frontend lint red (59 errors): triage/clean, then add to the `frontend` job.
- Bot strategies with identical `if/else` branches (`vince_bot.rs` thresholds, `thibot.rs` `select_hand_size`) currently silenced with `#[allow(clippy::if_same_then_else)]` to keep the Rust clippy gate green.

### Pre-commit gate (pending)
- A `chore/claude-hooks` branch (not merged on 2026-09-22) adds a Claude Code Bash guard that runs, before a commit, `cargo fmt --check` + clippy in `zapzap-rust`, `cargo fmt --check` in `native`, and `npm run build` in `frontend` — mirroring CI. The comments in both `rust-toolchain.toml` files already refer to "the commit hook".

## Decisions & History
- CI was introduced in commit 1e063d6 (squash of the chore/ci branch): "To start green, zapzap-rust/ and native/ are run through cargo fmt, and the backend's clippy findings are fixed ... or allowed where the code is a tuning knob (bot thresholds) or an API choice. The pre-existing red parts — the API integration tests with no schema, frontend lint and vitest, native clippy — are left out of the gates and tracked as local wip entries."
- Rust 1.92 pinned because the latest stable clippy added a lint 1.92 lacks (`sort_by_key`) and the image's former `rust:1.83` could not parse `base64ct` 1.8.1 (edition 2024) — commit message of the toolchain pin, folded into 1e063d6; comment `zapzap-rust/rust-toolchain.toml:1-2`.
- The scope classifier fails open by design: "Being wrong must cost a slow run, never an untested merge" (`scripts/ci_scope.sh:10-12`).
- The legacy Node suites are excluded from CI (`scripts/ci_scope.sh`) on the premise that the Rust backend is the target. Production still runs Node, so its changes reach production ungated until the switch — a known gap ([[KnownLimits]]).
