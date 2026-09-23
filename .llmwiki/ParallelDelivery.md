# ParallelDelivery

> Scope: how changes reach production — worktrees, one pull request per theme, lanes by
> risk, serial squash merges, deploy after each merge, local cleanup, and `wip/`.
> Procedure: the `ship-parallel` skill. Related: [[Hooks]] · [[Deployment]] · [[Testing]]
> Updated: 2026-09-23

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
- The required contexts are the five job **names**, verbatim, so a workflow that renames a
  job blocks every pull request until the name comes back ([[Testing]]). A pull request
  therefore never renames a job's `name:`; renaming is a separate step the user takes in
  the protection settings. A comment above each required job's `name:` in `ci.yml` says so,
  and so does the ship-parallel agent prompt (#41 renamed `native` and blocked every merge).
  `gh pr view <n> --json mergeStateStatus` reads `BLOCKED` while `gh pr checks` shows
  everything green — that combination means a missing context, not a failing one.

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

### The shared browser

- The Playwright MCP server is **one browser for every agent of the session**: a parallel
  agent's reload lands on whichever page is current, and every tab shares localStorage and
  tokens. So each agent opens its own tab (`browser_tabs` new), works only in it and closes
  it (ship-parallel agent prompt); a check that needs a clean origin is serialised.
- The server writes screenshots, console logs and network dumps to `.playwright-mcp/` in the
  checkout it runs from. The directory is gitignored and nothing in it is tracked; it is
  debris, never committed, and not an agent's to delete while others run.

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
`wip/README.md` by `wip.sh init`). An agent in a worktree reads entries by absolute path
but never writes them: it lists each new entry, complete, under a `## New wip entries`
heading of its final report, and the orchestrator writes them to `todo_nr/` after the
hand-back (`ship-parallel` §2). The orchestrator closes entries after the merge (§5). `wip-refine` decides what
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
- **New entries travel in the agent's report (2026-09-23, the user's decision).** An agent
  with `isolation: "worktree"` is refused writes outside its worktree, so a found problem
  either got lost or reached `wip/` through an ad-hoc request. No permission was opened for
  `<MAIN>/wip/**`: the report heading is the one path, and the orchestrator writes.
- **The 18 `.playwright-mcp/` screenshots were removed (2026-09-23).** Debugging captures
  of the React UI from December 2025, referenced nowhere; git history keeps them.
- **Squash, update by merging `master` in** (`gh api -X PUT .../update-branch`): linear history
  without force-pushes, which would destroy an agent's commits in its worktree.
