# ZapZap LLM Wiki — Index

Load this file first. Then read only the pages your task touches.

## Conventions

- `[[Name]]` resolves to `.llmwiki/Name.md`. A dangling link marks a page worth writing.
- Facts carry their source path (`zapzap-rust/src/main.rs:41`). Values are verbatim: if the
  code says `1000`, write `1000`.
- Every page ends with `## Decisions & History` — the *why* behind the facts. Add to it
  whenever a decision is taken or reversed.
- A fact that turns out wrong gets a status block under it rather than a silent rewrite:
  `> **Status: Outdated** (YYYY-MM-DD) — what changed, and what now holds.`
- When you change a durable fact, update the page **and** its `Updated:` date.
- Do not paste code into pages. Point at the file and the line.

## Product and code

| Page | Summary | Updated |
|---|---|---|
| [[Architecture]] | The five code bases (Rust backend, React frontend, Flutter client, native engine, legacy Node), runtime topology, SSE, `data/`, the compose files | 2026-09-24 |
| [[GameRules]] | Where each rule of `GAME_RULES.md` is implemented | 2026-09-22 |
| [[Backend]] | `zapzap-rust/`: layout, AppState, environment, auth, SSE broadcaster, bots trigger, the schema it creates (the Node DDL) | 2026-09-23 |
| [[Api]] | Every Rust route, its auth and failure codes; where the Node/Rust differences are listed | 2026-09-24 |
| [[Bots]] | Bot types and strategies, LLM bot, parameters in `data/` | 2026-09-22 |
| [[Frontend]] | `frontend/`: React + Vite structure, API and SSE clients, Google OAuth, build and tests | 2026-09-23 |
| [[FrontendFlutter]] | `frontend-flutter/`: the Flutter client (Android + PWA under `/app/`), lib layout, ApiConfig, API layer, session and routing guard, real-time channel (SSE), theme, l10n fr/en, card model, play rules and card widgets, build and tests | 2026-09-24 |
| [[NativeEngine]] | `native/`: headless engine, DRL training, the Node scripts that drive it | 2026-09-23 |

## Operations and process

| Page | Summary | Updated |
|---|---|---|
| [[Deployment]] | The NAS, the three containers (Node backend in production), `deploy.sh`, the tracked-database trap | 2026-09-24 |
| [[Testing]] | Each suite, what CI runs and skips, the `scope` job, the Node vs Rust parity suite, the Flutter end-to-end procedure | 2026-09-24 |
| [[Hooks]] | What Claude Code refuses mechanically, the commit gates, what is not covered | 2026-09-23 |
| [[ParallelDelivery]] | `master` protection, worktrees, the shared Playwright browser, lanes A–D, cleanup, local `wip/` | 2026-09-24 |
| [[Documentation]] | Which documents a change implicates; the `CLAUDE.md` budget | 2026-09-22 |
| [[KnownLimits]] | What is deliberately left out of the gates, and why | 2026-09-24 |

## Procedures live in skills, not here

`.claude/skills/`: `ship-parallel` (implement, merge, deploy), `wip-refine` (sort the
backlog), `deploy` (production on the NAS).
