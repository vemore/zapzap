---
name: ship-parallel
description: Implement a set of ZapZap wip/ entries in parallel — group them by theme, one pull request per theme, each built by a dedicated agent in its own git worktree; then bring each green pull request up to date, resolve conflicts, squash-merge it into master, deploy to the NAS, smoke-test production, close the entries and open follow-up fix pull requests. Use when the user lists several tasks to implement, asks to work in parallel, or asks to merge and deploy finished pull requests. Triggers: "implémente ces tâches", "attaque en parallèle", "lance les PR", "implement these", "work on these in parallel", "merge and deploy", "fusionne et déploie", "ship the todo".
---

# Shipping in parallel

One theme → one worktree → one agent → one pull request → squash-merged into `master` →
deployed. You are the **orchestrator**: you plan, launch, merge, deploy and verify. The agents
implement. The authorisation to merge and deploy is in `CLAUDE.md`; facts and the reasoning
behind each choice: `.llmwiki/ParallelDelivery.md`.

## 0. Where the orchestrator stands

- Work from the **main checkout, on `master`**, kept current: `git fetch --prune origin &&
  git merge --ff-only origin/master`. It is also where `wip/` lives (local, gitignored).
- If the main checkout is on another branch with work in it, it belongs to another session:
  do not switch it, ask the user.
- `session-start.sh` lists the existing worktrees and the branches whose remote is gone. A
  worktree whose pull request is still open is work in flight — resume it rather than start
  the same theme twice. Debris from a finished loop: `scripts/cleanup_local.sh` (§7) first.

## 1. Plan the pull requests

1. `git fetch --prune origin`, then `scripts/wip.sh list all` and read every entry the user
   named. A task not in `wip/` yet gets an entry first (`wip/README.md`); a `todo_nr/` entry
   that is not *ready* goes through `wip-refine` first.
2. Group by `Theme`, then **split or merge on the files each group will touch**: two groups
   editing the same route file, the same screen, or the database schema → one pull request,
   or two waves. A group that needs another's result → a later wave. Never a stacked pull
   request (the hook refuses `--base`). One pull request stays reviewable: one reason to
   revert, under the 1 500 counted lines of §3.1.
3. Order the merges: backend first, then frontend, then docs. A pull request touching
   `.claude/` merges **last in its wave** — the hooks in force are the main checkout's copy.
4. **Put each pull request in a lane** (`ParallelDelivery.md` § Execution lanes):
   - **A** standard.
   - **B** over 1 500 added-or-modified lines of code; or a failure that would be silent —
     the database schema or a migration, the scoring (`zapzap-rust/src/domain/`), the SSE
     event format both sides depend on; or a call site several features depend on.
   - **C** a diff touching authentication or secrets: `zapzap-rust/src/api/routes/auth.rs`,
     `zapzap-rust/src/api/middleware/`, `zapzap-rust/src/infrastructure/auth/`,
     `docker-compose.yml` / `zapzap-rust/docker-compose.yml` environment, `nginx/`.
   - **D** an experiment, on a `noPullRequest` branch, never merged as is.
   Lanes B and C need **acceptance criteria in the entry**. In doubt, the stricter lane.
5. Present the plan in **one** `AskUserQuestion` — per pull request: branch, entries, lane
   (and criteria for B/C), likely files, wave, merge order — and wait. The go-ahead covers
   the loop, merges and deploys included; it does not stand in for lane C's go-ahead in §3.

Four agents at a time at most: each worktree costs an `npm ci` and cargo builds.

## 2. Launch one agent per pull request

All agents of a wave in **one message**, each with `isolation: "worktree"`. The tool creates
the worktree under `.claude/worktrees/<name>` on a branch `worktree-<name>`; the agent moves
to a proper branch first. Fill in this prompt — do not shorten the rules:

```text
You implement one pull request of ZapZap, in the git worktree you start in.

Pull request: <type>/<topic> — <one-line goal>
Entries (local, read them by absolute path): <MAIN>/wip/todo/<file>.md ...
Lane: <A | B | C>. <B and C: another agent reviews this change before it merges; the
acceptance criteria below are what that review judges your tests against.>
Acceptance criteria (B and C): <one per line>
Files you will likely touch: <list>. Other agents work in parallel on: <PRs and files> —
stay out of those files; if you cannot, say so in your report.

Rules:
1. First: `git fetch --prune origin && git switch -c <type>/<topic> origin/master`, then
   `scripts/worktree_setup.sh` (--no-frontend or --no-rust when a side is untouched).
2. Read CLAUDE.md, .llmwiki/INDEX.md and the pages the change touches.
3. Implement, with tests. Update the wiki pages and README.md the change falsifies, in the
   same pull request.
4. wip/ is local to the main checkout (<MAIN>/wip) and never committed; you read it, you
   never write it. Do NOT move or close your entries — the orchestrator does after the
   merge. A problem you find but were not asked to fix goes, complete, under a
   `## New wip entries` heading of your final report, one block per entry in this format
   (<MAIN>/wip/README.md); the orchestrator writes it. Never fix it inline.
     ### todo_nr/YYYY-MM-DD-<slug>.md      (todo/ only if it blocks a release)
     # <What is wrong, as a statement>
     - **Noted:** YYYY-MM-DD — <while doing what>
     - **Theme:** <an existing tag: scripts/wip.sh themes all>
     - **Area:** backend | native | frontend | tooling | docs | ops
     - **Blocks release:** yes — <why> | no
     <The problem, with file paths and evidence.>
     **Fix:** <the proposed change.>
     **Acceptance:** <2 to 5 statements a test or a command can check.>
5. Working in parallel with other agents:
   - A browser check (Playwright MCP) happens in a tab you open (`browser_tabs` new) and
     only in it; close it when done. Never navigate, reload or read another tab: it is
     another agent's, with its tokens. The browser keeps no login between sessions
     (`--isolated`): sign in in your tab. Screenshots land in `.playwright-mcp/`
     (gitignored): never commit them, never delete that directory. If the MCP browser is
     unavailable, run a headless `chromium.launch()` script from your scratchpad subdirectory,
     requiring `<MAIN>/node_modules/playwright` (.llmwiki/ParallelDelivery.md § The shared
     browser).
   - Never rename a CI job's `name:` in `.github/workflows/ci.yml`: branch protection
     requires those names verbatim, and a renamed required job blocks every merge with all
     checks green. Say what a job grew to do in a step name or a comment.
   - A compound command (heredoc, `$(…)`, `cd … && …`) refused as "too complex to verify
     that it stays inside the worktree" is the harness's check, not a repository hook: write
     the script to your own subdirectory of the scratchpad, `<scratchpad>/<type>-<topic>/`
     (the branch name, `/` → `-`), and run it by path. Your PR body and commit messages go
     there too, never to a shared name at the scratchpad root: every agent of the session
     shares that scratchpad.
   - `gh pr edit` fails on this repo (gh 2.45 queries Projects classic). Edit a PR's title or
     body with `gh api -X PATCH repos/{owner}/{repo}/pulls/<n> -f title=… -F body=@<file>`.
6. Commit (the hook runs the gates in this worktree), `git push -u origin <type>/<topic>`,
   `gh pr create --base master` with a body saying what changed and why
   (`--body-file <scratchpad>/<type>-<topic>/pr.md`).
7. `gh pr checks <n> --watch` until every check is green or skipped (a job the scope job
   ruled out reports `skipping`, which counts as passing).
   Circuit breaker: after three fix attempts on the same failing check or test, stop — no
   fourth attempt, no loosened assertion, no skipped test. Report it as TEST_ISSUE,
   IMPL_ISSUE, DOC_ISSUE or UNCLEAR, with the check, the last error and the three attempts.
8. Never merge, never deploy, never force-push, never push to master.
9. Report briefly: PR URL and number, check state, files touched, schema changes, env vars
   or manual steps the deploy needs, the circuit-breaker class if any, then the
   `## New wip entries` heading ("none" when there are none).
   Lanes B and C: map each acceptance criterion to the test that covers it, by name.
```

`<MAIN>` is the main checkout's absolute path (`scripts/wip.sh path` minus `/wip`).

**After each hand-back**, before anything else with that pull request: write every block
under the agent's `## New wip entries` into `<MAIN>/wip/todo_nr/` (or `todo/`) as its own
file, as reported — the agent could not (`wip/` is outside its worktree). Then `scripts/wip.sh
check`. A reported entry is never dropped: it is the only copy.

A `SubagentStop` hook refuses to let an agent finish while its commits have no pull request
or its checks are red. On a circuit-breaker class: `TEST_ISSUE` → read the test against the
entry, correct the agent or treat as `IMPL_ISSUE`; `IMPL_ISSUE` → diagnose yourself, relaunch
with the diagnosis or narrow the PR; `DOC_ISSUE` → decide which side is true (ask the user if
it changes the entry); `UNCLEAR` → ask the user. Never relaunch the same prompt unchanged.

## 3. Merge, one pull request at a time

`master` requires an up-to-date branch, the required checks green or skipped, and a linear
history. So merges are serial. For each pull request, in the planned order:

1. `gh pr view <n> --json state,mergeable,mergeStateStatus,headRefName`, and read the diff
   (`gh pr diff <n>`) — you are the only reviewer. Then its size, the added or modified lines
   of code (docs, lock, generated and test files not counted):
   ```bash
   gh pr diff <n> | awk '
     /^diff --git / { p = $4; sub(/^b\//, "", p)
                      keep = (p !~ /\.md$|\.lock$|package-lock\.json$|^zapzap-rust\/tests\/|\.test\.jsx?$|^tests\//) }
     keep && /^\+/ && !/^\+\+\+/ { n++ }
     END { print n + 0 }'
   ```
   Above **1 500** it is lane B whatever the plan said, and does not merge without the
   user's go-ahead.
2. **Apply the lane.** A: go on. B and C: check each acceptance criterion maps to a test;
   launch a **fresh agent that did not write the change** with `/code-review high <n>`, the
   entries, their criteria and the calibration rules (`ParallelDelivery.md`); report **every**
   finding to the user with what you intend to do about it. C only: an explicit
   `AskUserQuestion` go-ahead for this merge, after the findings.
3. Bring it up to date: `gh api -X PUT repos/{owner}/{repo}/pulls/<n>/update-branch` (merges
   `master` into the branch on GitHub — no rebase, no force-push).
4. On a conflict, in that pull request's worktree: `git -C <wt> fetch origin && git -C <wt>
   merge origin/master`, fix, commit, push. `.llmwiki/*.md`: keep both facts and the later
   `Updated:`. `Cargo.lock` / `package-lock.json`: take master's, then `cargo update -w` /
   `npm install`. A real semantic clash between two themes: stop and tell the user.
5. `gh pr checks <n> --watch` on the updated head.
6. `gh pr merge <n> --squash --delete-branch`, then `git fetch --prune origin && git merge
   --ff-only origin/master` in the main checkout.
7. The next pull request is now behind `master`: back to step 3 for it.

## 4. Deploy what the merge changed

After **each** merge, so a regression points at one pull request:
`git diff --name-only <sha>^ <sha>` on the squash commit.

| Paths changed | Do |
|---|---|
| `zapzap-rust/`, `frontend/`, `frontend-flutter/`, `nginx/`, `docker-compose.yml`, `data/` | `deploy` skill — production runs the Rust backend (`.llmwiki/Deployment.md`) |
| `native/`, root `package*.json`, docs, `.claude/`, `.github/`, `scripts/` | nothing to deploy |

Then smoke-test production: `https://zapzap.ombivince.synology.me/api/health`, the frontend
loads, and the path the pull request changed, driven for real (Playwright). Record it.

## 5. Close the entries

In the main checkout, for each entry the merged pull request fixed:
`mv wip/todo/X.md wip/done/X.md`, then under the title
`**Status:** done (YYYY-MM-DD) — closed by #<n>. <one sentence>`. Partly done: rewrite it to
what is left and leave it open. Nothing to commit — `wip/` is local.

## 6. Follow-up fixes

A problem found after the deploy is a **new** pull request, never a commit on the merged
branch: a `wip/todo/` entry, one agent, §3–§5 again. A deploy that broke production is rolled
back first (`deploy` skill), then fixed.

## 7. Clean up and report

- Once **every agent has reported**: `scripts/cleanup_local.sh`, then `--apply`. Read the
  `keep` lines; an unmerged pull request or a dirty worktree is real — say so, never force it.
- `git worktree list` and `git branch -vv` then show only `master` and work in flight.
- Report: each pull request (URL, merged or not), each deploy and its smoke test, the entries
  created and closed, and what is left (`scripts/wip.sh list`).
