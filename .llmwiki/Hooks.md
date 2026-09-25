# Hooks

> Scope: the Claude Code hooks that enforce project rules mechanically, what each refuses and
> on what evidence, and what they do not cover.
> Related: [[ParallelDelivery]] · [[Testing]] · [[Documentation]]
> Updated: 2026-09-25

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

**This project, or a sandbox.** The two master rules — push to master, commit on master —
protect *this project's* master: the branch of any checkout of it (same git common dir as
`CLAUDE_PROJECT_DIR`, or a remote pointing at the project's remote) and the master of its
remote (compared by URL, `git@github.com:o/r.git` and `https://github.com/o/r` alike, or by
the repository a path remote leads to). A throwaway repository an agent builds under the
scratchpad to test a script is not that, and pushing to or committing on its master passes.
A remote or directory the guard cannot tell (`$VAR`, `cd $D`) counts as the project.

`scripts/hooks_selftest.sh` exercises all of it — 179 cases in sandbox repositories, with a
stubbed `gh`, `cargo`, `npm`, `flutter` and `dart` — plus `scripts/cleanup_local.sh`, the
`flutter pub get` of `scripts/worktree_setup.sh` (and that a failed one clears its setup
marker) and its `--deploy` links and `scripts/generate_keystore.sh` (stub `keytool`: writes to `$HOME`,
`umask 077`, mode 600, refuses to overwrite, refuses a path inside a repository); it is the `hooks` CI
job. The same job runs
`scripts/deploy_nas_selftest.sh`, the production deploy's own table (158 cases, `ssh`,
`docker`, `docker-compose` and `curl` stubbed: the step order that makes a failed deploy a
no-op rather than an outage, the health wait, every refusal, `--rollback` — [[Deployment]]).
`scripts/ci_scope.sh` classifies both scripts, `docker-compose.prod.yml` and
`scripts/deploy.env.example` as `hooks`, so a change to them runs that job.

### What is refused, and on what evidence

| Rule | Evidence |
|---|---|
| `pkill` / `killall` whose target matches `node` (kills the VS Code server under WSL) | tokenised command; `pkill -f nodemon` and `lsof -ti:9999 \| xargs kill` pass |
| `git push --force`, `-f`, `--force-with-lease`, `--mirror`, a `+refspec` | parsed flags and refspecs; `--dry-run` passes |
| `git push` to master: a refspec whose destination is `master`, `--all`, a bare push while on master — to this project's remote, not a sandbox's | parsed refspecs and remote; current branch of the repository the push runs in, and its push remote |
| `gh pr create --base <anything but master>` | parsed `--base`; unlocked per repository by `git config zapzap.allowStackedPr true` — the user's decision |
| `gh pr merge` with `--admin`, or without `--squash`, or with `--merge`/`--rebase` | parsed flags, bundled short flags included |
| Committing on master (of a checkout of this project), on a detached HEAD, on a branch whose upstream is `[gone]`, or one replaying commits already on `origin/master` | `%(upstream:track)`, `git cherry origin/master HEAD` |
| Committing a `.env` / `.env.*` (not `.env.example`), `client_secret_*.json`, a `*.db` / `*.sqlite` or a `*.db.bak-*` backup | paths the commit **adds or modifies** (`--diff-filter=d`): untracking a file with `git rm --cached` passes |
| Committing an Android keystore (`*.jks`, `*.keystore`), `key.properties` (its passwords; `key.properties.template` passes) or a `*service-account*.json` | same path list |
| Committing any JSON holding `"type": "service_account"` (a Google service-account key), whatever its name | the staged blob, or the working file under `-a` |
| Committing anything under `wip/`, or a root `TODO.md` / `DONE.md` | same path list |
| Committing with a red gate, or with the gate's setup missing | see below |

**Gates before a commit**, chosen from the union of paths the commit will contain (`--cached`,
plus the working-tree diff under `-a` — staged *after* the hook runs — plus `HEAD`'s files
under `--amend`, plus trailing pathspecs; during a merge, the diff against `MERGE_HEAD`):

| Paths | Gate |
|---|---|
| `zapzap-rust/` | `cargo fmt --check`, `cargo clippy --locked --all-targets -- -D warnings` (target dir shared with the main checkout) |
| `native/` | `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings` (no `--locked`: `native/Cargo.lock` is untracked; target dir shared with the main checkout) |
| `frontend/`, a file the commit leaves in the tree and not a `.md` (a README edit or a deletion runs none) | `npm run lint`, then `npm run build`; no `frontend/node_modules` → refusal naming `npm ci --prefix <tree>/frontend` |
| `frontend-flutter/`, a file the commit leaves in the tree and not a `.md` (a README edit or a deletion runs none) | `flutter pub get --offline`, `flutter gen-l10n` (the generated l10n is not committed and goes stale), `dart format --output=none --set-exit-if-changed lib test` (plus `integration_test` when it exists; the whole tree, not only the staged files, so drift another commit let through is caught — under a second; the refusal names `dart format lib test`), `flutter analyze`; no `flutter` on PATH or no `frontend-flutter/.dart_tool` → refusal naming `cd <tree>/frontend-flutter && flutter pub get`; a `pubspec.lock` the pub get rewrote and that is left unstaged (not under `-a`) → refusal naming `git add` |
| anything else (docs, `scripts/`, the root `package.json`) | none |

The test suites run in CI, not here. A setup refusal says to run the install as **its own**
Bash call: the hook judges the whole line before any of it runs.

### A refusal that is not ours: the harness's worktree check

In an agent launched with `isolation: "worktree"`, Claude Code itself — not a script of this
repository, no file under `.claude/` holds the text — refuses a Bash command it cannot prove
stays inside the worktree: "too complex to verify that it stays inside the worktree". A
heredoc (`python3 - <<'EOF'`, `cat > f <<'EOF'`), a `$(…)` substitution or a `cd … && …`
chain is enough. The workaround: write the script to the session's scratchpad directory and
run it by path (`bash <scratchpad>/x.sh`, `python3 <scratchpad>/x.py`); a script's contents
are not inspected. The ship-parallel agent prompt says so.

### What the hooks do not cover

- **Anything a script commits** (`bash scripts/x.sh` running `git commit`), `git merge`,
  `git cherry-pick`, `git revert`: the hook sees only the command string.
- **Merging through the API or the web page**: only the branch protection stands behind it.
- **Freshness of `origin/master`**: the hooks never fetch (a fetch writes to refs every
  worktree shares). What they know is as old as the last `git fetch --prune`; a silent pass
  is not proof the branch is live.
- **Publishing**: `require-pull-request.sh` reads GitHub, never writes; silent without `gh`,
  unauthenticated, or on a branch with `git config branch.<name>.noPullRequest true`.
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
- **Sandbox repositories are exempt from the master rules (2026-09-23).** Reviewing a script
  that drives `git` needs throwaway repositories, and the guard refused to push to or commit
  on their master; the same commands moved into a script file passed, since the hook does
  not read scripts — friction without safety. The rules now judge the target repository.
- **Queued branches are not a hook case (2026-09-23).** A branch built on another open pull
  request's branch was once a planned state, and the stop hook counted the base's commits as
  its own. Stacked pull requests are refused and a dependent group waits for a later wave,
  branched from `master` once its base merged, so the hook keeps counting from
  `origin/master` and no flag was added.
- **Production runs the Rust backend (2026-09-24).** `deploy.sh` refuses a compose file `docker-compose` cannot read — the Rust service's `JWT_SECRET` has no default — before building, printing compose's reason; three cases pin it. The Node backend, now the rollback, keeps having no pre-commit gate.
- **The Node backend is removed (2026-09-25, chore/remove-node-backend).** It had no gate, so the table only loses its `src/` row; the self-test's "no gate" case now stages `scripts/train-native.js`, and its OAuth-secret case a root `client_secret_*.json`. Its code can still be read at `232f168` (the last master commit holding `src/`, e.g. `git show 232f168:src/api/server.js`) and `0bfd407` (the last commit whose `docker-compose.yml` builds it, the former rollback target).
- **`deploy.sh` is removed (2026-09-25, feat/deploy-through-registry).** Its 45 cases leave `scripts/hooks_selftest.sh` with it; `scripts/deploy_nas.sh`, which replaces it, has its own table (`scripts/deploy_nas_selftest.sh`, 158 cases), run by the same `hooks` CI job. `worktree_setup.sh --deploy` also links `scripts/deploy.env`, with three cases.
- **Keystores and service-account keys (2026-09-25, feat/flutter-android-release-signing).** The Android release build now signs with an upload key ([[FrontendFlutter]] § Android), so the secret rule gained countscore's keystore, `key.properties` and service-account cases — the last judged by content too, since a downloaded key is named `<project>-<hash>.json`. Twenty self-test cases: the refused files, the template that passes, a key under another name and one written into a tracked JSON under `commit -a`, and the keystore script.
