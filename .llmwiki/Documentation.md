# Documentation

> Scope: which documents a change implicates, the wiki conventions and their lint pass
> (`scripts/wiki_lint.sh`), and the `CLAUDE.md` budget. No hook enforces these: they need
> judgement ([[Hooks]]).
> Related: [[ParallelDelivery]] · [[Hooks]] · [[Testing]]
> Updated: 2026-09-27

## Facts

### The wiki (`.llmwiki/`)

The conventions — one owner per fact, changing a fact is an ingest, answers compound, status
blocks, budgets — are `INDEX.md` § Conventions, which owns them; the lint pass that checks
them is below.

### `README.md`

It is what a newcomer reads before running anything. A change touching one of these
implicates it:

| What you changed | What to check in `README.md` |
|---|---|
| A step needed to build or run a fresh clone | Getting started — a missing step is a defect |
| A toolchain version (`rust-toolchain.toml`, Node) or a dependency added or dropped | Tech stack, prerequisites |
| A new top-level directory | Project structure |
| A CI job | Continuous integration |
| Which backend production runs, or how it is deployed | Deployment |
| A feature a player would notice | Features |

Verify against the source, never against the old README. If the change falsifies nothing
there, leave it alone.

### `GAME_RULES.md`

The rules reference. A change to scoring, combinations, ZapZap eligibility or the golden
score updates it in the same pull request, and [[GameRules]] points at where the code
implements each rule. The Flutter app's rules sheet summarises it for players (the `rules*`
strings of the ten ARB files): the same change updates them.

### The `CLAUDE.md` budget

At most **120 lines**: what the project is, "read the wiki first", the non-negotiables, each
workflow rule in one line with a pointer, the commands, Git. Anything longer moves to the
page that owns it. When a rule becomes a hook, it leaves `CLAUDE.md` for [[Hooks]].

### Wiki lint

The wiki is kept current by each change (the ingest rules in `INDEX.md` § Conventions) and
checked as a whole by a lint pass, run by hand — before a release, or when a `wip-refine`
pass finds the wiki drifting. The pass proposes; the fixes are `wip/` entries and their own
pull requests.

Mechanical, run by `scripts/wiki_lint.sh [wiki-dir]` — a report, not a gate: it prints each
finding with its page (and line, where it has one) and exits 1 when there is any, which the
real wiki does, so only its self-test (`scripts/wiki_lint_selftest.sh`, a fixture wiki with a
known answer) runs in CI, in the `hooks` job ([[Testing]]):

- **Dead references:** a backticked repository path under a top-level directory that no
  longer exists and is not gitignored (`scripts/lib/dead_paths.sh`, which `scripts/wip.sh
  refine` shares for `wip/` entries). A placeholder (`<Name>`, `*`, `{…}`) is skipped.
- **Dangling links:** a `[[Link]]` naming a page `.llmwiki/<Name>.md` does not have; one
  touching a backtick is a placeholder and skipped.
- **Dates:** an `INDEX.md` row whose date differs from its page's `> Updated:` line.
- **Budgets:** a page over 400 lines; an `INDEX.md` row summary over 25 words.
- **Status blocks:** every `> **Status: Outdated**` and `> **Status: Contradicted**` block,
  unfiltered — whether one is old enough to fold back into the fact, with the why moved to
  `## Decisions & History`, still wants a person.

Mechanical, still by hand:

- A `file:line` reference past the end of the file.
- **Orphans:** a page no other page links to and `INDEX.md` does not list; a dangling
  `[[Link]]` named by several pages is a page to write, not just a finding to clear.
- A page whose `Updated:` is older than the last commit to the sources it cites.

Judgement:

- **Contradictions:** the same fact stated differently on two pages — keep it on its owner,
  link from the other.
- **Rebuilt answers:** a synthesis a pull request body or a `wip/done/` entry carries that no
  page does.

## Decisions & History

- **Budget and wiki ported from countscore (2026-09-22).** The old `CLAUDE.md` (≈170 lines)
  mixed durable facts, deploy commands and rules, and was wrong on the frontend (vanilla JS)
  and on which backend is current. Facts moved to pages written from the code; the deploy
  recipe moved to the `deploy` skill; the "never run" list became a hook.
- **Karpathy's LLM Wiki pattern, ported from countscore (2026-09-27, docs/wiki-conventions-lint).**
  countscore compared its wiki with the idea file
  (gist.github.com/karpathy/442a6bf555914893e9891c11519de94f): its *ingest* became "changing a
  fact is an ingest" and "one owner per fact", its *query* "answers compound", its *lint* the
  section above; the index got a one-line row budget back, since every session reads it. The
  gap showed here first: `FrontendFlutter.md` passed 1600 lines and its `INDEX.md` row 70
  words. Not adopted, there or here: a `log.md` (`git log -- .llmwiki` already gives the
  timeline), a search engine (the index and `grep` suffice at this size), YAML frontmatter
  (nothing queries it).
- **The mechanical half of the lint became a script (2026-09-27, docs/wiki-conventions-lint).**
  `scripts/wiki_lint.sh`, ported from countscore, with the dead-path finder that was inline in
  `scripts/wip.sh` moved to `scripts/lib/dead_paths.sh` so both share it. Two changes from
  countscore: the 25-word row budget is checked (a `wc -w` per row, cheap), and a gitignored
  path (`data/zapzap.db`, `scripts/deploy.env`, `native/Cargo.lock`) is not dead — a fresh
  checkout lacks it by design, and the wiki names such files on purpose. It stays out of CI as
  a gate: the real wiki fails it, and gating a pull request on a backlog it did not create
  would block unrelated work, so only its self-test runs.
