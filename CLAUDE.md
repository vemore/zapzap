# ZapZap — Instructions for Claude Code

> Budget: ≤ 120 lines; anything past it moves to the wiki page that owns it.

ZapZap is a multiplayer rummy-style card game: a Rust backend (`zapzap-rust/`, axum + SQLite,
**what production runs**), a React + Vite frontend (`frontend/`), a Flutter client in the
making (`frontend-flutter/`, Android + PWA), and a Rust simulation engine for bot training
(`native/`).

## Read the wiki first

Durable project knowledge lives in **`.llmwiki/`**, not in this file. **Before any
non-trivial task, read `.llmwiki/INDEX.md` and load the pages your task touches.** Do not
guess at architecture, routes, rules or deployment — a page already has it. `[[Name]]` in a
wiki page resolves to `.llmwiki/Name.md`. The game rules are `GAME_RULES.md`.

Repeatable procedures are **skills** in `.claude/skills/`: `ship-parallel`, `wip-refine`,
`deploy`.

## Non-negotiables

1. **The database never enters git.** `data/zapzap.db` holds every account; in production it
   is a file in the NAS clone that a careless `git pull` can delete (`deploy` skill §0).
2. **A rule change updates `GAME_RULES.md`** and the test that proves it, in the same change.

What a hook refuses outright — killing node, secrets, the database, `wip/` in a commit, red
gates, committing on master, force-push, push to master, stacked pull requests, merges
without squash — and what it does not cover: `.llmwiki/Hooks.md`.

## Workflow

- **Work is tracked one file per entry under `wip/`**, which is **local and never committed**
  (gitignored, main checkout only; `scripts/wip.sh path`): `todo/` committed to now,
  `todo_nr/` backlog, `done/` closed. `wip/README.md`.
- **A problem you find but were not asked to fix becomes a `wip/` entry** — not an inline
  fix, not dropped: `todo_nr/`, or `todo/` when it blocks (security, data loss, crash,
  production down). Then carry on. An agent in a worktree never writes `wip/`: it puts the
  entry, complete, under `## New wip entries` in its final report; the orchestrator writes it.
- **Tooling that fights you is a `wip/` entry too** — a skill, hook, wiki procedure or this
  file that forced a detour. The fix may be a removal; prefer replacing to adding.
- **An entry is closed after its pull request merges**, by the orchestrator in the main
  checkout: `mv` to `wip/done/` with a `**Status:** done (date) — closed by #PR` line.
- **Keep every document a change falsifies true, in the same commit**: its wiki page and
  `Updated:` date, `README.md`, `GAME_RULES.md`. `.llmwiki/Documentation.md`.
- **Nothing is finished until it is tested and committed.** The commit hook runs the fast
  gates, CI runs the tests. `.llmwiki/Hooks.md`, `.llmwiki/Testing.md`.
- **A finished change is a green pull request against `master`.** Push, `gh pr create --base
  master` with a body saying what changed and why, `gh pr checks`, fix what fails, report the
  URL and the check state. Never stack on another branch. A branch held back sets
  `git config branch.<name>.noPullRequest true`, and you say so.
- **You merge and deploy your own green pull requests, through `ship-parallel`**, in the lane
  their risk picked at planning time: squash-merge, deploy what the merge changed (`deploy`
  skill), smoke-test production; a problem found after is a new pull request.
  `.llmwiki/ParallelDelivery.md`.
- **Several tasks at once are several pull requests, in parallel** — one per theme, one agent
  and worktree each: `ship-parallel`.
- **Leave the local environment clean**: the main checkout back on a fast-forwarded `master`,
  then `scripts/cleanup_local.sh` and `--apply` once no agent is working.

## Commands

```bash
# Rust backend (toolchain pinned: rust-toolchain.toml)
cd zapzap-rust && JWT_SECRET=<openssl rand -hex 32> cargo run   # :9999, JWT_SECRET required; needs the DB file
cargo run -- seed --demo                         # bots + demo users (demo123); idempotent, creates the DB file
cargo fmt && cargo clippy --all-targets -- -D warnings
cargo test                                       # unit + API integration tests: .llmwiki/Testing.md

# Frontend
cd frontend && npm ci && npm run dev             # :5173, proxies /api to :9999
npm run build

# Flutter client (Android + PWA): .llmwiki/FrontendFlutter.md
cd frontend-flutter && flutter analyze && flutter test
flutter build web --base-href /app/ && flutter build apk --debug

# Native engine and training
cd native && cargo test
node scripts/train-native.js                     # .llmwiki/NativeEngine.md

# Tooling
scripts/wip.sh list all                          # the local backlog
scripts/hooks_selftest.sh                        # the hooks
```

Kill a local server by port, never by name: `lsof -ti:9999 | xargs kill`.

## Code style

- Rust: `cargo fmt`, clippy clean with `-D warnings`; errors via `thiserror`/`anyhow`.
- Frontend: React function components and hooks; API calls through `frontend/src/services/`.
- Match the surrounding code: its comment density, naming and idiom.

## Git

**Start every piece of work on a fresh branch off the current `master`, in its own
worktree**, before the first commit. The main checkout stays on `master`; the hooks never
fetch, so the fetch is on you.

```bash
git fetch --prune origin
git worktree add ../zapzap-<short-topic> -b <type>/<short-topic> origin/master
scripts/worktree_setup.sh ../zapzap-<short-topic>        # npm ci, cargo, flutter pub get; --deploy links .env
```

An agent launched with `isolation: "worktree"` has its worktree already, and switches to
`<type>/<short-topic>` off `origin/master` as its first step.

- Branch names `<type>/<short-topic>`; commit messages `feat:`, `fix:`, `refactor:`, `docs:`,
  `chore:`.
- Never force-push, never rewrite a commit on `origin/master`. Bring a branch up to date by
  merging `master` in: `gh api -X PUT repos/{owner}/{repo}/pulls/<n>/update-branch`.
