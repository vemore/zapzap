# KnownLimits

> Scope: what is deliberately left out of the gates and the harness, and why. Open work
> itself lives in `wip/` (local, `scripts/wip.sh list all`).
> Related: [[Testing]] · [[Hooks]] · [[Deployment]]
> Updated: 2026-09-23

## Facts

| Gap | Where it shows | Why it stays for now |
|---|---|---|
| The Node backend production runs has no pre-commit hook gate, and its Playwright e2e suite runs nowhere | [[Hooks]], [[Testing]] | CI gates it since 2026-09-23 (`node` job: jest; `image` job: the root `Dockerfile`); the e2e suite needs a browser and both servers |
| Frontend lint (59 errors) and vitest (122 failing tests) are not run in CI | frontend job builds only | pre-existing red; each is a wip entry, added to the job once green |
| The hooks cannot see a commit made inside a script, a `git merge`, or a merge through the API | [[Hooks]] | a hook sees a command string only |
| `AUDIT_REPORT.md` (2025-11) audited the old jQuery/EJS app | removed 2026-09-22 | it described code that no longer exists (git history keeps it) |
| `BACKEND_API.md` described the Node API with several errors (JWT 24 h instead of 7 days, 2 players minimum instead of 3, SSE heartbeat 15 s instead of 20 s) | removed 2026-09-22 | [[Api]] replaces it, written from the Rust routes |

## Decisions & History

- **Start the gates green (2026-09-22).** When CI was added, every suite already red was left
  out of it and recorded as an entry, rather than added red (a red required check blocks
  every merge) or silenced in place.
- **Gate the Node backend after all (2026-09-23).** The user reversed the "not worth gating
  legacy code" call: production runs `src/`, and #39 reached the NAS with a lockfile npm 10
  rejects. The jest suites were brought green (tests realigned with the current code, none
  deleted) and joined CI, and the `image` job builds the root `Dockerfile`.
- **API integration tests gated (2026-09-23).** `zapzap-rust/tests/api_tests.rs` left this
  table when the Rust backend got its own schema step; the `rust` job now runs `--tests`.
