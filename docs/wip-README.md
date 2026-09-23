# wip — work tracking (local, never committed)

One file per piece of work. `wip/` is **gitignored** and lives only in the **main
checkout** (`scripts/wip.sh path` prints it): an agent working in a worktree reads entries
there by that absolute path, but never writes them (below). This file is copied from
`docs/wip-README.md` by `scripts/wip.sh init`; the committed copy is the reference.

| Folder | Holds |
|---|---|
| `todo/` | Work committed to now — at most 12 entries |
| `todo_nr/` | Backlog: noted, not yet committed to |
| `done/` | Closed or dropped work, kept for its reasoning |
| `assets/<entry-slug>/` | Images an entry points at (mock-ups, screenshots) |

`scripts/wip.sh` is the index: `list [todo|todo_nr|done|all]`, `themes`, `check`, `refine`.

## An entry

`<folder>/YYYY-MM-DD-<slug>.md`, dated the day the problem was noted. Short: the evidence
and the fix, twenty lines or so.

```markdown
# <What is wrong, as a statement>

- **Noted:** 2026-09-22 — <while doing what>
- **Theme:** <one tag, e.g. security, bots, frontend-quality, hooks>
- **Area:** backend | native | frontend | tooling | docs | ops
- **Blocks release:** yes — <why> | no

<The problem, with file paths and evidence.>

**Fix:** <the proposed change.>

**Acceptance:** <required to be promoted to todo/ — 2 to 5 statements a test or a
command can check.>

**Open question:** <what the user must decide; the answer replaces it.>
```

`Theme` groups entries into one pull request: reuse an existing tag (`scripts/wip.sh
themes all`) before inventing one. `Blocks release: yes` is for what must not wait: a
security flaw, a crash, data loss, production down.

## Where a new entry goes

A problem a task surfaces but was not asked to fix is neither fixed inline nor dropped: it
becomes an entry, and the task carries on. `todo_nr/` by default; `todo/` only when it
blocks (above). A skill, hook or wiki procedure that had to be worked around is an entry
too — and the fix may be a removal.

An agent working in a worktree (`ship-parallel`) never writes under `wip/`: it lists each
new entry, complete in the format above, under a `## New wip entries` heading of its final
report, and the orchestrator writes it to `todo_nr/` (or `todo/`) in the main checkout after
the hand-back.

## Lifecycle

- **Moving** between folders is a plain `mv`; the file name never changes.
- **Closing** happens once the pull request that fixes it is **merged** — the orchestrator
  does it in the main checkout (`ship-parallel` §5): `mv wip/todo/X.md wip/done/X.md`, then
  a line under the title:
  `**Status:** done (YYYY-MM-DD) — closed by #PR. <What closed it, in one sentence.>`
- **Dropping** is a move to `done/` with `**Status:** dropped (YYYY-MM-DD) — <why>`.
- **Partly done** stays open, rewritten to what is left.
- Never delete an entry. Nothing under `wip/` is ever committed — the commit hook refuses
  it (`.llmwiki/Hooks.md`).

## Refinement

Moving an entry from `todo_nr/` to `todo/` is the commitment point. The `wip-refine`
skill prepares it: checks each open entry against the code, sorts it, ranks what is ready.
The user decides.
