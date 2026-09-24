# Api

> Scope: every HTTP route served by the Rust backend (`zapzap-rust/src/main.rs`, `zapzap-rust/src/api/routes/*.rs`): method, path, auth, handler, failure codes; differences with the old `BACKEND_API.md` and the legacy Node routes.
> Related: [[Backend]] · [[Frontend]] · [[Bots]] · [[GameRules]] · [[Testing]]
> Updated: 2026-09-24

## Facts

### Conventions
- Router assembly: `zapzap-rust/src/api/routes/mod.rs:23-60` (under `/api`), plus `/suscribeupdate` and `/health` at the root (`zapzap-rust/src/main.rs:41-45`).
- Auth column: **JWT** = `auth_middleware` (Bearer header, bare 401 without JSON body on a missing or invalid token, or a token whose user no longer exists, `zapzap-rust/src/api/middleware/auth_middleware.rs`); **opt** = optional auth; **admin** = JWT + `admin_middleware`, which reads `is_admin` from the database (401 `AUTH_REQUIRED` / 403 `ADMIN_REQUIRED`, `{success:false, error, code}`, as Node); the handlers do not check again; **none** = public.
- Error body for auth/party/game: `{error, code, details?}` (`ErrorBody`, `zapzap-rust/src/api/error.rs`); admin/bots/stats/history use `{success:false, error}` or `{error}` without `code`.
- Party and game errors are typed: each use-case error variant maps to Node's status and `code` in one `From` impl per use case (`zapzap-rust/src/api/error.rs`). A 500 carries a generic `error` (`Failed to …`), a `<ROUTE>_ERROR` code and the cause in `details`, as on Node.
- A JSON body that does not parse — malformed, a field missing or mistyped — answers **400** with the route's missing-field code (`ApiJson`, `zapzap-rust/src/api/error.rs`), not axum's 422 plain text. A request without a JSON content type reads as `{}`, as Express does; a body over axum's 2 MB default limit answers 413 `PAYLOAD_TOO_LARGE`.
- CORS fully permissive (`zapzap-rust/src/main.rs:46`). No rate limiting.

### Root
| Method | Path | Auth | Handler | Notes |
|---|---|---|---|---|
| GET | `/health` and `/api/health` | none | `zapzap-rust/src/api/routes/health.rs:13` | `{status:"ok", version, uptime_seconds}`; uptime counts from the first health call, not process start (`health.rs:11-14`) |
| GET | `/suscribeupdate?token=` | token optional (query) | `zapzap-rust/src/api/sse.rs` | SSE; events without a party and a public party's lifecycle events to all, a game's moves and private-party events only to that party's players (a token of a deleted user names nobody). See [[Backend]] |

### Auth — `/api/auth` (`zapzap-rust/src/api/routes/auth.rs:12-17`)
| Method | Path | Auth | Handler | Success | Failures |
|---|---|---|---|---|---|
| POST | `/register` | none | `auth.rs:101` | 201 `{success, user{id,username,createdAt}, token}` | 400 `MISSING_CREDENTIALS`/`VALIDATION_ERROR`, 409 `USERNAME_EXISTS`, 500 `REGISTRATION_ERROR` |
| POST | `/login` | none | `auth.rs:177` | 200 `{success, user{id,username,isAdmin}, token}` | 400 `MISSING_CREDENTIALS`/`VALIDATION_ERROR`, 401 `INVALID_CREDENTIALS`, 500 `LOGIN_ERROR` |
| POST | `/google` | none | `auth.rs:252` | 200 `{success, user{id,username,email,isAdmin,isGoogleUser}, token, isNewUser}`; finds the user by `google_id`, else creates a password-less human with a unique username (`zapzap-rust/src/application/auth/login_with_google.rs`) | 400 `MISSING_CREDENTIAL` (`credential` absent or falsy), 401 `GOOGLE_AUTH_FAILED` (invalid/forged/expired token, wrong `aud`/`iss`, `email_verified` false, or `GOOGLE_OAUTH_CLIENT_ID` unset: `Google OAuth non configuré sur ce serveur`, as Node), 500 `GOOGLE_AUTH_ERROR` (`details` is generic; the database message is only logged). Token check in [[Backend]] § Google OAuth |

### Party — `/api/party` (`zapzap-rust/src/api/routes/mod.rs:63-124`)
| Method | Path | Auth | Handler | Failures |
|---|---|---|---|---|
| GET | `/` | opt | `zapzap-rust/src/api/routes/party.rs:348` | 500 `GET_PARTIES_ERROR`. Query `status`, `limit` (default 50, **no max**), `offset` (default 0) (`party.rs:358-359`). Only `visibility='public'` parties (`zapzap-rust/src/infrastructure/database/repositories/party_repo.rs:149`). Each item carries `isMyTurn`: true when the caller is a member, the party is playing, the round is not finished and `currentTurn` is the caller's seat (`zapzap-rust/src/application/party/list_parties.rs`); **Rust only**, Node has no such field |
| POST | `/` | JWT | `party.rs:277` | 400 `MISSING_PARTY_NAME`; 400 `VALIDATION_ERROR` for an unreadable body or a use-case validation error (Node: 500 `CREATE_PARTY_ERROR`); 500 `CREATE_PARTY_ERROR` on repository errors. Body `name`, `visibility` (default `public`), `settings{handSize=5,maxScore=100,enableGoldenScore=true,goldenScoreThreshold=100}` (`party.rs:287-295`), `botIds[]`. Emits `partyUpdate`/`partyCreated` with the new `partyId` for a public party only — a private one is not in `GET /party` (**Rust only**, Node emits nothing). Bots from `botIds` take the seats after the owner's, contiguous whatever ids are skipped or repeated |
| GET | `/:partyId` | JWT | `party.rs:389` | 404 `PARTY_NOT_FOUND`, 403 `NOT_IN_PARTY` (`User is not in this party`) for a non-member of a **private** party, so its `inviteCode` stays with its players (`zapzap-rust/src/application/party/get_party_details.rs`); Node means to refuse too but its message has no branch and answers 500 `GET_PARTY_ERROR`. Public parties: any user, as in Node |
| DELETE | `/:partyId` | JWT | `party.rs:560` | 404, 403 `NOT_AUTHORIZED` (neither owner nor only human), 409 `PARTY_PLAYING` |
| POST | `/:partyId/join` | JWT | `party.rs:440` | 404, 409 `PARTY_FULL` (8 players, `zapzap-rust/src/domain/entities/party.rs:100-101`), 409 `ALREADY_IN_PARTY` (also when a concurrent join loses on `UNIQUE(party_id, user_id)`), 409 `PARTY_STARTED` (not waiting). The joiner takes the lowest free seat (`lowest_free_seat`, `zapzap-rust/src/domain/entities/player.rs`), not `players.len()`, which collided with a seat after a leave. A **private** party needs body `inviteCode` equal to its code: without one 403 `PRIVATE_PARTY` `Party is private. Use invite code to join.`, with a wrong one 403 `INVALID_INVITE_CODE` `Invalid invite code` (`zapzap-rust/src/application/party/join_party.rs`). Node's messages; Node answers 500 `JOIN_PARTY_ERROR` (no branch in `partyRoutes.js`), a Node bug |
| POST | `/:partyId/leave` | JWT | `party.rs:482` | 404, 403 `NOT_IN_PARTY`, 409 `PARTY_PLAYING` (during a game only; a finished party can be left, as on Node). Owner leaving transfers ownership (`zapzap-rust/src/application/party/leave_party.rs:87-89`) |
| POST | `/:partyId/start` | JWT | `party.rs:517` | 404, 403 `NOT_OWNER`, 409 `PARTY_ALREADY_PLAYING` (playing: `Party is already playing`; finished: `Party has finished`), 400 `NOT_ENOUGH_PLAYERS` (3..=8 required, `zapzap-rust/src/domain/entities/party.rs:105-106`). Renumbers the seats 0..n-1 before dealing, since the game state indexes seats by position (`zapzap-rust/src/application/party/start_party.rs`) |
| POST | `/:partyId/bots` | JWT | `party.rs:595` | **Rust only.** Body `{botId}`; the owner fills the lowest free seat of a waiting party with a bot (`zapzap-rust/src/application/party/add_bot_to_party.rs`). 201 `{success, party{id,name,status}, bot{id,username,botDifficulty}, playerIndex}`, and a `partyUpdate`/`playerJoined` event with the bot as `userId`. 400 `MISSING_BOT_ID`, 404 `PARTY_NOT_FOUND`, 403 `NOT_OWNER`, 409 `PARTY_STARTED`, 404 `BOT_NOT_FOUND`, 400 `NOT_A_BOT`, 409 `ALREADY_IN_PARTY`, 409 `PARTY_FULL` |

### Game — `/api/game` (`zapzap-rust/src/api/routes/mod.rs:127-179`), all JWT
Every action answers 404 `PARTY_NOT_FOUND`, 400 `INVALID_PARTY_STATE` when the party is not playing (Node: 500 except for `nextRound`), 403 `NOT_IN_PARTY` for a non-member, 403 `NOT_YOUR_TURN`, and 500 `<ROUTE>_ERROR` on repository errors.

| Method | Path | Handler | Body | Failures |
|---|---|---|---|---|
| GET | `/:partyId/state` | `zapzap-rust/src/api/routes/game.rs:311` | — | 404, 403 `NOT_IN_PARTY` for a non-member, as Node (`zapzap-rust/src/application/game/get_game_state.rs`), 500. Spawns a bot trigger (`game.rs:383`). `eliminatedPlayers` computed as score > 100 hard-coded (`game.rs:343-349`), ignoring `maxScore`; response below |
| POST | `/:partyId/selectHandSize` | `game.rs:412` | `{handSize}` (4-7, 4-10 in golden score, `zapzap-rust/src/application/game/select_hand_size.rs`) | 400 `INVALID_ACTION_STATE` (checked first, as Node), 403 `NOT_YOUR_TURN`, 400 `INVALID_HAND_SIZE` (also for an unreadable body) |
| POST | `/:partyId/play` | `game.rs:452` | `{cardIds:[u8]}` | 400 `MISSING_CARDS` (empty, missing, not an array or unreadable), 400 `INVALID_ACTION_STATE`, 400 `INVALID_CARDS` (a card not in hand, or an id that is no card id such as `300`, `-1`, `"a"` — checked before the turn, where Node finds it after; or a card named twice, `[c, c]`, which Node accepts and plays), 400 `INVALID_PLAY` (not a valid combination; Node: 500) |
| POST | `/:partyId/draw` | `game.rs:513` | `{source:"deck"\|"played", cardId?}`; no `cardId` from `played` takes the top card, as Node | 400 `INVALID_SOURCE` (also for an unreadable body), 400 `INVALID_ACTION_STATE`, 400 `DECK_EMPTY` (deck and discard empty; Node: 500), 400 `NO_CARDS_AVAILABLE`, 400 `CARD_NOT_AVAILABLE` |
| POST | `/:partyId/zapzap` | `game.rs:562` | — | 400 `INVALID_ACTION_STATE`, 400 `HAND_TOO_HIGH`; response below |
| POST | `/:partyId/nextRound` | `game.rs:663` | — | 404, 403 `NOT_IN_PARTY` for a non-member (checked in the handler, `require_party_member`, `zapzap-rust/src/api/access.rs`; `NextRound` itself still never reads `input.user_id`), 400 `INVALID_PARTY_STATE`/`ROUND_NOT_FINISHED`; response below |
| POST | `/:partyId/trigger-bot` | `game.rs` | — | 404 `PARTY_NOT_FOUND`, 403 `NOT_IN_PARTY` for a non-member (`require_party_member`; Node has no check here). Runs the party's bot loop through the per-party lock (`run_bot_turns_now`, [[Backend]] "Bot triggering"); `{success, message: "Bot trigger completed. Actions taken: n"}`, 500 `BOT_ACTION_ERROR` when a bot action or a repository call fails |

#### zapzap response (Node's contract, plus three Rust-only keys)
Node's route sends exactly `{success, zapzapSuccess, counteracted, counteractedBy, scores, handPoints, callerPoints}` (`src/api/routes/gameRoutes.js:392-400`; its use case computes `gameFinished`/`winner` but the route drops them). Rust sends those seven keys with Node's meanings, plus `roundScores`, `gameFinished?` and `winner?`, **Rust-only additions**:
`{success, zapzapSuccess, counteracted, counteractedBy, scores, roundScores, handPoints, callerPoints, gameFinished?, winner?}` (`ZapZapResponse`, `game.rs`; values from `zapzap-rust/src/application/game/call_zapzap.rs`):
- `scores`: **running totals after the round**, an object keyed by player index for every seat (`{"0": 10, "1": 26, "2": 36}`) — Node's `scores` (`src/use-cases/game/CallZapZap.js:121-125`, `:496`), the same values as `/state`'s `gameState.scores`.
- `roundScores` (Rust only): this round's points, keyed by player index for the active players — the key `/state` uses for the same values.
- `handPoints`: each active player's hand value with Joker = 25, keyed by player index (Node's `handPointsMap`).
- `callerPoints`: the caller's hand value with Joker = 0. `counteractedBy`: the counteracting player's index, or `null`.
- `gameFinished: true` and `winner{userId, playerIndex, score}` (Rust only) only when the call ends the game.
- Pinned by `test_zapzap_scores_are_running_totals` and `test_zapzap_counteracted_scores` (`zapzap-rust/tests/api_tests.rs`) and, on Node, `should answer scores as running totals and handPoints per player` (`tests/unit/use-cases/game/CallZapZap.test.js`).

#### state response (Node's contract, `src/use-cases/game/GetGameState.js`)
`{success, party{id, name, status, currentRoundId}, players[{playerIndex, userId, username}], round{id, roundNumber, status}, gameState}` (`GameStateResponse`, `game.rs`). `gameState` always carries `wasCounterActed` and `gameFinished` (booleans), besides the round-end keys filled once `currentAction` is `finished`.
- `gameState.lastAction` is built per move, with Node's fields (`GameState::get_last_action_json`, `zapzap-rust/src/domain/value_objects/game_state.rs`; written by `game_service.rs` and `select_hand_size.rs`): always `{type, playerIndex}`, plus `handSize` (selectHandSize, no `timestamp` as on Node), `cardIds` (play), `source`, `deckReshuffled` and — from the played pile only — `cardId` (draw), `wasCounterActed`, `counterActedByPlayerIndex`, `callerHandPoints`, `roundScores` (zapzap), and `timestamp` (Unix ms). `null` before the round's first move.
- Deliberate differences: a deck draw's `cardId`, which Node sends to every player (the drawn card, a leak: `2026-09-22-node-play-draw-leak-all-hands`), is neither sent nor stored; `gameState.counterActedByPlayerIndex` is `0` when seat 0 counteracts, where Node's `|| null` answers `null`.
- The stored game state writes the same `lastAction`; `GameState::from_json` reads Node's (dropping a deck draw's `cardId`, taking the zapzap outcome from `lastAction` when the top-level keys are missing) and the older Rust `{type, playerIndex, wasCounterActed, callerHandPoints}`.
- Pinned by `test_state_sends_nodes_always_present_keys`, `test_state_last_action_of_select_play_and_draw`, `test_state_last_action_of_a_reshuffling_draw`, `test_state_last_action_of_a_zapzap` (`zapzap-rust/tests/api_tests.rs`) and the `test_node_*`/`test_older_rust_*` unit tests of `game_state.rs`.

#### nextRound response (Node's contract, `src/api/routes/gameRoutes.js`, `src/use-cases/game/NextRound.js`)
`NextRoundResponse`, `game.rs`:
- A new round: `{success, gameFinished: false, round{id, roundNumber, status}, startingPlayer, scores, eliminatedPlayers}`; `scores` are the running totals keyed by player index (`{"0": 10, "1": 120}`), as zapzap's.
- The end of the game: `{success, gameFinished: true, winner{userId, playerIndex, score}, finalScores, eliminatedPlayers}`, `finalScores` keyed like `scores`.
- `eliminatedPlayers`: `[{userId, playerIndex, score}]` by seat — the players past 100, and at the end of the game every seat but the winner's (Node adds the golden score's loser).
- Pinned by `test_next_round_answers_nodes_keys` and `test_next_round_at_the_end_of_the_game_answers_nodes_keys`.

### Stats — `/api/stats` (`zapzap-rust/src/api/routes/mod.rs:182-195`)
| Method | Path | Auth | Handler | Notes |
|---|---|---|---|---|
| GET | `/me` | JWT | `zapzap-rust/src/api/routes/stats.rs:174` | 404 user not found |
| GET | `/user/:userId` | none | `stats.rs:182` | public stats for any id |
| GET | `/leaderboard` | none | `stats.rs:304` | `minGames` default 5, `limit` 50, `offset` 0 (`stats.rs:21-36`); humans only, by win rate then wins, as Node. Node's body: `{success, leaderboard[{rank, userId, username, gamesPlayed, wins, winRate, averageScore}], criteria{minGames, sortBy:"winRate"}, pagination{limit, offset, hasMore}}` — `hasMore` is "the page is full", no total |
| GET | `/bots` | none | `stats.rs:378` | per-difficulty bot stats |

### History — `/api/history` (`zapzap-rust/src/api/routes/mod.rs:198-223`)
| Method | Path | Auth | Handler | Notes |
|---|---|---|---|---|
| GET | `/` and `/my-games` | JWT | `zapzap-rust/src/api/routes/history.rs:259` | same handler; `limit` default 20 (`history.rs:28-30`). Node's body: `{success, games[{id, partyId, partyName, winnerUserId, winnerUsername, winnerFinalScore, totalRounds, wasGoldenScore, playerCount, finishedAt, visibility, userPlacement, userScore}], pagination{limit, offset, hasMore}}` |
| GET | `/public` | none | `history.rs:281` | finished public games only (`visibility = 'public'`, as Node, `src/infrastructure/database/sqlite/repositories/PartyRepository.js:760`); the same body without `visibility`, `userPlacement`, `userScore` |
| GET | `/:partyId` | JWT | `history.rs:301` | 404 `Game not found`; 403 `{error:"Access denied. Party is private."}` for a **private** game to a user in neither `party_players` nor `player_game_results`. Node checks nothing here; public games stay readable by any signed-in user |

### Admin — `/api/admin` (`create_admin_router`, `zapzap-rust/src/api/routes/mod.rs`), all admin: 401 without a token, 403 `ADMIN_REQUIRED` for a non-admin
| Method | Path | Handler | Notes |
|---|---|---|---|
| GET | `/users` | `zapzap-rust/src/api/routes/admin.rs:244` | humans only, `limit` 50 (`admin.rs:38-40`) |
| DELETE | `/users/:userId` | `admin.rs:354` | `{success, deletedUserId, deletedUsername}`; 400 self-delete (`admin.rs:359`) or target is admin (`admin.rs:394`, Node deletes it: a `node-bug` divergence), 404 |
| POST | `/users/:userId/admin` | `admin.rs:428` | body `{isAdmin}` → `{success, userId, username, isAdmin}`; 404 |
| GET | `/parties` | `admin.rs:494` | `status`, `limit`, `offset` → `parties[{id, name, ownerId, ownerUsername, inviteCode, visibility, status, settings, currentRoundId, playerCount, createdAt, updatedAt}]`, `pagination{total, limit, offset}`; `settings` is the stored settings **JSON-encoded as a string**, as Node sends it (the React admin `JSON.parse`s it) |
| POST | `/parties/:partyId/stop` | `admin.rs:579` | `{success, partyId, partyName, stopped:true}`; 404, 400 already finished (`admin.rs:612`) |
| DELETE | `/parties/:partyId` | `admin.rs:642` | `{success, partyId, partyName, deleted:true}`; 404 |
| GET | `/statistics` | `admin.rs:708` | counts |

### Misc
| Method | Path | Auth | Handler | Notes |
|---|---|---|---|---|
| GET | `/api/bots?difficulty=` | none | `zapzap-rust/src/api/routes/bots.rs:52` | valid: easy, medium, hard, hard_vince, ml, drl, llm, thibot (`bots.rs:56-65`); 400 otherwise |
| POST | `/api/bots` | admin (`auth_middleware` + `admin_middleware`, `zapzap-rust/src/api/routes/mod.rs:32-56`): bare 401 without a token, 403 `ADMIN_REQUIRED` for a non-admin, as `/api/admin` | `bots.rs:182` | body `{username, difficulty}`; 201 `{success, bot}` with `bot` shaped as Node's `toPublicObject()` (`id, username, userType, botDifficulty, isAdmin, lastLoginAt, totalPlayTimeSeconds, email, isGoogleUser, createdAt, updatedAt`). Every failure is 400 `{success:false, error}` with Node's message: `Username is required`, `Difficulty must be one of: easy, medium, hard, hard_vince, ml, drl, llm` (`thibot` is not creatable, as in Node), `Username "X" already exists`, the username format messages; a name taken by a concurrent request between the lookup and the save also answers `already exists` (`zapzap-rust/src/application/bot/create_bot.rs`) |
| DELETE | `/api/bots/:botId` | admin (as above) | `bots.rs:207` | 200 `{success:true, deletedBotId}`; 400 `Bot not found` (unknown id, as Node's `DeleteBot`), 400 `User is not a bot - cannot delete human users via this endpoint`, 400 `Bot is in an active party - cannot delete it` (seated in a `waiting` or `playing` party; Node has no such check), 400 `Failed to delete bot` when a concurrent delete removed it first (`zapzap-rust/src/application/bot/delete_bot.rs`) |
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
| GET `/party/:id` | non-member of a private party (`Access denied. Party is private.` has no branch) | 500 `GET_PARTY_ERROR` | 403 `NOT_IN_PARTY` |
| join | private party without its invite code / with a wrong one (no branch) | 500 `JOIN_PARTY_ERROR` | 403 `PRIVATE_PARTY` / `INVALID_INVITE_CODE` *new* |

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

### Node vs Rust: the parity suite
- Every difference between the two backends' answers that the parity suite finds is listed,
  with its class and wip entry, in `tests/parity/divergences.json`: `node-bug` (Node is
  wrong and Rust rightly differs) or `pending` (Rust must still change). The CI job
  `parity` fails on an unlisted difference and on a listed one that no longer occurs, so
  that file is the up-to-date list; the prose below is a code read and may lag it.
  Suite and rules: [[Testing]].

### Missing vs legacy Node / frontend
- `POST /api/auth/google` and `POST /api/bots` / `DELETE /api/bots/:botId` were missing until 2026-09-24; they are ported (see Auth and Misc above).
- Deliberate difference: Node serves the two bot mutations **without any authentication** (`src/api/routes/botRoutes.js`, mounted without middleware); Rust requires an admin.

## Decisions & History
- 2026-09-24 (fix/rust-game-state-next-round): `GET /state` and `POST /nextRound` took Node's shapes. Rust's `players[].userType`/`botDifficulty` on `/state` were dropped rather than kept as additions: neither client reads them there (React's `PartyLobby` reads `userType` from `/party/:id`; Flutter defaults it). A played-pile draw keeps its `cardId`, since that card lay on the table and React names it; only the deck draw's is withheld. nextRound's `winner` became Node's object and `finalScores` a map too, beyond the parity items, so that one client code path reads both backends.
- 2026-09-24 (fix/rust-history-admin-contract): the history, leaderboard and admin bodies took Node's keys (`src/use-cases/history/GetGameHistory.js`, `stats/GetLeaderboard.js`, `admin/*`). Rust's own `games[].roundsPlayed` and top-level `total` were dropped rather than kept as additions: no client needs them (Flutter reads `totalRounds` first and never shows a history or leaderboard total; React reads Node's keys).
- 2026-09-24 (fix/rust-security): the authorization holes listed on this page were closed. Where Node refuses correctly, Rust answers as Node does (state 403 `NOT_IN_PARTY`, admin 401/403); where Node is lax or buggy (details and join refusals answer 500, `trigger-bot` and history unchecked), Rust refuses with 403 — the user's rule: a Node 500 on a client error is a Node bug, Rust keeps the correct 4xx. So a private join without the code is 403 `PRIVATE_PARTY`, with a wrong code 403 `INVALID_INVITE_CODE`. `/history/public` had lost Node's public-only filter and listed private games; it filters again.
- 2026-09-24 (fix/rust-api-errors-contract): the substring matching of use-case error messages was replaced by typed errors (`zapzap-rust/src/api/error.rs`), after six of its branches were found answering 500 for client errors (join already-in-party and not-waiting, start, delete, leave, and `NOT_IN_PARTY` on every game action). The zapzap `scores` were aligned on Node's meaning (running totals, user decision), with round points under `roundScores`; `partyCreated`, `isMyTurn` and `POST /party/:id/bots` were added on the Rust side first, Node and the clients following in their own changes.
- Routes and JSON shapes were ported from the Node backend in `e4f83da` (2025-12-23, "rewrite backend in Rust"); handlers carry "matching JS behavior"/"like JS" comments (`zapzap-rust/src/api/routes/auth.rs:105`, `game.rs:311`). The substring-based error mapping appears to mimic the Node error-message checks, and the mismatches date from porting messages without re-aligning the matchers.
- The `/suscribeupdate` typo is kept for compatibility with the frontend and nginx config.
- 2026-09-24 (feat/rust-google-and-bot-admin): `POST /api/auth/google`, `POST /api/bots` and `DELETE /api/bots/:botId` ported from Node with Node's bodies and messages. The bot mutations were made admin-only because Node leaving them open lets anyone create or delete bot accounts; no client calls them (the React and Flutter clients only list bots).
