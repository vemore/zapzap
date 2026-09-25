# KnownLimits

> Scope: what is deliberately left out of the gates and the harness, and why. Open work
> itself lives in `wip/` (local, `scripts/wip.sh list all`).
> Related: [[Testing]] · [[Hooks]] · [[Deployment]]
> Updated: 2026-09-25

## Facts

| Gap | Where it shows | Why it stays for now |
|---|---|---|
| The hooks cannot see a commit made inside a script, a `git merge`, or a merge through the API | [[Hooks]] | a hook sees a command string only |
| `AUDIT_REPORT.md` (2025-11) audited the old jQuery/EJS app | removed 2026-09-22 | it described code that no longer exists (git history keeps it) |
| `BACKEND_API.md` described the (since removed) Node API with several errors (JWT 24 h instead of 7 days, 2 players minimum instead of 3, SSE heartbeat 15 s instead of 20 s) | removed 2026-09-22 | [[Api]] replaces it, written from the Rust routes |

## Decisions & History

- **Start the gates green (2026-09-22).** When CI was added, every suite already red was left
  out of it and recorded as an entry, rather than added red (a red required check blocks
  every merge) or silenced in place.
- **Gate the Node backend after all (2026-09-23).** The user reversed the "not worth gating
  legacy code" call: production ran `src/`, and #39 reached the NAS with a lockfile npm 10
  rejects. The jest suites were brought green (tests realigned with the current code, none
  deleted) and joined CI, and the `image` job builds the root `Dockerfile`.
- **API integration tests gated (2026-09-23).** `zapzap-rust/tests/api_tests.rs` left this
  table when the Rust backend got its own schema step; the `rust` job now runs `--tests`.
- **The Flutter end-to-end test leaves this table (2026-09-24).** The `flutter-e2e` CI job
  runs it against a Rust backend it starts ([[Testing]]).
- **Production switches to Rust (2026-09-24).** The Node gates stay: `src/` is the rollback, and a rollback that does not build or does not start is worse than none. The rollback itself joins this table.
- **The Node backend is removed (2026-09-25, chore/remove-node-backend).** Its two rows leave this table: its missing hook gate and unrun Playwright suite, and the unrehearsed rollback to it — there is no Node backend to gate or roll back to; a rollback is the previous commit of the Rust deployment ([[Deployment]]). Its code can still be read at `232f168` (the last master commit holding `src/`, e.g. `git show 232f168:tests/e2e/`) and `0bfd407` (the last commit whose `docker-compose.yml` builds it, the former rollback target).
