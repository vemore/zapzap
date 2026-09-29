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
| [[Architecture]] | The three code bases (Rust backend in production, Flutter client, native engine), runtime topology, SSE, `data/`, the compose files | 2026-09-29 |
| [[GameRules]] | Where each rule of `GAME_RULES.md` is implemented, the turn time limit included | 2026-09-29 |
| [[Backend]] | `zapzap-rust/`: layout, AppState, environment, auth and account changes, SSE, bots trigger, turn timer, versioned game-state writes, schema and migrations, `seed`, `reset-password` | 2026-09-29 |
| [[Api]] | Every route, its auth and failure codes (typed), the zapzap/state/nextRound response contracts | 2026-09-29 |
| [[Bots]] | Bot types and Rust strategies, LLM bot, parameter files in `data/` | 2026-09-28 |
| [[Frontend]] | The React client, removed 2026-09-29: what replaced it, its redirected URLs, where its code can still be read | 2026-09-29 |
| [[FrontendFlutter]] | `frontend-flutter/`, the Flutter client (Android + PWA under `/app/`) hub: status, stack, lib layout, ApiConfig, API layer, theme, wide screens, build and tests | 2026-09-29 |
| [[FlutterAuth]] | Flutter session and token storage, login and register screens, routing guard, Google sign-in (web + Android OAuth client) | 2026-09-29 |
| [[FlutterRealtime]] | Flutter real-time channel (SSE): parser, two transports, reconnecting `SseClient`, `SseProvider` following the session, presence | 2026-09-29 |
| [[FlutterParties]] | Flutter parties list, create-party, lobby and its bots, back navigation, the app-bar menu (rules, sign-out), the account page (username, password, deletion) | 2026-09-29 |
| [[FlutterGameBoard]] | Flutter game board: `GameProvider`, modes, errors, layouts, the turn clock and ejection, end of round and game with its overlays, the offline example game (`/tutorial`) | 2026-09-29 |
| [[FlutterGameUi]] | Flutter turn UX (step, named button, suggestions, ZapZap, felt, pile, opponents), board motion and reduced motion, card model, play rules, card widgets | 2026-09-29 |
| [[FlutterHistoryAdmin]] | Flutter history, game details and statistics screens; the admin screen (users, parties, statistics tabs) | 2026-09-29 |
| [[FlutterI18n]] | Flutter l10n: ten ARB files, the game-terms glossary, the l10n tests, generated code not committed, the "tu" voice | 2026-09-29 |
| [[FlutterAndroidPwa]] | Flutter Android app (CI APK, release signing, keys, OAuth SHA-1s, manifest, icons) and the PWA image (Dockerfile, nginx, manifest) | 2026-09-29 |
| [[NativeEngine]] | `native/`: headless engine, DRL training, the two Node scripts that drive it (`train-native.js`, `genetic-optimize-thibot.js`) | 2026-09-27 |

## Operations and process

| Page | Summary | Updated |
|---|---|---|
| [[Deployment]] | The NAS deploy directory (no clone), the LAN registry, Compose v2, the three containers, the old React URLs' redirects, DSM's `X-Forwarded-For` header, `scripts/deploy_nas.sh`, `--rollback <sha>` | 2026-09-29 |
| [[Testing]] | Each suite, what CI runs and skips, the `scope` job, the Flutter end-to-end procedure | 2026-09-29 |
| [[Hooks]] | What Claude Code refuses mechanically, the commit gates, what is not covered | 2026-09-29 |
| [[ParallelDelivery]] | `master` protection, worktrees, shared browser, scratch directory and `gh` pitfalls, lanes A–D, size count, model routing, merged-not-deployed, cleanup, `wip/`, metrics | 2026-09-29 |
| [[Release]] | Google Play: package `com.zapzap.app`, the keys' fingerprints, `scripts/verify_aab.sh` and `scripts/play_publish.py` (androidpublisher v3, from this machine only), the service account, versions shipped | 2026-09-28 |
| [[AgentEvals]] | `evals/`: replaying past tasks with `claude -p` in throwaway worktrees, deterministic checks, the self-test, how to run a case for real and its cost | 2026-09-29 |
| [[Documentation]] | Which documents a change implicates; the wiki lint (`scripts/wiki_lint.sh`); the `CLAUDE.md` budget | 2026-09-27 |
| [[KnownLimits]] | What is deliberately left out of the gates, and why | 2026-09-25 |

## Procedures live in skills, not here

`.claude/skills/`: `ship-parallel` (implement, merge, deploy), `wip-refine` (sort the
backlog), `deploy` (production on the NAS), `release-android` (a bundle to Google Play),
`flutter-device-test` (the Android app on the user's phone), `i18n-add-string` (a Flutter
string across the ten ARB files). `.claude/agents/`: `implementer-complex` and
`implementer-simple`, the implementers `ship-parallel` launches by rating
([[ParallelDelivery]] § Model routing).
