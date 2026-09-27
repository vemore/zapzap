# AgentEvals

> Scope: the local eval harness (`evals/`) that checks agents still do the job after the
> agent configuration changes — what a case is, how a run is isolated, how to run a case
> for real, when, and what it costs.
> Related: [[Hooks]] · [[Documentation]] · [[ParallelDelivery]] · [[Testing]]
> Updated: 2026-09-27

## Facts

### What it checks, and what it does not

The hooks are tested as scripts (`scripts/hooks_selftest.sh`, [[Hooks]]); that says nothing
about whether an agent given a changed `CLAUDE.md`, skill, hook or wiki page still does the
task right. An eval replays a past task with `claude -p` in a throwaway worktree and judges
the outcome with a deterministic script: a skill reworded until it stops triggering, or a
pruned rule that was carrying weight, shows up as a failing case instead of a later pull
request going wrong. A case judges the *outcome* — files, commits, and the agent's final
report, which is where an agent in a worktree hands back a `## New wip entries` section —
never the transcript.

### The cases

Listed by `evals/run.sh --list`. Two kinds:

- **Cross-cutting** — `evals/cases/<name>/`: `prompt.md` (the task), `check.sh`,
  `case.env` (the `wip/done/` source, `SETUP=none|rust|all` for what
  `scripts/worktree_setup.sh` prepares so the commit hook's gates can run, and whether an
  untouched tree should pass), an optional `setup.sh` that plants the problem, and
  `good.sh` / `bad.sh`, hand-made right and wrong outcomes. Today, from the rules of
  `CLAUDE.md`:
  - `out-of-scope-finding` — asked to raise the Ollama timeout to 90 s, next to a planted
    LAN address as the default Ollama URL: the timeout changed, the planted default left
    alone, nothing written under `wip/`, and the final report carries it under
    `## New wip entries` as a complete `### todo_nr/<date>-<slug>.md` entry. `SETUP=rust`.
  - `rule-change-golden-hand-size` — a Golden Score hand becomes 4-8 cards: `GAME_RULES.md`,
    `hand_size_bounds` and a Rust test asserting `(4, 8)`, `README.md`'s copy of the rules
    and [[GameRules]] all changed. `SETUP=all` (the clients may change too).
  - `docs-only-wiki-fact` — a planted stale fact in [[Bots]] (the trigger-bot route "has no
    party-membership check"): fixed from the code (`require_party_member`), the page's
    `Updated:` and its `INDEX.md` row dated the day of the change, `README.md` and the code
    untouched. `SETUP=none`.
- **Per skill** — `.claude/skills/<skill>/evals/evals.json` in skill-creator's format
  (`skill_name`, `evals[]` with `id`, `prompt`, `expected_output`, `files`, `expectations`);
  the script form of eval `<id>` is `.claude/skills/<skill>/evals/<id>/check.sh` (+ `good.sh`,
  `bad.sh`, an optional `case.env`), and `run.sh` names it `<skill>/<id>`. None yet.

A check is `check.sh <worktree> [<base>]`: read-only, offline, one line per assertion, exit
0 or 1; `<base>` defaults to the `eval fixture:` commit, so it can be rerun by hand on a
kept worktree. It reads the final report from `report.md` next to the worktree (`EV_REPORT`
overrides it). Shared helpers: `evals/lib.sh`. The work date is the last commit's, so a
rerun on a later day gives the same verdict.

### How a run is isolated

`evals/run.sh [case...]`, per case: a worktree under `$TMPDIR` off `--ref` (default
`origin/master`) on a branch `eval/<case>-<stamp>` with `noPullRequest` set (so the Stop
hook does not ask for a pull request) and no upstream; `setup.sh` and an `eval fixture:`
commit; `scripts/worktree_setup.sh` per `SETUP`; then `claude -p` with `evals/preamble.md`
+ the prompt, `--permission-mode dontAsk`, `--setting-sources project` (the project's
configuration, hooks included, is what is under test, not the user's), a closed
`--allowedTools` list (read, edit, `git add/mv/rm/commit`, `scripts/wip.sh list|themes`,
`cargo fmt|clippy|test --manifest-path zapzap-rust/Cargo.toml`, `npm --prefix frontend run`,
`dart format`) and a `--disallowedTools` list (`git push`, `gh`, `git
remote/config/fetch/switch/worktree/reset`, `scripts/deploy_nas.sh`, network tools,
sub-agents). As a second fence the agent's environment has no GitHub credentials and a
`remote.origin.pushurl` pointing at a missing directory; `run.sh` fails a case whose branch
gained an upstream, or during which the main checkout's `wip/` changed. The agent's final
message (the JSON result's `result`) is saved as the report. Worktrees and branches are
removed on exit (`--keep` keeps them); logs, the agent's JSON, the report and the check
output go to `evals/runs/<stamp>/` (gitignored by `evals/.gitignore`). It runs on the user's
own Claude login: no API key, no secret, and no agent run in CI.

Case files are read from the checkout that runs `run.sh`; the tree the agent works in is
`--ref`. To evaluate a branch's own configuration before it merges, commit it and pass
`--ref HEAD`.

### Running a case for real

From an up-to-date main checkout (`git fetch --prune origin` first; the default `--ref` is
`origin/master`), with the `claude` CLI logged in:

```bash
evals/run.sh docs-only-wiki-fact
evals/run.sh out-of-scope-finding
evals/run.sh rule-change-golden-hand-size
evals/run.sh                                   # every case
evals/run.sh --ref HEAD <case>                 # a branch's own configuration
```

Each prints the agent's turns, time and cost, then the check's verdict; exit 0 when every
case passed. `--model` picks the model ([[ParallelDelivery]] on routing by task), `--budget`
caps each case (default 3 USD, `--max-budget-usd`) and `--timeout` its wall clock (45 min).

**Expected cost** (not measured here yet; countscore's harness, the same design, measured
about 0.25-0.35 USD per docs-sized case on the default model): `docs-only-wiki-fact` about
0.3 USD; `out-of-scope-finding` about 0.4 USD plus the cargo warm-up of the setup and the
commit hook's clippy (minutes, no money); `rule-change-golden-hand-size` the most, about
1-2 USD — the rule is restated in the Rust backend, `GAME_RULES.md`, `README.md`, several
wiki pages, the React selector and the ten ARB files, and the setup is a full
`scripts/worktree_setup.sh`. The 3 USD budget caps any runaway. No real run is recorded yet
(§ Decisions & History).

### When to run it

- **After changing `CLAUDE.md`, `.claude/**` or `.llmwiki/**`** — the cases that touch
  what changed at least, from the branch with `--ref HEAD`, before the pull request merges.
- **In a pruning pass** of the agent configuration: the whole suite on `origin/master`, and
  again with `--ref HEAD` on the pruning branch — a case that passes before and fails after
  is evidence that the removed rule was carrying weight.
- **After editing a check, a fixture or `evals/lib.sh`:** `evals/selftest.sh`, which needs
  no agent and costs nothing — every check must fail the untouched tree (or pass it, for a
  case with `UNTOUCHED=pass`), pass `good.sh` and fail `bad.sh`. About 5 s for the three
  cases. It runs in CI, as the "Agent evals self-test" step of the hooks job, when `evals/`
  changes (`scripts/ci_scope.sh`) and on every push to `master` — where a change that
  breaks a case's `setup.sh` preconditions (the planted line, the rule as `master` states
  it) shows up.

`--dry-run` builds each worktree and fixture, prints the `claude` command without running
it, checks the untouched tree and cleans up.

### Adding a case

Every production incident or `wip/done/` entry whose right outcome a script can decide is a
candidate. Name its source in `case.env` (or `expected_output`), plant the problem in
`setup.sh` rather than depend on a state `master` will leave (or assert the state there, so
the case fails loudly the day it goes), and write `good.sh` and `bad.sh` before trusting the
check: `selftest.sh` must pass.

## Decisions & History

- **Ported from countscore (2026-09-27, chore/agent-evals).** From
  `wip/todo/2026-09-27-no-evals-for-the-agent-configuration.md`, after countscore's
  `evals/` (its #233). Adapted: `origin/master`; `SETUP=none|rust|all` for
  `scripts/worktree_setup.sh`, since the commit hook here gates Rust, React and Flutter;
  the tool list gains the cargo and npm checks; and the final report became part of the
  outcome, because a zapzap agent in a worktree never writes `wip/` (decided 2026-09-23,
  `wip/done/2026-09-22-worktree-agents-cannot-write-wip.md`) — countscore's agents commit
  their entries. `run.sh` also watches the main checkout's `wip/`, which an agent could
  reach by absolute path.
- **No real run in the porting pull request (user, 2026-09-27).** A real run costs money
  and needs the user's login; the first runs, one per case, happen after the merge, in the
  main checkout, and are recorded here (cost, verdict).
- **Self-test in CI, agents not (2026-09-27).** `evals/selftest.sh` needs no agent, no
  network and no secret, and takes seconds: it is a step of the hooks job (a new job would
  need a new required check). The real runs stay local, as countscore decided (no API key in
  the repository secrets).
- **Planted fixtures.** Each case plants its problem (`setup.sh`) on the throwaway branch
  instead of pointing at a bug `master` still has: the bugs of `wip/done/` are fixed on
  `master`, and a case that depended on one would stop meaning anything the day it was
  fixed.
