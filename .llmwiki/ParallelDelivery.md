# ParallelDelivery

> Scope: how changes reach production — worktrees, one pull request per theme, lanes by
> risk, the model per pull request, serial squash merges, deploy after each merge, local
> cleanup, and `wip/`.
> Procedure: the `ship-parallel` skill. Related: [[Hooks]] · [[Deployment]] · [[Testing]]
> Updated: 2026-09-28

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

- The Playwright MCP server is declared in the committed `.mcp.json` (project scope) as
  `npx @playwright/mcp@latest --isolated`. `--isolated` keeps the browser profile in memory
  (`@playwright/mcp` 0.0.82 `--help`), so each Claude Code session's server gets its own
  browser: a second session no longer fails with "Browser is already in use for
  …/mcp-chrome-…, use --isolated". The cost: no login, cookie or localStorage survives
  from one run to the next — sign in within the check. Claude Code asks once to approve a
  project-scope server, and a same-name server in the user's local scope (`~/.claude.json`)
  takes precedence over it.
- Within one session it is still **one browser for every agent**: a parallel
  agent's reload lands on whichever page is current, and every tab shares localStorage and
  tokens. So each agent opens its own tab (`browser_tabs` new), works only in it and closes
  it (ship-parallel agent prompt); a check that needs a clean origin is serialised.
- **When the MCP browser is unavailable**, the fallback is a headless script, run by path
  from the agent's scratch directory: `require('<MAIN>/node_modules/playwright')`
  (the only devDependency of the root `package.json`, installed by `npm ci` at the root of
  the main checkout; browsers in `~/.cache/ms-playwright`), then
  `chromium.launch()`, `browser.newPage({ viewport })`, `page.goto(url)`,
  `page.screenshot({ path })`, `browser.close()`. It shares nothing with any other agent.
- The server writes screenshots, console logs and network dumps to `.playwright-mcp/` in the
  checkout it runs from. The directory is gitignored and nothing in it is tracked; it is
  debris, never committed, and not an agent's to delete while others run.
- **`/tmp` is shared too**: an agent writes its scripts, PR body and commit messages under
  its own scratch directory, `/tmp/zapzap-<branch-slug>/` (the branch name, `/` → `-`;
  `mkdir -p` first), never at a shared name. Not the session scratchpad under
  `~/.claude/jobs/`, which every agent of a session shares and whose Write the harness
  refuses to a worktree-isolated agent.
- **`gh pr edit` fails** here: gh 2.45.0 still queries `projectCards` (Projects classic),
  which GitHub removed. A PR's title or body is edited with `gh api -X PATCH
  repos/{owner}/{repo}/pulls/<n> -f title=… -F body=@<file>`.

### Lanes — chosen at planning time, from what a change will touch

| Lane | What falls in it | Before merging |
|---|---|---|
| **A** | everything else | checks green or skipped, the orchestrator reads the diff |
| **B** | > 1 500 added-or-modified lines of code; a silent failure mode (schema, migration, scoring in `zapzap-rust/src/domain/`, the SSE event format); a call site many features use | A + acceptance criteria in the entry + `/code-review high` by an agent that did not write it, every finding reported to the user |
| **C** | authentication and secrets: `zapzap-rust/src/api/routes/auth.rs`, `zapzap-rust/src/api/middleware/`, `zapzap-rust/src/infrastructure/auth/`, compose environment, `nginx/` | B + an explicit go-ahead from the user for that merge |
| **D** | an experiment | a `noPullRequest` branch, never merged; what it taught becomes an entry |

The 1 500 lines are counted on the pull request's diff (`ship-parallel` §3.1): the `+` lines
of the kept files, so added or modified, never deleted. Not counted: Markdown, lock files,
the tests — `zapzap-rust/tests/`, `tests/`, `*.test.js(x)`, `frontend-flutter/test/`,
`frontend-flutter/integration_test/`, `*_test.dart` — and the translated ARB files (every
`frontend-flutter/lib/l10n/app_*.arb` but `app_fr.arb` and `app_en.arb`).

A change confined to `frontend-flutter/` is lane **A** unless it meets a B criterion (its
size, most often). The PWA ships under `/app/` since #36 ([[Deployment]]), so its merge is
deployed like any other (`ship-parallel` §4); the proxy does not depend on it, so a broken
bundle takes down `/app/` and not the site. A change that also touches the backend, `nginx/`
or the compose files is judged on those. Since 2026-09-24 the backend a merge deploys is
`zapzap-rust/` ([[Deployment]]).

The reviewing agent gets these rules: verify each finding against the PR head; a wiki page
or README the change makes false is at least Medium; read a page's `Decisions & History`
before calling something redundant; judge the tests against the entry's acceptance
criteria, not coverage.

### Model routing — the rating picks the model

The lane rates the **risk to production**; a second rating, made at the same moment
(`ship-parallel` §1) and shown in the same plan, rates the **difficulty**, and picks the model
the implementing agent runs on. Without it every agent inherits the orchestrator's model and
effort, and a string rename costs what a scoring change costs.

| Rating | When | Launched as (`ship-parallel` §2) |
|---|---|---|
| **complex** | A design choice is open, several subsystems move together, the root cause is unknown, or the lane is B or C. **In doubt, complex** | `subagent_type: "implementer-complex"` — `.claude/agents/implementer-complex.md`, `model: opus`, `effort: high` |
| **simple** | The entry's fix is explicit and local, and its acceptance is mechanical | `subagent_type: "implementer-simple"` — `.claude/agents/implementer-simple.md`, `model: sonnet`, effort inherited |
| **bulk** | Many independent, mechanical, well-specified units — the eight translated locales of a translation, a sweep over files | One `general-purpose` agent per unit, `model: "haiku"`, in parallel, launched by the orchestrator; the French and English master is the orchestrator's (`i18n-add-string` §1b) |

- **Effort needs a definition.** The `Agent` tool takes a per-call `model`, but `effort` comes
  only from an agent definition's frontmatter (`low` … `max`, Claude Code's sub-agents
  reference) — hence the two files. A per-call `model` overrides the definition's, so §2
  passes none with them.
- **The definitions hold no procedure.** Their body only frames the rating (understand
  first; or stop and ask for a re-rate); the §2 prompt, passed in full, stays the one
  specification, and its rules override the body.
- **Bulk is the orchestrator's, not an implementer's**: a subagent has no `Agent` tool, and
  the commit hook refuses an ARB key missing from a locale, so nothing commits between the
  master and the units. An implementer whose pull request has bulk units stops before its
  first commit; the orchestrator finishes them in its worktree and resumes it.
- **Loading.** Claude Code watches `.claude/agents/` and picks up an edited definition
  without a restart, but a session started before the directory first existed does not see
  it; §2 then falls back to `general-purpose` with `model: "opus"` or `"sonnet"` (no effort).
- The hooks key on the working directory, never on the agent type: `SubagentStop`
  ([[Hooks]]) judges the two implementers exactly as it judged `general-purpose` ones.
- **Checking the thresholds**: `scripts/agent_metrics.py --by agent,branch` gives the
  weighted tokens and active time per `implementer-*` type and pull request, and
  `scripts/delivery_metrics.sh` the rework per change — an over-reworked `simple` or a cheap,
  never-reworked `complex` moves the thresholds or the models. The weights are by price
  class, not by model: an Opus token costs more than a Sonnet one of the same class.

### Merged, not deployed

Only a session on the LAN deploys: `scripts/deploy_nas.sh` needs ssh to the NAS and the
registry `192.168.1.25:5050`, and `scripts/deploy.env` exists only in the main checkout. A
claude.ai/code session, or any session while the NAS is down, can still squash-merge. So
`ship-parallel` §1.5 probes both routes, read-only and with 5-second timeouts, and a failed
probe heads the plan. A merge that needed a deploy and did not get one is reported
**merged, not deployed** and listed, one line per squash sha, in a single
`wip/todo/<date>-merged-not-deployed.md` (Blocks release: yes); the next session that passes
the probe deploys `master` and closes it before merging anything new (§0, §4).

### `wip/` — local work tracking

`wip/` is gitignored and exists only in the main checkout; `scripts/wip.sh` finds it from
any worktree (`wip.sh path`). Format and lifecycle: `docs/wip-README.md` (copied to
`wip/README.md` by `wip.sh init`). An agent in a worktree reads entries by absolute path
but never writes them: it lists each new entry, complete, under a `## New wip entries`
heading of its final report, and the orchestrator writes them to `todo_nr/` after the
hand-back (`ship-parallel` §2). The orchestrator closes entries after the merge (§5). `wip-refine` decides what
moves from `todo_nr/` to `todo/` (12 per session, sessions on disjoint `Area`s: its §5).

### Measuring delivery and its cost

Two local scripts, ported from countscore, no tracking of their own; each documents its
definitions in its header. `scripts/delivery_metrics.sh [since [until]]` — outcomes from git
and `gh` on `origin/master`: `fix:` share, **rework rate** (a change followed within 48 h by
a `fix:` on one of its files; the §3.1 size exclusion list applied, so the wiki, `*.md`,
tests, locks and `wip/` never count), deployments and **change failure rate** (derived from
the `ship-parallel` §4 paths), first-run-green share, size per change, `wip/` ages (the main
checkout's). `scripts/agent_metrics.py` — cost, from the transcripts in
`~/.claude/projects/-home-vemore-workspace-zapzap*/`: tokens raw and weighted by price class,
active time, per session, branch, skill, agent, tool, file and hook; names and numbers only,
never content. `ship-parallel` §7's report prints the first; the pruning pass before each release
(`release-android` §3b) reads both against the baseline below and records new figures. DORA counts rework as unplanned
deployments fixing a production issue; this file-level proxy needs no incident log.

Baseline, measured 2026-09-27 on `origin/master` at `232fec3` (until exclusive; nothing
landed 09-14..09-21 — the history on `master` resumes on 09-22 with #21):

| Window | Changes | `fix:` | Rework | Deploys | CFR | 1st-run green | Size p50 / p90 / max |
|---|---|---|---|---|---|---|---|
| 2026-09-14..09-25 | 75 | 25 (33.3 %) | 69.3 % | 58 | 70.7 % | 94.8 % | 172 / 1164 / 2606 |
| 2026-09-25..09-28 | 46 | 6 (13.0 %) | 15.2 % | 24 | 16.7 % | 93.2 % | 61 / 1173 / 1639 |

The second window is young: a change of 09-27 has not had its 48 h yet, so its rework and
CFR are floors. `wip/` on 2026-09-27: `todo` 8 open (max 2 d), `todo_nr` 44 (median 2 d, max
5 d); 171 entries closed since 09-14, median age at close 0 d, max 4 d.

Cost, `--since 2026-09-14` (35 sessions, 13 587 model calls, 460 MB of transcripts): 2.0 G
tokens raw, 300 M weighted; 124 h of agent time active, 46 h waiting on the user.
- **Cache reads are 65 % of the weighted cost**, cache writes 31 %, output 4 %. Subagents
  (`general-purpose`) hold 70 % of it, the main agent 28 %.
- **By skill:** `ship-parallel` 35 %, `deploy` 16 %, `code-review` 4 %; 41 % under no skill.
- **Time:** `sleep` is 17.6 % of tool time and waiting on CI (`gh pr checks`) 15.0 %; hooks
  that leave a record total about 12 min.

Pruning pass for 1.0.2, measured 2026-09-28 on `origin/master` at `6e02fc8`, since the
1.0.1+2 tag's date (the window starts 09-27 00:00, so it overlaps the baseline's second
window, and its changes of 09-28 have not had their 48 h — rework and CFR are floors):

| Window | Changes | `fix:` | Rework | Deploys | CFR | 1st-run green | Size p50 / p90 / max |
|---|---|---|---|---|---|---|---|
| 2026-09-27..09-29 | 47 | 18 (38.3 %) | 40.4 % | 26 | 61.5 % | 91.5 % | 54 / 831 / 1181 |

`wip/` on 2026-09-28: `todo` 1 open (max 1 d), `todo_nr` 62 (median 1 d, max 6 d); 62
closed in the window, median age at close 1 d, max 5 d.

Cost, `--since 2026-09-27` (11 sessions, 3 947 model calls, 111 MB of transcripts): 511 M
tokens raw, 79 M weighted; 36.2 h active, 8.4 h waiting on the user.
- Cache reads 62 %, cache writes 34 %, output 4 %. `implementer-complex` 36 %,
  `general-purpose` 35 %, main 22 %, `implementer-simple` 7 %.
- **By skill:** `ship-parallel` 44 %, `deploy` 16 %, `code-review` 5 %, `wip-refine` 3 %;
  31 % under no skill.
- **Time:** `gh pr checks` 26.1 % of tool time, `sleep` 17.0 %; hooks that leave a record
  about 4 min.

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
- **A Flutter merge is deployed (2026-09-24).** The lane rule said the client was not
  deployed, so a merge reached no user; that stopped being true with #36, and #62–#64 were
  deployed through the `deploy` skill while the rule still said otherwise.
- **The Playwright MCP server runs `--isolated`, from a committed `.mcp.json` (2026-09-25).**
  Declared in the user's local scope with no flag, it kept one on-disk profile, and a
  second session's server was refused it ("Browser is already in use", #78, #98); agents
  fell back to headless Chromium. Isolated trades the persisted login for that. The
  per-branch scratchpad subdirectory and the `gh api` PR edit came the same day, after an
  agent overwrote another's `pr.md` (#71) and `gh pr edit` failed on #68.
- **Flutter tests left out of the size count (2026-09-27).** The filter already dropped Rust
  and JS tests but not `frontend-flutter/test/`: #133 counted 1 877 lines, 696 of them
  `*_test.dart`, and crossed into lane B on its tests alone; without them it counts 1 181.
- **The scratch directory moved to `/tmp/zapzap-<branch-slug>/` (2026-09-27).** The prompt
  named a subdirectory of the session scratchpad, `~/.claude/jobs/<job>/tmp/`; the harness
  refused a Write there from an agent launched with `isolation: "worktree"` (#138), though
  Bash could write it. The same session's five isolated agents then wrote their PR bodies,
  commit messages and scripts under `/tmp/zapzap-<type>-<topic>/` without a refusal. A
  gitignored folder inside the worktree was the alternative; `/tmp` needs no ignore rule
  and cannot be committed by mistake.
- **"Merged, not deployed" is tracked (2026-09-27)**, ported from countscore, where
  #212–#216 sat merged and undeployed for days with no trace: nothing in §4 covered a session
  that could merge but not reach the NAS.
- **Model routing by a rating made at planning time (2026-09-27)**, ported from countscore
  (#229). Every implementer inherited the orchestrator's model and effort. Routing by task
  envelope is current practice (Haiku for volume, Sonnet for execution, Opus for
  judgement); here the orchestrator rates each pull request at planning time and shows the
  rating to the user, rather than letting a router infer it per call — the rating is
  reviewable, and it is made where the lane already is. Two project agent definitions
  rather than a per-call `model`, because effort can only be set in a definition. "In
  doubt, complex", like "in doubt, the stricter lane": a rework costs more than the tokens.
- **Squash, update by merging `master` in** (`gh api -X PUT .../update-branch`): linear history
  without force-pushes, which would destroy an agent's commits in its worktree.
- **A `zapzap-rust/` merge is deployed, a `src/` one is not (2026-09-24).** Production switched to the Rust backend; the `ship-parallel` §4 table follows, and the Node backend stays gated in CI as the rollback.
- **The Node backend is removed (2026-09-25, chore/remove-node-backend).** A `src/` merge no longer exists, and the root `package.json` now holds only Playwright, for the headless browser fallback. Its code can still be read at `232f168` (the last master commit holding `src/`, e.g. `git show 232f168:src/api/server.js`) and `0bfd407` (the last commit whose `docker-compose.yml` builds it, the former rollback target).
