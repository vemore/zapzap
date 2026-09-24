# Api

> Scope: every HTTP route served by the Rust backend (`zapzap-rust/src/main.rs`, `zapzap-rust/src/api/routes/*.rs`): method, path, auth, handler, failure codes; differences with the old `BACKEND_API.md` and the legacy Node routes.
> Related: [[Backend]] · [[Frontend]] · [[Bots]] · [[GameRules]] · [[Testing]]
> Updated: 2026-09-24

## Facts

### Conventions
- Router assembly: `zapzap-rust/src/api/routes/mod.rs:23-35` (under `/api`), plus `/suscribeupdate` and `/health` at the root (`zapzap-rust/src/main.rs:41-45`).
- Auth column: **JWT** = `auth_middleware` (Bearer header, bare 401 without JSON body on a missing or invalid token, or a token whose user no longer exists, `zapzap-rust/src/api/middleware/auth_middleware.rs`); **opt** = optional auth; **admin** = JWT + `admin_middleware`, which reads `is_admin` from the database (401 `AUTH_REQUIRED` / 403 `ADMIN_REQUIRED`, `{success:false, error, code}`, as Node); the handlers do not check again; **none** = public.
- Error body for auth/party/game: `{error, code, details?}` (`zapzap-rust/src/api/routes/game.rs:243-248`); admin/bots/stats/history use `{success:false, error}` or `{error}` without `code`.
- Error codes come from **substring matching on the use-case error message**, which is fragile (see "Error-mapping mismatches").
- CORS fully permissive (`zapzap-rust/src/main.rs:46`). No rate limiting.

### Root
| Method | Path | Auth | Handler | Notes |
|---|---|---|---|---|
| GET | `/health` and `/api/health` | none | `zapzap-rust/src/api/routes/health.rs:13` | `{status:"ok", version, uptime_seconds}`; uptime counts from the first health call, not process start (`health.rs:11-14`) |
| GET | `/suscribeupdate?token=` | token optional (query) | `zapzap-rust/src/api/sse.rs` | SSE; events without a party and a public party's lifecycle events to all, a game's moves and private-party events only to that party's players (a token of a deleted user names nobody). See [[Backend]] |

### Auth — `/api/auth` (`zapzap-rust/src/api/routes/auth.rs:10-14`)
| Method | Path | Auth | Handler | Success | Failures |
|---|---|---|---|---|---|
| POST | `/register` | none | `auth.rs:79` | 201 `{success, user{id,username,createdAt}, token}` | 400 `MISSING_CREDENTIALS`/`VALIDATION_ERROR`, 409 `USERNAME_EXISTS`, 500 `REGISTRATION_ERROR` |
| POST | `/login` | none | `auth.rs:155` | 200 `{success, user{id,username,isAdmin}, token}` | 400 `MISSING_CREDENTIALS`/`VALIDATION_ERROR`, 401 `INVALID_CREDENTIALS`, 500 `LOGIN_ERROR` |

### Party — `/api/party` (`zapzap-rust/src/api/routes/mod.rs:38-92`)
| Method | Path | Auth | Handler | Failures |
|---|---|---|---|---|
| GET | `/` | opt | `zapzap-rust/src/api/routes/party.rs:319` | 500 `GET_PARTIES_ERROR`. Query `status`, `limit` (default 50, **no max**), `offset` (default 0) (`party.rs:327-329`). Only `visibility='public'` parties (`zapzap-rust/src/infrastructure/database/repositories/party_repo.rs:149`) |
| POST | `/` | JWT | `party.rs:247` | 400 `MISSING_PARTY_NAME`, 500 `CREATE_PARTY_ERROR` (all use-case errors, incl. validation). Body `name`, `visibility` (default `public`), `settings{handSize=5,maxScore=100,enableGoldenScore=true,goldenScoreThreshold=100}` (`party.rs:263-268`), `botIds[]` |
| GET | `/:partyId` | JWT | `party.rs:369` | 404 `PARTY_NOT_FOUND`, 403 `NOT_IN_PARTY` (`User is not in this party`) for a non-member of a **private** party, so its `inviteCode` stays with its players (`zapzap-rust/src/application/party/get_party_details.rs`); Node means to refuse too but its message has no branch and answers 500 `GET_PARTY_ERROR`. Public parties: any user, as in Node |
| DELETE | `/:partyId` | JWT | `party.rs:614` | 404, 403 `NOT_AUTHORIZED` (not owner), 500 when in progress (should be 409 `PARTY_PLAYING`) |
| POST | `/:partyId/join` | JWT | `party.rs:435` | 404, 409 `PARTY_FULL` (8 players, `zapzap-rust/src/domain/entities/party.rs:100-101`), 500 for already-in-party / not waiting (should be 409). A **private** party needs body `inviteCode` equal to its code: without one 403 `PRIVATE_PARTY` `Party is private. Use invite code to join.`, with a wrong one 403 `INVALID_INVITE_CODE` `Invalid invite code`, body `{error, code}` (`zapzap-rust/src/application/party/join_party.rs`). Node's messages; Node answers 500 `JOIN_PARTY_ERROR` (no branch in `partyRoutes.js`), a Node bug |
| POST | `/:partyId/leave` | JWT | `party.rs:500` | 404, 500 for not-in-party / not waiting (should be 403). Owner leaving transfers ownership (`zapzap-rust/src/application/party/leave_party.rs:87-89`) |
| POST | `/:partyId/start` | JWT | `party.rs:551` | 404, 403 `NOT_OWNER`, 500 for not-waiting and not-enough-players (3..=8 required, `zapzap-rust/src/domain/entities/party.rs:105-106`) |

### Game — `/api/game` (`zapzap-rust/src/api/routes/mod.rs:95-147`), all JWT
| Method | Path | Handler | Body | Failures |
|---|---|---|---|---|
| GET | `/:partyId/state` | `zapzap-rust/src/api/routes/game.rs:255` | — | 404, 403 `NOT_IN_PARTY` for a non-member, as Node (`zapzap-rust/src/application/game/get_game_state.rs`), 500. Spawns a bot trigger (`game.rs:345`). `eliminatedPlayers` computed as score > 100 hard-coded (`game.rs:302-308`), ignoring `maxScore` |
| POST | `/:partyId/selectHandSize` | `game.rs:381` | `{handSize}` (4-7, 4-10 in golden score, `zapzap-rust/src/application/game/select_hand_size.rs:60-62`) | 404, 403 `NOT_YOUR_TURN`, 400 `INVALID_ACTION_STATE`/`INVALID_HAND_SIZE` |
| POST | `/:partyId/play` | `game.rs:452` | `{cardIds:[u8]}` | 400 `MISSING_CARDS`, 404, 403 `NOT_YOUR_TURN`, 400 `INVALID_ACTION_STATE`/`INVALID_CARDS`/`INVALID_PLAY` |
| POST | `/:partyId/draw` | `game.rs:540` | `{source:"deck"\|"played", cardId?}` | 400 `INVALID_SOURCE`, 404, 403, 400 `DECK_EMPTY`/`NO_CARDS_AVAILABLE`/`CARD_NOT_AVAILABLE` |
| POST | `/:partyId/zapzap` | `game.rs:628` | — | 404, 403, 400 `HAND_TOO_HIGH`/`INVALID_ACTION_STATE`; response `{zapzapSuccess, counteracted, counteractedBy, scores, callerPoints}` |
| POST | `/:partyId/nextRound` | `game.rs:743` | — | 404, 403 `NOT_IN_PARTY` for a non-member (checked in the handler, `require_party_member`, `zapzap-rust/src/api/access.rs`; `NextRound` itself still never reads `input.user_id`), 400 `INVALID_PARTY_STATE`/`ROUND_NOT_FINISHED` |
| POST | `/:partyId/trigger-bot` | `game.rs:846` | — | 404 `PARTY_NOT_FOUND`, 403 `NOT_IN_PARTY` for a non-member (`require_party_member`; Node has no check here), 500 on repo errors |

### Stats — `/api/stats` (`zapzap-rust/src/api/routes/mod.rs:150-163`)
| Method | Path | Auth | Handler | Notes |
|---|---|---|---|---|
| GET | `/me` | JWT | `zapzap-rust/src/api/routes/stats.rs:174` | 404 user not found |
| GET | `/user/:userId` | none | `stats.rs:182` | public stats for any id |
| GET | `/leaderboard` | none | `stats.rs:284` | `minGames` default 5, `limit` 50, `offset` 0 (`stats.rs:21-36`); humans only |
| GET | `/bots` | none | `stats.rs:370` | per-difficulty bot stats |

### History — `/api/history` (`zapzap-rust/src/api/routes/mod.rs:166-191`)
| Method | Path | Auth | Handler | Notes |
|---|---|---|---|---|
| GET | `/` and `/my-games` | JWT | `zapzap-rust/src/api/routes/history.rs:164` | same handler; `limit` default 20 (`history.rs:28-30`) |
| GET | `/public` | none | `history.rs:271` | finished public games: list and `total` both filter `visibility = 'public'`, as Node (`src/infrastructure/database/sqlite/repositories/PartyRepository.js:760`, `:1028`) |
| GET | `/:partyId` | JWT | `history.rs:343` | 404 `Game not found`; 403 `{error:"Access denied. Party is private."}` for a **private** game to a user in neither `party_players` nor `player_game_results`. Node checks nothing here; public games stay readable by any signed-in user |

### Admin — `/api/admin` (`create_admin_router`, `zapzap-rust/src/api/routes/mod.rs`), all admin: 401 without a token, 403 `ADMIN_REQUIRED` for a non-admin
| Method | Path | Handler | Notes |
|---|---|---|---|
| GET | `/users` | `zapzap-rust/src/api/routes/admin.rs:181` | humans only, `limit` 50 (`admin.rs:38-40`) |
| DELETE | `/users/:userId` | `admin.rs:303` | 400 self-delete (`admin.rs:320`) or target is admin (`admin.rs:355`), 404 |
| POST | `/users/:userId/admin` | `admin.rs:384` | body `{isAdmin}`; 404 |
| GET | `/parties` | `admin.rs:456` | `status`, `limit`, `offset` |
| POST | `/parties/:partyId/stop` | `admin.rs:592` | 404, 400 already finished (`admin.rs:632`) |
| DELETE | `/parties/:partyId` | `admin.rs:662` | 404 |
| GET | `/statistics` | `admin.rs:735` | counts |

### Misc
| Method | Path | Auth | Handler | Notes |
|---|---|---|---|---|
| GET | `/api/bots?difficulty=` | none | `zapzap-rust/src/api/routes/bots.rs:51` | valid: easy, medium, hard, hard_vince, ml, drl, llm, thibot (`bots.rs:55-64`); 400 otherwise |
| GET | `/api/players/connected` | none | `zapzap-rust/src/api/routes/players.rs:34` | max 5 sessions; status always `lobby` (see [[Backend]]) |

### Error-mapping mismatches (use-case message vs handler matcher)
| Route | Use-case message | Matcher expects | Result |
|---|---|---|---|
| join | `Already in party` (`join_party.rs:101`) | `already in party` (case-sensitive, `party.rs:458`) | 500 instead of 409 |
| join | `Party is not in waiting state` (`join_party.rs:99`) | `already started` (`party.rs:460`) | 500 instead of 409 `PARTY_STARTED` |
| start | `Party is not in waiting state` / `Not enough players (minimum 3)` (`start_party.rs:99-101`) | `already playing` (`party.rs:570`) | 500 |
| delete | `Cannot delete party in progress` (`delete_party.rs:99`) | `active game` (`party.rs:635`) | 500 |
| leave | `Not in party` (`leave_party.rs:111`) | exact `User is not in this party` (`party.rs:517`) | 500 instead of 403 |
| game actions | `Not in party` (`play_cards.rs:109` etc.) | `not in this party` (`game.rs:482`, `:571`, `:645`) | 500 instead of 403 `NOT_IN_PARTY` |

### Differences with `BACKEND_API.md` (old doc, Node era, "Last Updated 2025-12-04"; removed 2026-09-22, read it with `git show 1e063d6:BACKEND_API.md`)
- Token lifetime: doc says 24 hours (`BACKEND_API.md:94`); code is 7 days (`zapzap-rust/src/infrastructure/auth/jwt_service.rs:28`).
- Auth error codes `MISSING_AUTH_HEADER`/`INVALID_AUTH_FORMAT`/`INVALID_TOKEN` (`BACKEND_API.md:128-130`): Rust returns a bare 401 without body.
- Game error codes `GAME_NOT_STARTED`/`INVALID_TURN`/`INVALID_ACTION`/`CARD_NOT_IN_HAND` (`BACKEND_API.md:144-148`) do not exist; Rust uses `NOT_YOUR_TURN`, `INVALID_ACTION_STATE`, `INVALID_CARDS`, `INVALID_PLAY`. Wrong-phase is 400, not 403.
- Start minimum: doc "minimum 2" (`BACKEND_API.md:454`); code requires 3 (`zapzap-rust/src/domain/entities/party.rs:106`).
- `GET /api/party` "max: 100" (`BACKEND_API.md:298`): no max in code.
- SSE: doc says heartbeat every 15 s and `retry: 500` (`BACKEND_API.md:679-683`); Rust sends a comment every 20 s and no `retry`; events carry `type` and flattened data, not only `{partyId,userId,action}`.
- Health: doc `{status, timestamp}` (`BACKEND_API.md:720-721`); Rust `{status, version, uptime_seconds}`.
- Undocumented in the old doc: `selectHandSize`, `nextRound`, `trigger-bot`, `/stats/*`, `/history/*`, `/admin/*`, `/bots`, `/players/connected`.
- `AUDIT_REPORT.md` (2025-11-06) audits the pre-clean-architecture `app.js`/jQuery app (e.g. "No Turn Validation in API Endpoints"); obsolete for Rust, which checks turn and phase in every game use case.

### Missing vs legacy Node / frontend
- `POST /api/auth/google` exists in Node (`src/api/routes/authRoutes.js:123`) and is called by the frontend (`frontend/src/services/auth.js:180`) but has **no Rust route** → Google sign-in 404s on the Rust backend.
- Node `POST /api/bots` and `DELETE /api/bots/:botId` (`src/api/routes/botRoutes.js`) have no Rust equivalent.

## Decisions & History
- 2026-09-24 (fix/rust-security): the authorization holes listed on this page were closed. Where Node refuses correctly, Rust answers as Node does (state 403 `NOT_IN_PARTY`, admin 401/403); where Node is lax or buggy (details and join refusals answer 500, `trigger-bot` and history unchecked), Rust refuses with 403 — the user's rule: a Node 500 on a client error is a Node bug, Rust keeps the correct 4xx. So a private join without the code is 403 `PRIVATE_PARTY`, with a wrong code 403 `INVALID_INVITE_CODE`. `/history/public` had lost Node's public-only filter and listed private games; it filters again.
- Routes and JSON shapes were ported from the Node backend in `e4f83da` (2025-12-23, "rewrite backend in Rust"); handlers carry "matching JS behavior"/"like JS" comments (`zapzap-rust/src/api/routes/auth.rs:83`, `game.rs:288`). The substring-based error mapping appears to mimic the Node error-message checks, and the mismatches date from porting messages without re-aligning the matchers.
- The `/suscribeupdate` typo is kept for compatibility with the frontend and nginx config.
