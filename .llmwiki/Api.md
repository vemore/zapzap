# Api

> Scope: every HTTP route served by the Rust backend (`zapzap-rust/src/main.rs`, `zapzap-rust/src/api/routes/*.rs`): method, path, auth, handler, failure codes; differences with the old `BACKEND_API.md` and the legacy Node routes.
> Related: [[Backend]] · [[Frontend]] · [[Bots]] · [[GameRules]] · [[Testing]]
> Updated: 2026-09-24

## Facts

### Conventions
- Router assembly: `zapzap-rust/src/api/routes/mod.rs:23-35` (under `/api`), plus `/suscribeupdate` and `/health` at the root (`zapzap-rust/src/main.rs:41-45`).
- Auth column: **JWT** = `auth_middleware` (Bearer header, bare 401 without JSON body on missing/invalid token, `zapzap-rust/src/api/middleware/auth_middleware.rs:28-37`); **opt** = optional auth; **admin** = JWT + `claims.is_admin` checked in the handler (403 `Admin access required`); **none** = public.
- Error body for auth/party/game: `{error, code, details?}` (`ErrorBody`, `zapzap-rust/src/api/error.rs`); admin/bots/stats/history use `{success:false, error}` or `{error}` without `code`.
- Party and game errors are typed: each use-case error variant maps to Node's status and `code` in one `From` impl per use case (`zapzap-rust/src/api/error.rs`). A 500 carries a generic `error` (`Failed to …`), a `<ROUTE>_ERROR` code and the cause in `details`, as on Node.
- A JSON body that does not parse — malformed, a field missing or mistyped — answers **400** with the route's missing-field code (`ApiJson`, `zapzap-rust/src/api/error.rs`), not axum's 422 plain text. A request without a JSON content type reads as `{}`, as Express does; a body over axum's 2 MB default limit answers 413 `PAYLOAD_TOO_LARGE`.
- CORS fully permissive (`zapzap-rust/src/main.rs:46`). No rate limiting.

### Root
| Method | Path | Auth | Handler | Notes |
|---|---|---|---|---|
| GET | `/health` and `/api/health` | none | `zapzap-rust/src/api/routes/health.rs:13` | `{status:"ok", version, uptime_seconds}`; uptime counts from the first health call, not process start (`health.rs:11-14`) |
| GET | `/suscribeupdate?token=` | token optional (query) | `zapzap-rust/src/api/sse.rs:18` | SSE, see [[Backend]] |

### Auth — `/api/auth` (`zapzap-rust/src/api/routes/auth.rs:10-14`)
| Method | Path | Auth | Handler | Success | Failures |
|---|---|---|---|---|---|
| POST | `/register` | none | `auth.rs:79` | 201 `{success, user{id,username,createdAt}, token}` | 400 `MISSING_CREDENTIALS`/`VALIDATION_ERROR`, 409 `USERNAME_EXISTS`, 500 `REGISTRATION_ERROR` |
| POST | `/login` | none | `auth.rs:155` | 200 `{success, user{id,username,isAdmin}, token}` | 400 `MISSING_CREDENTIALS`/`VALIDATION_ERROR`, 401 `INVALID_CREDENTIALS`, 500 `LOGIN_ERROR` |

### Party — `/api/party` (`zapzap-rust/src/api/routes/mod.rs:38-99`)
| Method | Path | Auth | Handler | Failures |
|---|---|---|---|---|
| GET | `/` | opt | `zapzap-rust/src/api/routes/party.rs:348` | 500 `GET_PARTIES_ERROR`. Query `status`, `limit` (default 50, **no max**), `offset` (default 0) (`party.rs:358-359`). Only `visibility='public'` parties (`zapzap-rust/src/infrastructure/database/repositories/party_repo.rs:149`). Each item carries `isMyTurn`: true when the caller is a member, the party is playing, the round is not finished and `currentTurn` is the caller's seat (`zapzap-rust/src/application/party/list_parties.rs`); **Rust only**, Node has no such field |
| POST | `/` | JWT | `party.rs:277` | 400 `MISSING_PARTY_NAME`; 400 `VALIDATION_ERROR` for an unreadable body or a use-case validation error (Node: 500 `CREATE_PARTY_ERROR`); 500 `CREATE_PARTY_ERROR` on repository errors. Body `name`, `visibility` (default `public`), `settings{handSize=5,maxScore=100,enableGoldenScore=true,goldenScoreThreshold=100}` (`party.rs:287-295`), `botIds[]`. Emits `partyUpdate`/`partyCreated` with the new `partyId` for a public party only — a private one is not in `GET /party` (**Rust only**, Node emits nothing). Bots from `botIds` take the seats after the owner's, contiguous whatever ids are skipped or repeated |
| GET | `/:partyId` | JWT | `party.rs:389` | 404 `PARTY_NOT_FOUND`, 500. **No membership check**: any user gets details incl. `inviteCode` of private parties (`zapzap-rust/src/application/party/get_party_details.rs:44-100`) |
| DELETE | `/:partyId` | JWT | `party.rs:560` | 404, 403 `NOT_AUTHORIZED` (neither owner nor only human), 409 `PARTY_PLAYING` |
| POST | `/:partyId/join` | JWT | `party.rs:440` | 404, 409 `PARTY_FULL` (8 players, `zapzap-rust/src/domain/entities/party.rs:100-101`), 409 `ALREADY_IN_PARTY` (also when a concurrent join loses on `UNIQUE(party_id, user_id)`), 409 `PARTY_STARTED` (not waiting). The joiner takes the lowest free seat (`lowest_free_seat`, `zapzap-rust/src/domain/entities/player.rs`), not `players.len()`, which collided with a seat after a leave. Body `inviteCode` is **ignored** by the use case |
| POST | `/:partyId/leave` | JWT | `party.rs:482` | 404, 403 `NOT_IN_PARTY`, 409 `PARTY_PLAYING` (during a game only; a finished party can be left, as on Node). Owner leaving transfers ownership (`zapzap-rust/src/application/party/leave_party.rs:87-89`) |
| POST | `/:partyId/start` | JWT | `party.rs:517` | 404, 403 `NOT_OWNER`, 409 `PARTY_ALREADY_PLAYING` (playing: `Party is already playing`; finished: `Party has finished`), 400 `NOT_ENOUGH_PLAYERS` (3..=8 required, `zapzap-rust/src/domain/entities/party.rs:105-106`). Renumbers the seats 0..n-1 before dealing, since the game state indexes seats by position (`zapzap-rust/src/application/party/start_party.rs`) |
| POST | `/:partyId/bots` | JWT | `party.rs:595` | **Rust only.** Body `{botId}`; the owner fills the lowest free seat of a waiting party with a bot (`zapzap-rust/src/application/party/add_bot_to_party.rs`). 201 `{success, party{id,name,status}, bot{id,username,botDifficulty}, playerIndex}`, and a `partyUpdate`/`playerJoined` event with the bot as `userId`. 400 `MISSING_BOT_ID`, 404 `PARTY_NOT_FOUND`, 403 `NOT_OWNER`, 409 `PARTY_STARTED`, 404 `BOT_NOT_FOUND`, 400 `NOT_A_BOT`, 409 `ALREADY_IN_PARTY`, 409 `PARTY_FULL` |

### Game — `/api/game` (`zapzap-rust/src/api/routes/mod.rs:102-154`), all JWT
Every action answers 404 `PARTY_NOT_FOUND`, 400 `INVALID_PARTY_STATE` when the party is not playing (Node: 500 except for `nextRound`), 403 `NOT_IN_PARTY` for a non-member, 403 `NOT_YOUR_TURN`, and 500 `<ROUTE>_ERROR` on repository errors.

| Method | Path | Handler | Body | Failures |
|---|---|---|---|---|
| GET | `/:partyId/state` | `zapzap-rust/src/api/routes/game.rs:294` | — | 404, 500. No membership check: a non-member gets an empty `playerHand` but all public state and, once a round is finished, `allHands`. Spawns a bot trigger (`game.rs:368`). `eliminatedPlayers` computed as score > 100 hard-coded (`game.rs:325-331`), ignoring `maxScore` |
| POST | `/:partyId/selectHandSize` | `game.rs:404` | `{handSize}` (4-7, 4-10 in golden score, `zapzap-rust/src/application/game/select_hand_size.rs`) | 400 `INVALID_ACTION_STATE` (checked first, as Node), 403 `NOT_YOUR_TURN`, 400 `INVALID_HAND_SIZE` (also for an unreadable body) |
| POST | `/:partyId/play` | `game.rs:451` | `{cardIds:[u8]}` | 400 `MISSING_CARDS` (empty, missing, not an array or unreadable), 400 `INVALID_ACTION_STATE`, 400 `INVALID_CARDS` (a card not in hand, or an id that is no card id such as `300`, `-1`, `"a"` — checked before the turn, where Node finds it after), 400 `INVALID_PLAY` (not a valid combination; Node: 500) |
| POST | `/:partyId/draw` | `game.rs:519` | `{source:"deck"\|"played", cardId?}`; no `cardId` from `played` takes the top card, as Node | 400 `INVALID_SOURCE` (also for an unreadable body), 400 `INVALID_ACTION_STATE`, 400 `DECK_EMPTY` (deck and discard empty; Node: 500), 400 `NO_CARDS_AVAILABLE`, 400 `CARD_NOT_AVAILABLE` |
| POST | `/:partyId/zapzap` | `game.rs:575` | — | 400 `INVALID_ACTION_STATE`, 400 `HAND_TOO_HIGH`; response below |
| POST | `/:partyId/nextRound` | `game.rs:676` | — | 404, 400 `INVALID_PARTY_STATE`/`ROUND_NOT_FINISHED`; **any authenticated user** can advance any party: `NextRound` never reads `input.user_id` and has no `NotInParty` error (`zapzap-rust/src/application/game/next_round.rs:238-246`) |
| POST | `/:partyId/trigger-bot` | `game.rs:757` | — | 500 on repo errors. Handler takes no `Claims`: any authenticated user can drive bots in any party |

#### zapzap response (Node's contract, plus three Rust-only keys)
Node's route sends exactly `{success, zapzapSuccess, counteracted, counteractedBy, scores, handPoints, callerPoints}` (`src/api/routes/gameRoutes.js:392-400`; its use case computes `gameFinished`/`winner` but the route drops them). Rust sends those seven keys with Node's meanings, plus `roundScores`, `gameFinished?` and `winner?`, **Rust-only additions**:
`{success, zapzapSuccess, counteracted, counteractedBy, scores, roundScores, handPoints, callerPoints, gameFinished?, winner?}` (`ZapZapResponse`, `game.rs`; values from `zapzap-rust/src/application/game/call_zapzap.rs`):
- `scores`: **running totals after the round**, an object keyed by player index for every seat (`{"0": 10, "1": 26, "2": 36}`) — Node's `scores` (`src/use-cases/game/CallZapZap.js:121-125`, `:496`), the same values as `/state`'s `gameState.scores`.
- `roundScores` (Rust only): this round's points, keyed by player index for the active players — the key `/state` uses for the same values.
- `handPoints`: each active player's hand value with Joker = 25, keyed by player index (Node's `handPointsMap`).
- `callerPoints`: the caller's hand value with Joker = 0. `counteractedBy`: the counteracting player's index, or `null`.
- `gameFinished: true` and `winner{userId, playerIndex, score}` (Rust only) only when the call ends the game.
- Pinned by `test_zapzap_scores_are_running_totals` and `test_zapzap_counteracted_scores` (`zapzap-rust/tests/api_tests.rs`) and, on Node, `should answer scores as running totals and handPoints per player` (`tests/unit/use-cases/game/CallZapZap.test.js`).

### Stats — `/api/stats` (`zapzap-rust/src/api/routes/mod.rs:157-170`)
| Method | Path | Auth | Handler | Notes |
|---|---|---|---|---|
| GET | `/me` | JWT | `zapzap-rust/src/api/routes/stats.rs:174` | 404 user not found |
| GET | `/user/:userId` | none | `stats.rs:182` | public stats for any id |
| GET | `/leaderboard` | none | `stats.rs:284` | `minGames` default 5, `limit` 50, `offset` 0 (`stats.rs:21-36`); humans only |
| GET | `/bots` | none | `stats.rs:370` | per-difficulty bot stats |

### History — `/api/history` (`zapzap-rust/src/api/routes/mod.rs:173-198`)
| Method | Path | Auth | Handler | Notes |
|---|---|---|---|---|
| GET | `/` and `/my-games` | JWT | `zapzap-rust/src/api/routes/history.rs:164` | same handler; `limit` default 20 (`history.rs:28-30`) |
| GET | `/public` | none | `history.rs:271` | finished public games |
| GET | `/:partyId` | JWT | `history.rs:343` | 404 `Game not found`; `_claims` unused, `visibility` selected but not enforced — private game details readable by any user |

### Admin — `/api/admin` (`zapzap-rust/src/api/routes/mod.rs:201-253`), all admin
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

### Where Rust answers a 4xx and Node a 500
Node is the reference for statuses and codes, except where it answers 500 for a client error; there Rust keeps a 4xx (codes Node has no equivalent for are marked *new*):
| Route | Case | Node | Rust |
|---|---|---|---|
| POST `/party` | validation error (short name, bad bot id…) or unreadable body | 500 `CREATE_PARTY_ERROR` | 400 `VALIDATION_ERROR` *new* |
| join | already in the party (`User is already in this party` misses the `already in party` match, `src/api/routes/partyRoutes.js`) | 500 | 409 `ALREADY_IN_PARTY` |
| join | party not waiting (`Cannot join finished party`; Node lets a playing party be joined) | 500 | 409 `PARTY_STARTED` |
| leave | during a game | 500 | 409 `PARTY_PLAYING` |
| start | not enough players (Node: `At least 2 players`, Rust requires 3) | 500 | 400 `NOT_ENOUGH_PLAYERS` *new* |
| start | party finished (`Party has finished`, the message kept) | 500 | 409 `PARTY_ALREADY_PLAYING` |
| selectHandSize, play, draw, zapzap | party not playing | 500 | 400 `INVALID_PARTY_STATE` (Node's `nextRound` code) |
| play | invalid combination (message lacks `Must play at least 2 cards`) | 500 | 400 `INVALID_PLAY` |
| draw | deck and discard empty (`Deck is empty and no cards to reshuffle` ≠ `Deck is empty`) | 500 | 400 `DECK_EMPTY` |
| draw | wrong phase (`Cannot draw at this time…` ≠ `Current action is not DRAW`) | 500 | 400 `INVALID_ACTION_STATE` |
| any JSON route | malformed JSON (Express error handler) | 500 `INTERNAL_ERROR` | 400, route's code |

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
- 2026-09-24 (fix/rust-api-errors-contract): the substring matching of use-case error messages was replaced by typed errors (`zapzap-rust/src/api/error.rs`), after six of its branches were found answering 500 for client errors (join already-in-party and not-waiting, start, delete, leave, and `NOT_IN_PARTY` on every game action). The zapzap `scores` were aligned on Node's meaning (running totals, user decision), with round points under `roundScores`; `partyCreated`, `isMyTurn` and `POST /party/:id/bots` were added on the Rust side first, Node and the clients following in their own changes.
- Routes and JSON shapes were ported from the Node backend in `e4f83da` (2025-12-23, "rewrite backend in Rust"); handlers carry "matching JS behavior"/"like JS" comments (`zapzap-rust/src/api/routes/auth.rs:83`, `game.rs:311`). The substring-based error mapping appears to mimic the Node error-message checks, and the mismatches date from porting messages without re-aligning the matchers.
- The `/suscribeupdate` typo is kept for compatibility with the frontend and nginx config.
