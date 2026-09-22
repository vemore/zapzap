---
name: wip-refine
description: Refine the ZapZap wip/ backlog (local, gitignored, in the main checkout) — check every open entry against the code, sort it into already fixed, obsolete, merge, needs detail, ready or promote, prioritise what is ready, and propose what moves from wip/todo_nr/ to wip/todo/; the user decides, then the moves are applied in the main checkout (nothing is committed). Use when wip/todo/ empties, when wip/todo_nr/ passes 30 entries, or when the user asks what to work on next. Triggers: "refinement", "grooming", "backlog", "trier le backlog", "qu'est-ce qui passe en todo", "fais le tri dans wip", "what's next", "promote to todo", "obsolete entries".
---

# Refining the wip/ backlog

The point where an entry moves from `todo_nr/` to `todo/` is the **commitment point**: before
it, entries are options, cheap to write and cheap to drop; after it, they are the work in
progress. This skill prepares that decision and proposes it. **The user decides.** Nothing
moves until they answer. `wip/` is local and gitignored: the decision is applied by moving
files in the main checkout, with no pull request. Why it works this
way: `.llmwiki/ParallelDelivery.md` § Decisions & History.

**When:** when `wip/todo/` empties, when `todo_nr/` passes 30 entries, or on request. Keep a pass short: it prepares a decision and does
not implement anything.

## 1. Mechanical signals

From the main checkout on a fresh `master` (`git fetch --prune origin && git merge --ff-only
origin/master`):

```bash
scripts/wip.sh refine all      # every open entry: age, idle days, flags; crowded themes
scripts/wip.sh check           # header fields, Status line in done/
```

| Flag | Means | Look at |
|---|---|---|
| `stale` | the entry file untouched (mtime) for over 60 days | revalidate or drop it. An idea that matters will come back. |
| `dead-path:[…]` | a path in backticks no longer exists | refactored away (the evidence is stale), **or** a file the fix proposes to create. Read the sentence. |
| `links-closed:[…]` | links an entry already in `done/` | a dependency now met, or a problem the other entry already solved |
| `no-fix` / `no-acceptance` | the section is missing | a candidate for *needs detail* |
| `open-question` | a question waits on the user | ask it again, or keep it in *needs detail* |
| `crowded theme` | a theme with more than 4 entries | overlaps and supersessions: *merge* |
| `BLOCKS-RELEASE` | `Blocks release: yes` | always **promote**, whatever the rest |

## 2. Check each entry against the code

Read-only: is the problem still true today? Grep the files it names, read the lines, check
`git log --oneline -- <path>` since `Noted`, and look for a merged pull request that fixed it
without closing the entry. Every verdict carries a piece of **evidence**: a line, a commit or
a command output.

For more than 15 entries, split the work by theme across 2 or 3 `Explore` agents. Give each
agent its entries' paths and ask it for one line per entry: `still-true | fixed-by <sha/#PR> |
changed <what>`, plus the evidence. Never ask an agent to judge priority.

## 3. Sort into six bins, in this order

Hygiene before prioritisation: what goes away is cleared first, so it is never ranked.

1. **Already fixed.** The code no longer has the problem → `done/`, `Status: done`, naming the
   commit or pull request that closed it.
2. **Obsolete.** The feature was removed, a decision made it moot, or it went stale and
   nothing supports it any more → `done/`, `Status: dropped`, with the reason.
3. **Merge.** Several entries describe one problem, or one entry's fix replaces others (e.g.
   an entry saying "this replaces the two entries above"). The survivor absorbs the others'
   evidence. The others move to `done/` with `Status: dropped (date) — merged into [[survivor]]`.
4. **Needs detail.** Fails the definition of ready (§4). For each entry, give the **exact
   question** for the user or the evidence still to gather. "Needs more thought" is not an
   answer.
5. **Ready.** Passes §4.
6. **Promote.** Ready and within the top of the ranking (§5), up to the WIP limit.

## 4. Definition of ready

An entry is ready when all five hold:

1. **Still true.** The problem exists in today's code, and the evidence proves it.
2. **One pull request.** The `**Fix:**` is concrete and fits one reviewable pull request
   (about a day's work, one reason to revert). Anything bigger is split into several entries
   first.
3. **Testable.** An `**Acceptance:**` section gives 2 to 5 statements that can each be checked
   (`wip/README.md` § An entry). Draft them in the proposal; the user validates them.
4. **Unblocked.** No decision waits on the user, and no open entry has to land first.
5. **Themed.** The `Theme` reuses an existing tag (`scripts/wip.sh themes all`).

Ready is required for **promotion**, not for writing an entry: a new entry stays twenty lines
of evidence and a fix.

## 5. Prioritise what is ready

No scoring formula: at this size, RICE or WSJF cost more than they decide, and "reach" cannot
be measured. Rank by:

1. **Cost-of-delay class.** *Expedite*: `Blocks release: yes` — a security, crash, data-loss or
   production-down problem. *Fixed date*: an external deadline. *Standard*: user-visible value.
   *Intangible*: tooling, docs, debt. Higher classes come first.
2. Within a class, **value** (H/M/L) against **cost** (S/M/L): high value and small cost first.
   Two entries in one theme that would share a pull request are ranked together.

Give each ranked entry one line of reason. **WIP limit:** `wip/todo/` holds at most **12**
entries, about one `ship-parallel` run. Promote only to that limit. Anything over it stays
ready in `todo_nr/`.

## 6. Propose, then let the user decide

Present one table per bin: entry, verdict, evidence, and for *needs detail* the question. Then
ask one multi-select `AskUserQuestion` per non-empty bin, covering what to apply as proposed.
Ask the *needs detail* questions in the same round (at most 4 per call; group them). An entry
the user leaves unticked stays where it is.

## 7. Apply in the main checkout

`wip/` is gitignored: there is no branch and no pull request.

- every move is a plain `mv`, and the file name never changes (`wip/README.md` § Lifecycle);
- a closed or dropped entry gets its `**Status:**` line directly under the title;
- the answers to the *needs detail* questions and the approved acceptance criteria are written
  into the entries; a question left for later becomes an `**Open question:**` line;
- `scripts/wip.sh check` is green.

Report the counts per bin and what is now in `wip/todo/`. From there, `ship-parallel`
implements `wip/todo/`.

## When the tool itself fights you

A flag that fires on the wrong thing, a bin that does not fit, a limit that is always wrong:
record it as a `wip/` tooling entry, as `CLAUDE.md` says. Do not bend the pass around it.
