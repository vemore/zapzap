# Hooks

> Scope: the Claude Code hooks that enforce project rules mechanically, what each refuses and
> on what evidence, and what they do not cover.
> Related: [[ParallelDelivery]] · [[Testing]] · [[Documentation]]
> Updated: 2026-09-23

## Facts

### What is configured

`.claude/settings.json` declares four handlers; the scripts are in `.claude/hooks/`.
`.claude/settings.local.json` (permissions) is separate and untouched.

| Event | Matcher | Script | What it does |
|---|---|---|---|
| `PreToolUse` | `Bash` | `guard-bash.sh` | Refuses a set of commands outright; before a commit, refuses what must not be committed and runs the gates |
| `SessionStart` | — | `session-start.sh` | Worktrees in flight, branches whose remote is gone, PRs merged into a non-master base, the open `wip/` counts, whether the branch is safe; `frontend/node_modules` missing |
| `Stop` | — | `require-pull-request.sh` | Refuses to end the turn while commits have no pull request, or while it is red or closed unmerged |
| `SubagentStop` | — | `require-pull-request.sh` | The same for an agent, judged on its worktree's branch |

**Which repository a hook judges.** Every handler resolves the repository from the payload's
`cwd` — for `guard-bash.sh`, the directory the `git` command actually runs in, following `cd`
and `git -C` (`parse_command.py` reports it) — and falls back to `CLAUDE_PROJECT_DIR`. The
hook *scripts* are read from `${CLAUDE_PROJECT_DIR}/.claude/hooks`: the rules in force are the
main checkout's copy, which is why it stays on `master` ([[ParallelDelivery]]).

`parse_command.py` tokenizes (shlex, heredoc bodies stripped) rather than grepping, so a
commit message or a heredoc that *mentions* a forbidden command passes. When it cannot tell
where a `git commit` or a bare `git push` runs (a `cd $VAR` it cannot resolve, `$(...)`), it
refuses with `unknown-repo` and asks for `git -C <literal path>`.

`scripts/hooks_selftest.sh` exercises all of it — 168 cases in sandbox repositories, with a
stubbed `gh`, `cargo`, `npm`, `flutter`, `docker-compose`, `docker` and `curl` — plus
`scripts/cleanup_local.sh`, the `flutter pub get` of `scripts/worktree_setup.sh`, and
`deploy.sh` (42 cases: the step order that makes a failed deploy a no-op rather than an
outage, the health wait that stops it reporting success over a dead site, and every refusal
— [[Deployment]]); it is the `hooks` CI job. `deploy.sh` is not classified by
`scripts/ci_scope.sh`, so a change to it runs every job, the `hooks` one included.

### What is refused, and on what evidence

| Rule | Evidence |
|---|---|
| `pkill` / `killall` whose target matches `node` (kills the VS Code server under WSL) | tokenised command; `pkill -f nodemon` and `lsof -ti:9999 \| xargs kill` pass |
| `git push --force`, `-f`, `--force-with-lease`, `--mirror`, a `+refspec` | parsed flags and refspecs; `--dry-run` passes |
| `git push` to master: a refspec whose destination is `master`, `--all`, a bare push while on master | parsed refspecs; current branch of the repository the push runs in |
| `gh pr create --base <anything but master>` | parsed `--base`; unlocked per repository by `git config zapzap.allowStackedPr true` — the user's decision |
| `gh pr merge` with `--admin`, or without `--squash`, or with `--merge`/`--rebase` | parsed flags, bundled short flags included |
| Committing on master, on a detached HEAD, on a branch whose upstream is `[gone]`, or one replaying commits already on `origin/master` | `%(upstream:track)`, `git cherry origin/master HEAD` |
| Committing a `.env` / `.env.*` (not `.env.example`), `client_secret_*.json`, a `*.db` / `*.sqlite` or a `*.db.bak-*` backup | paths the commit **adds or modifies** (`--diff-filter=d`): untracking a file with `git rm --cached` passes |
| Committing anything under `wip/`, or a root `TODO.md` / `DONE.md` | same path list |
| Committing with a red gate, or with the gate's setup missing | see below |

**Gates before a commit**, chosen from the union of paths the commit will contain (`--cached`,
plus the working-tree diff under `-a` — staged *after* the hook runs — plus `HEAD`'s files
under `--amend`, plus trailing pathspecs; during a merge, the diff against `MERGE_HEAD`):

| Paths | Gate |
|---|---|
| `zapzap-rust/` | `cargo fmt --check`, `cargo clippy --locked --all-targets -- -D warnings` (target dir shared with the main checkout) |
| `native/` | `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings` (no `--locked`: `native/Cargo.lock` is untracked; target dir shared with the main checkout) |
| `frontend/` | `npm run build`; no `frontend/node_modules` → refusal naming `npm ci --prefix <tree>/frontend` |
| `frontend-flutter/` (any file, `.md` included) | `flutter pub get --offline`, `flutter gen-l10n` (the generated l10n is not committed and goes stale), `flutter analyze`; no `flutter` on PATH or no `frontend-flutter/.dart_tool` → refusal naming `cd <tree>/frontend-flutter && flutter pub get` |
| anything else (docs, legacy `src/`) | none |

The test suites run in CI, not here. A setup refusal says to run the install as **its own**
Bash call: the hook judges the whole line before any of it runs.

### What the hooks do not cover

- **Anything a script commits** (`bash scripts/x.sh` running `git commit`), `git merge`,
  `git cherry-pick`, `git revert`: the hook sees only the command string.
- **Merging through the API or the web page**: only the branch protection stands behind it.
- **Freshness of `origin/master`**: the hooks never fetch (a fetch writes to refs every
  worktree shares). What they know is as old as the last `git fetch --prune`; a silent pass
  is not proof the branch is live.
- **Publishing**: `require-pull-request.sh` reads GitHub, never writes; silent without `gh`,
  unauthenticated, or on a branch with `git config branch.<name>.noPullRequest true`.
- **The legacy Node backend** (`src/`) has no gate although production runs it ([[KnownLimits]]).
- **Hard enforcement generally**: a missing or non-executable script exits 127, a timeout
  does not block either. They reduce a class of mistake; they do not make it impossible.

## Decisions & History

- **Ported from countscore (2026-09-22).** The user asked for countscore's harness in this
  project: wiki, hooks, pull-request delivery with CI. The Flutter-specific rules (icon
  tree-shaking, web binaries, ARB files) were dropped; the `pkill`/`killall node` rule — prose
  in the old `CLAUDE.md` ("NEVER RUN") — became a refusal, since a rule a script can decide
  should not depend on rereading a file.
- **`wip/` is local (2026-09-22).** Unlike countscore, the user wants work tracking out of
  git, so the hook refuses committing it instead of refusing a shared `TODO.md` next to it.
- **Secrets are judged on additions only.** #21 untracked `data/zapzap.db` with
  `git rm --cached`; judging deletions too would refuse exactly the commit that removes a
  database from git.
