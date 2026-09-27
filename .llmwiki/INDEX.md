# ZapZap LLM Wiki — Index

Load this file first. Then read only the pages your task touches.

## Conventions

- `[[Name]]` resolves to `.llmwiki/<Name>.md`. A dangling link marks a page worth writing.
- Facts carry their source path (`zapzap-rust/src/main.rs:41`). Values are verbatim: if the
  code says `1000`, write `1000`.
- Every page ends with `## Decisions & History` — the *why* behind the facts. Add to it
  whenever a decision is taken or reversed.
- A fact that turns out wrong gets a status block under it rather than a silent rewrite:
  `> **Status: Outdated** (YYYY-MM-DD) — what changed, and what now holds.`
- **One owner per fact.** A fact lives on one page; other pages link to it, never restate it.
- **Changing a fact is an ingest.** `grep -rn` the old value across `.llmwiki/` and fix every
  page it falsifies, in the same change, each with its `Updated:` date and its row below.
- **Answers compound.** A synthesis the next task would otherwise rebuild — a root cause, a
  comparison, a measured figure — goes into the page that owns the topic in the same pull
  request, not only into the chat or the pull request body.
- Two pages that disagree and cannot be settled now: `> **Status: Contradicted** (YYYY-MM-DD)
  — see [[Other]]` on both, and a `wip/` entry.
- **Budgets:** a row below is one line of 25 words at most; a page stays under 400 lines —
  past it, split by sub-topic and leave a pointer. The lint pass: [[Documentation]].
- Do not paste code into pages. Point at the file and the line.

## Product and code

| Page | Summary | Updated |
|---|---|---|
| [[Architecture]] | The four code bases (Rust backend in production, React frontend, Flutter client, native engine), runtime topology, SSE, `data/`, the compose files | 2026-09-25 |
| [[GameRules]] | Where each rule of `GAME_RULES.md` is implemented | 2026-09-27 |
| [[Backend]] | `zapzap-rust/`: layout, AppState, environment, auth, SSE broadcaster, bots trigger, the schema it creates (`schema.sql`), the `seed` command | 2026-09-27 |
| [[Api]] | Every route, its auth and failure codes (typed), the zapzap/state/nextRound response contracts | 2026-09-27 |
| [[Bots]] | Bot types and Rust strategies, LLM bot, parameter files in `data/` | 2026-09-25 |
| [[Frontend]] | `frontend/`: React + Vite structure, API and SSE clients, Google OAuth, build and tests | 2026-09-27 |
| [[FrontendFlutter]] | `frontend-flutter/`: the Flutter client (Android + PWA under `/app/`), lib layout, ApiConfig, API layer, session and routing guard, Google sign-in (web + Android OAuth client), real-time channel (SSE), the app-bar menu (rules sheet, confirmed sign-out), the offline example game (`/tutorial`) and its first-opening offer, theme, l10n in ten languages (fr, en and eight translated), card model, play rules and card widgets, board motion and reduced motion, the admin screen, build and tests | 2026-09-27 |
| [[NativeEngine]] | `native/`: headless engine, DRL training, the two Node scripts that drive it (`train-native.js`, `genetic-optimize-thibot.js`) | 2026-09-25 |

## Operations and process

| Page | Summary | Updated |
|---|---|---|
| [[Deployment]] | The NAS deploy directory (no clone), the LAN registry, the four containers, their environment and `data/`, `scripts/deploy_nas.sh`, `--rollback <sha>` | 2026-09-26 |
| [[Testing]] | Each suite, what CI runs and skips, the `scope` job, the Flutter end-to-end procedure | 2026-09-27 |
| [[Hooks]] | What Claude Code refuses mechanically, the commit gates, what is not covered | 2026-09-27 |
| [[ParallelDelivery]] | `master` protection, worktrees, the shared Playwright browser and its fallback, scratchpad and `gh` pitfalls, lanes A–D, cleanup, local `wip/` | 2026-09-25 |
| [[Release]] | Google Play: package `com.zapzap.app`, the keys' fingerprints, `scripts/verify_aab.sh` and `scripts/play_publish.py` (androidpublisher v3, from this machine only), the service account, versions shipped | 2026-09-26 |
| [[Documentation]] | Which documents a change implicates; the wiki lint (`scripts/wiki_lint.sh`); the `CLAUDE.md` budget | 2026-09-27 |
| [[KnownLimits]] | What is deliberately left out of the gates, and why | 2026-09-25 |

## Procedures live in skills, not here

`.claude/skills/`: `ship-parallel` (implement, merge, deploy), `wip-refine` (sort the
backlog), `deploy` (production on the NAS), `release-android` (a bundle to Google Play),
`flutter-device-test` (the Android app on the user's phone).
