# KnownLimits

> Scope: what is deliberately left out of the gates and the harness, and why. Open work
> itself lives in `wip/` (local, `scripts/wip.sh list all`).
> Related: [[Testing]] · [[Hooks]] · [[Deployment]]
> Updated: 2026-09-22

## Facts

| Gap | Where it shows | Why it stays for now |
|---|---|---|
| Production runs the Node backend, which no CI job and no hook gate checks | [[Deployment]], `scripts/ci_scope.sh` classifies `src/` as needing no job | the target is `zapzap-rust/`; gating legacy code the project is leaving costs more than the switch |
| `zapzap-rust/tests/api_tests.rs` is not run in CI (`--lib --bins` only) | `.github/workflows/ci.yml`, rust job | the in-memory DB has no schema: the Rust backend creates no tables ([[Backend]]) |
| Frontend lint (59 errors) and vitest (122 failing tests) are not run in CI | frontend job builds only | pre-existing red; each is a wip entry, added to the job once green |
| `native/` has no clippy gate, one test skipped by name | native job | clippy deny-level errors and a failing Thibot test, both wip entries |
| The hooks cannot see a commit made inside a script, a `git merge`, or a merge through the API | [[Hooks]] | a hook sees a command string only |
| `AUDIT_REPORT.md` (2025-11) audited the old jQuery/EJS app | removed 2026-09-22 | it described code that no longer exists (git history keeps it) |
| `BACKEND_API.md` described the Node API with several errors (JWT 24 h instead of 7 days, 2 players minimum instead of 3, SSE heartbeat 15 s instead of 20 s) | removed 2026-09-22 | [[Api]] replaces it, written from the Rust routes |

## Decisions & History

- **Start the gates green (2026-09-22).** When CI was added, every suite already red was left
  out of it and recorded as an entry, rather than added red (a red required check blocks
  every merge) or silenced in place.
