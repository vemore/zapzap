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
- An open `wip/todo/*-merged-not-deployed.md` holds merges an earlier session could not
  deploy (§4): when §1.5 finds the NAS reachable, deploy `master` and close it first.

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
   **And rate it complex, simple or bulk** — the lane rates the risk to production, the
   rating the difficulty, and it picks the model §2 launches (why: `ParallelDelivery.md`
   § Model routing):
   - **complex** → `implementer-complex` (Opus, effort high): a design choice is still open,
     several subsystems move together, the root cause is unknown, or the lane is B or C.
   - **simple** → `implementer-simple` (Sonnet): the entry's fix is explicit and local, and
     its acceptance is mechanical (a string, a rename, a documented one-file change).
   - **bulk** → Haiku, one agent per unit, in parallel: many independent, mechanical,
     well-specified units — the eight translated locales of `i18n-add-string` §1b, a sweep
     over files. The pull request is rated simple or complex for the rest of its work; the
     units are **yours** to fan out (§2) — a subagent has no `Agent` tool — and so is a
     translation's French and English master.
   - In doubt, complex: an under-rated change costs a rework, an over-rated one only tokens.
5. **Check that this session can deploy.** A claude.ai/code session has no route to the LAN,
   and the NAS or the registry can be down; §4 cannot run then. Read-only, a few seconds at
   most, over the two routes `scripts/deploy_nas.sh` takes — ssh to the NAS, plain HTTP to
   the registry (`/v2/` answers even unauthenticated) — from the main checkout, the only one
   with `scripts/deploy.env`:
   ```bash
   ( f=scripts/deploy.env
     [ -r "$f" ] || { echo "deploy: no $f in this checkout"; exit 1; }
     set -a; . "$f"; set +a
     ssh -o BatchMode=yes -o ConnectTimeout=5 "$NAS_SSH" true >/dev/null 2>&1 \
       || { echo "deploy: NAS unreachable over ssh"; exit 1; }
     curl -s -o /dev/null -m 5 "http://$REGISTRY/v2/" \
       || { echo "deploy: registry unreachable"; exit 1; }
     echo "deploy: reachable" )
   ```
   Anything but `deploy: reachable` is **the plan's first line**: "this session cannot
   deploy — merges will land *merged, not deployed* (§4)". The user then chooses between
   merging anyway and leaving the green pull requests to a session on the LAN.
6. Present the plan in **one** `AskUserQuestion` — the deploy check, then per pull request:
   branch, entries, lane (and criteria for B/C), rating (complex or simple, and bulk units if
   any), likely files, wave, merge order — and wait.
   The go-ahead covers the loop, merges and deploys included; it does not stand in for lane
   C's go-ahead in §3.

Four agents at a time at most: each worktree costs an `npm ci` and cargo builds.

## 2. Launch one agent per pull request

All agents of a wave in **one message**, each with `isolation: "worktree"` and the
**`subagent_type` its §1 rating picks**: `implementer-complex` or `implementer-simple`
(`.claude/agents/`). Pass no `model`: a per-call `model` overrides the definition's, and
effort comes only from the definition. If the session does not list the two (a session
started before `.claude/agents/` first existed needs a restart), launch `general-purpose`
with `model: "opus"` or `"sonnet"` instead, and say so in the report. The tool creates the
worktree under `.claude/worktrees/<name>` on a branch `worktree-<name>`; the agent moves to
a proper branch first.

**Bulk units** (§1) are launched by you, never by an implementer: add to its prompt that it
stops **before its first commit** and reports what is left; then write the master in its
worktree and launch one `general-purpose` agent per unit with `model: "haiku"`, all in one
message, **no** `isolation`, each given the worktree's absolute path and the one file it
owns, no commit. Review what comes back, then `SendMessage` the implementer to commit and
carry on (translations: `i18n-add-string` §1b). A pull request that is nothing but bulk you
hold yourself, in a worktree of your own.

Fill in this prompt — do not shorten the rules:

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
     unavailable, run a headless `chromium.launch()` script from your scratch directory
     (below), requiring `<MAIN>/node_modules/playwright` (.llmwiki/ParallelDelivery.md § The shared
     browser).
   - Never rename a CI job's `name:` in `.github/workflows/ci.yml`: branch protection
     requires those names verbatim, and a renamed required job blocks every merge with all
     checks green. Say what a job grew to do in a step name or a comment.
   - A compound command (heredoc, `$(…)`, `cd … && …`) refused as "too complex to verify
     that it stays inside the worktree" is the harness's check, not a repository hook: write
     the script to your own scratch directory, `/tmp/zapzap-<type>-<topic>/` (the branch
     name, `/` → `-`; `mkdir -p` it first), and run it by path. Your PR body and commit
     messages go there too, never to a shared name: every agent shares `/tmp`. Not the
     session scratchpad under `~/.claude/jobs/`: the harness refuses a Write there from a
     worktree-isolated agent.
   - `gh pr edit` fails on this repo (gh 2.45 queries Projects classic). Edit a PR's title or
     body with `gh api -X PATCH repos/{owner}/{repo}/pulls/<n> -f title=… -F body=@<file>`.
6. Commit (the hook runs the gates in this worktree), `git push -u origin <type>/<topic>`,
   `gh pr create --base master` with a body saying what changed and why
   (`--body-file /tmp/zapzap-<type>-<topic>/pr.md`).
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
   of code (docs, lock, generated and test files not counted — Rust, JS and Flutter tests
   alike: `frontend-flutter/test/`, `frontend-flutter/integration_test/`, `*_test.dart` —
   nor the translated ARB files, every `frontend-flutter/lib/l10n/app_*.arb` but
   `app_fr.arb` and `app_en.arb`):
   ```bash
   gh pr diff <n> | awk '
     /^diff --git / { p = $4; sub(/^b\//, "", p)
                      keep = (p !~ /\.md$|\.lock$|package-lock\.json$|^zapzap-rust\/tests\/|\.test\.jsx?$|^tests\/|^frontend-flutter\/(test|integration_test)\/|_test\.dart$/) \
                          && (p !~ /^frontend-flutter\/lib\/l10n\/app_.*\.arb$/ || p ~ /\/app_(fr|en)\.arb$/) }
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
| `zapzap-rust/`, `frontend/`, `frontend-flutter/`, `nginx/`, `docker-compose.prod.yml` | `deploy` skill (`scripts/deploy_nas.sh`, run from the main checkout on the merged `master`) — production runs the Rust backend (`.llmwiki/Deployment.md`) |
| `native/`, `data/` (the Rust backend reads none of its tracked files), root `package*.json`, `docker-compose.yml` (local and CI only), docs, `.claude/`, `.github/`, `scripts/` | nothing to deploy |

Then smoke-test production: `https://zapzap.ombivince.synology.me/api/health`, the frontend
loads, and the path the pull request changed, driven for real (Playwright). Record it.

**When the deploy cannot run** — §1.5 said so, or the `deploy` skill cannot reach the NAS or
the registry — a merge whose paths call for a deploy is **merged, not deployed**, never a
silent success. A deploy that ran and broke production is not this case: that is a rollback.
- Say "merged, not deployed" for that pull request, then and in §7's report.
- Write **one** entry for the loop, `wip/todo/<date>-merged-not-deployed.md` (Theme
  `deployment`, Blocks release: yes — production runs older code than `master`), or add to
  the one already open: one line per squash sha, with its pull request and the paths from
  the table above that call for the deploy. Its fix: deploy `origin/master` from the main
  checkout (one deploy covers every sha listed), smoke-test each listed pull request's path,
  and close it (§5) naming the deployed sha — whichever session next passes §1.5 does so
  before merging anything new. `wip/` is local: no pull request carries it.

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
- Report: each pull request (URL, merged or not, "merged, not deployed" when §4 could not
  run), each deploy and its smoke test, the entries created and closed, and what is left
  (`scripts/wip.sh list`).
- And the **delivery metrics** of the last seven days, `scripts/delivery_metrics.sh $(date -d
  '7 days ago' +%F)`, next to the baseline in `ParallelDelivery.md` § Measuring delivery.
