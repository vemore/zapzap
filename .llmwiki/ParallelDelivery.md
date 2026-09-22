# ParallelDelivery

> Scope: how changes reach production — worktrees, one pull request per theme, lanes by
> risk, serial squash merges, deploy after each merge, local cleanup, and `wip/`.
> Procedure: the `ship-parallel` skill. Related: [[Hooks]] · [[Deployment]] · [[Testing]]
> Updated: 2026-09-22

## Facts

### `master` and its protection

- CI: `.github/workflows/ci.yml`, jobs `scope`, `rust`, `native`, `frontend`, `image`,
  `hooks`, `flutter`; the `scope` job decides which run ([[Testing]]). A job skipped by its `if:`
  reports Success, so a docs-only pull request satisfies required checks.
- Branch protection is set once the harness is merged (2026-09-22, after #21–#23): required
  checks = the five build jobs `rust` … `hooks` (not `scope`, and not yet `flutter`, added
  after them: until it is listed, a red `flutter` job does not stop a merge — only the
  "green or skipped" rule of the lanes does), `strict` (up to date before merging → merges
  are **serial**), linear history (**squash**), no force-push; `enforce_admins` off, so the
  hook refuses `--admin` instead. Read it with `gh api repos/vemore/zapzap/branches/master/protection`.
- Merged branches are deleted on GitHub; the local copy then reads `[gone]` and the hook
  refuses commits on it.

### Worktrees

- The **main checkout** (`/home/vemore/workspace/zapzap`) stays on `master`, fast-forwarded,
  never commits. It holds the hooks in force and the local `wip/`.
- Work happens in a worktree: `git worktree add ../zapzap-<topic> -b <type>/<topic>
  origin/master` by hand, or `.claude/worktrees/<name>` for an agent with
  `isolation: "worktree"`. Then `scripts/worktree_setup.sh <dir>`: `npm ci` in `frontend/`,
  a cargo clippy warm-up of `zapzap-rust/` on the main checkout's target dir, `flutter pub
  get` + `gen-l10n` in `frontend-flutter/` (`--no-flutter` skips it); `--deploy`
  symlinks the main checkout's `.env`. It holds `.zapzap-setup-in-progress` while running.
- `scripts/cleanup_local.sh` (dry run; `--apply`) removes branches with nothing ahead of
  `origin/master` or whose merged PR head GitHub's compare proves identical, and clean
  worktrees whose branch goes. It keeps a worktree locked by a live session, a setup marker,
  or anything modified in the last 30 minutes (`CLEANUP_IDLE_MINUTES`).

### Lanes — chosen at planning time, from what a change will touch

| Lane | What falls in it | Before merging |
|---|---|---|
| **A** | everything else | checks green or skipped, the orchestrator reads the diff |
| **B** | > 1 500 added-or-modified lines of code; a silent failure mode (schema, migration, scoring in `zapzap-rust/src/domain/`, the SSE event format); a call site many features use | A + acceptance criteria in the entry + `/code-review high` by an agent that did not write it, every finding reported to the user |
| **C** | authentication and secrets: `zapzap-rust/src/api/routes/auth.rs`, `zapzap-rust/src/api/middleware/`, `zapzap-rust/src/infrastructure/auth/`, compose environment, `nginx/` | B + an explicit go-ahead from the user for that merge |
| **D** | an experiment | a `noPullRequest` branch, never merged; what it taught becomes an entry |

A change confined to `frontend-flutter/` is lane **A** unless it meets a B criterion (its
size, most often): the client is not deployed ([[FrontendFlutter]]), so a merge reaches no
user and there is nothing to deploy after it. It becomes B or C by the same rules as the
rest once it ships, and a change that also touches the backend, `nginx/` or the compose files
is judged on those.

The reviewing agent gets these rules: verify each finding against the PR head; a wiki page
or README the change makes false is at least Medium; read a page's `Decisions & History`
before calling something redundant; judge the tests against the entry's acceptance
criteria, not coverage.

### `wip/` — local work tracking

`wip/` is gitignored and exists only in the main checkout; `scripts/wip.sh` finds it from
any worktree (`wip.sh path`). Format and lifecycle: `docs/wip-README.md` (copied to
`wip/README.md` by `wip.sh init`). Agents write new entries there by absolute path; the
orchestrator closes entries after the merge (`ship-parallel` §5). `wip-refine` decides what
moves from `todo_nr/` to `todo/` (at most 12).

## Decisions & History

- **Adopted 2026-09-22**, ported from countscore at the user's request: Claude merges and
  deploys its own green pull requests, one theme per pull request, several in parallel
  through worktrees; the main checkout stays on `master`.
- **`wip/` not committed** — the user's choice for this project. Consequences: entries cannot
  be closed inside the pull request that fixes them (the orchestrator closes them after the
  merge), and agents in worktrees reach them by absolute path.
- **Bootstrapped in three pull requests** (#21 CI, #22 hooks, #23 wiki): hooks only take
  effect once on the main checkout, and required checks can only be named once they exist.
- **Squash, update by merging `master` in** (`gh api -X PUT .../update-branch`): linear history
  without force-pushes, which would destroy an agent's commits in its worktree.
