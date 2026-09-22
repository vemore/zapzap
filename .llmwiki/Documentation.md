# Documentation

> Scope: which documents a change implicates, the wiki conventions, and the `CLAUDE.md`
> budget. No hook enforces these: they need judgement ([[Hooks]]).
> Related: [[ParallelDelivery]] · [[Hooks]]
> Updated: 2026-09-22

## Facts

### The wiki (`.llmwiki/`)

Conventions are in `INDEX.md`. A change that falsifies a fact on a page updates that page and
its `Updated:` date **in the same pull request**; a decision taken or reversed goes under
`## Decisions & History`.

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
implements each rule.

### The `CLAUDE.md` budget

At most **120 lines**: what the project is, "read the wiki first", the non-negotiables, each
workflow rule in one line with a pointer, the commands, Git. Anything longer moves to the
page that owns it. When a rule becomes a hook, it leaves `CLAUDE.md` for [[Hooks]].

## Decisions & History

- **Budget and wiki ported from countscore (2026-09-22).** The old `CLAUDE.md` (≈170 lines)
  mixed durable facts, deploy commands and rules, and was wrong on the frontend (vanilla JS)
  and on which backend is current. Facts moved to pages written from the code; the deploy
  recipe moved to the `deploy` skill; the "never run" list became a hook.
