# Frontend

> Scope: the React + Vite single-page client in `frontend/` — structure, routing, API and SSE clients, Google sign-in, build, tests, image.
> Related: [[Architecture]] · [[Api]] · [[Backend]] · [[Testing]]
> Updated: 2026-09-28

## Facts

### Stack
- React 19 (`react` ^19.2.1), React Router 7 (`react-router-dom` ^7.9.5), axios ^1.13.2, framer-motion, lucide-react, Tailwind 3 — `frontend/package.json:15-43`.
- Vite 7 (`vite` ^7.2.6) with `@vitejs/plugin-react` — `frontend/package.json:31,42`, `frontend/vite.config.js:6`.
- Not vanilla JS: the root `CLAUDE.md` and root `README.md` ("vanilla JavaScript") describe the pre-React era; `frontend/README.md` is the untouched Vite template.
- Card faces are drawn by the `cardmeister` web component loaded as a global script: `frontend/index.html:9` (`/elements.cardmeister.full.js`, shipped in `frontend/public/`). `frontend/src/utils/cardAdapter.js:2` converts ZapZap numeric ids (0-53, see [[GameRules]]) to cardmeister `cid`. `deck-of-cards` is still a dependency (`frontend/package.json:20`) but no source file imports it.
- Jokers are not cardmeister's: `PlayingCard.jsx` shows `/joker-red.svg` or `/joker-black.svg` (`frontend/public/`) in an `<img>` — David Bellot's LGPL jokers, the same files as the Flutter client's ([[FlutterGameUi]]); licence in `frontend/THIRD_PARTY.md`.
- Several test-only packages sit in `dependencies` (`@testing-library/*`, `jsdom`, `vitest`) — `frontend/package.json:17-18,22,25`.

### Scripts (`frontend/package.json:6-14`)
| Script | Command |
|---|---|
| dev | `vite --host` (port 5173) |
| build | `vite build` → `dist/` |
| lint | `eslint .` |
| test | `vitest` (watch); `vitest run` for one shot |
| test:coverage | `vitest --coverage` |

### Source layout (`frontend/src/`)
| Path | Role |
|---|---|
| `main.jsx` | `createRoot` + `StrictMode` (`main.jsx:6`) |
| `App.jsx` | router, `AuthProvider`, optional `GoogleOAuthProvider` |
| `contexts/AuthContext.jsx` | `user`, `setUser`, `isAuthenticated`, `logout`; user restored from localStorage on mount (`AuthContext.jsx:10-17`) |
| `services/api.js` | axios instance + token helpers |
| `services/auth.js` | login/register/Google login, `deleteAccount` (DELETE `/auth/me`, then the session is cleared; a refusal throws an Error carrying the backend's `code`), client-side validation |
| `services/sse.js` | `sseUrl()`: the `/suscribeupdate?token=` URL every SSE stream opens |
| `services/party.js` | bot levels, `/bots`, add-bot and fill-and-start calls; `TURN_TIME_LIMITS`, `turnTimeLimitLabel`, `EJECTED_MESSAGE` (§ Turn timer) |
| `hooks/useSSE.js` | EventSource hook |
| `hooks/useTurnCountdown.js` | the turn clock of a game state and its ticking countdown (§ Turn timer) |
| `components/Auth/` | Login, Register, ProtectedRoute, GoogleLoginButton, DeleteAccount |
| `components/Party/` | PartyList, CreateParty, PartyLobby, ConnectedPlayers |
| `components/Game/` | GameBoard (583 lines) and card/table widgets, HandSizeSelector, RoundEnd, TurnTimer |
| `components/History/`, `components/Stats/` | game history, statistics/leaderboard |
| `components/Admin/` | AdminRoute, AdminLayout (renders `<Outlet />`, `AdminLayout.jsx:69`), users/parties/statistics |
| `utils/` | `cards.js`, `scoring.js`, `validation.js` (client-side copies of the rules), `cardAdapter.js`, `playerName.js` (« Joueur supprimé » for a `deleted-` user id, used by GameHistory and GameDetails) |
| `test/setup.js`, `**/__tests__/` | vitest setup and tests |

### Routing (`frontend/src/App.jsx:33-115`)
| Path | Component | Guard |
|---|---|---|
| `/login`, `/register` | Login, Register | public |
| `/parties`, `/create-party` | PartyList, CreateParty | ProtectedRoute |
| `/party/:partyId` | PartyLobby | ProtectedRoute |
| `/game/:partyId` | GameBoard | ProtectedRoute |
| `/history`, `/history/:partyId` | GameHistory, GameDetails | ProtectedRoute |
| `/stats` | Statistics | ProtectedRoute |
| `/account/delete` | DeleteAccount: the warning, a password field (or Google's button for a Google account, `user.isGoogleUser`), then back to `/login` with "Ton compte a été supprimé." Linked from the PartyList header ("Delete account"); also the web deletion URL Google Play asks for, `https://zapzap.ombivince.synology.me/account/delete` | ProtectedRoute |
| `/admin` → `users`, `parties`, `statistics` (index redirects to `/admin/users`) | AdminLayout + children | AdminRoute |
| `/`, `*` | redirect to `/login` | — |
- `ProtectedRoute` only checks that a non-empty `token` exists in localStorage (`components/Auth/ProtectedRoute.jsx`, `services/auth.js` `isAuthenticated`); no expiry check. Signed out, it redirects to `/login` with `state.from` (the path asked for, its query string and hash included), and Login and GoogleLoginButton go back there after signing in (else `/parties`), so a link to a protected page works from outside the app.
- `AdminRoute` additionally requires `user.isAdmin` from the stored user object, else redirects to `/parties` (`components/Admin/AdminRoute.jsx:26`). This is cosmetic: the backend must enforce admin rights (see [[Api]]).

### API client (`frontend/src/services/api.js`)
- axios `baseURL: '/api'`, `timeout: 10000` — `api.js:4-10`. Always relative: works behind the proxy (`nginx/nginx.conf` `/api/`) and in dev via the Vite proxy.
- Request interceptor adds `Authorization: Bearer <localStorage.token>` — `api.js:13-24`.
- On 401 it clears `token` and `user`, but the redirect to `/login` is commented out (`api.js:34-38`): the user stays on a page whose calls keep failing until a navigation hits `ProtectedRoute`.
- Endpoints called (all exist in the Rust router): auth `login`/`register`/`google`, DELETE `/auth/me` with `{password}` or `{credential}` (`services/auth.js`); `/party`, `/party/:id{,/join,/leave,/start}`, DELETE `/party/:id` (`PartyList.jsx:21,33`, `PartyLobby.jsx`); `/bots`, POST `/party/:id/bots` and `/party/:id/fill-and-start` (`services/party.js`, from `PartyLobby.jsx`); `/game/:id/{state,play,draw,zapzap,selectHandSize,nextRound}` (`GameBoard.jsx:42-292`); `/history`, `/history/public`, `/history/:id`; `/stats/{me,leaderboard,bots}` (`Statistics.jsx:26-50`); `/players/connected` (`ConnectedPlayers.jsx:38`); `/admin/{users,parties,statistics}` and their mutations (`UserList.jsx:27-66`, `AdminPartyList.jsx:29-63`, `AdminStats.jsx:29`).

### Real-time (SSE)
- `useSSE(url, {onMessage, onError, onOpen, reconnectDelay = 3000})` — `hooks/useSSE.js:13-19`. Parses `event.data` as JSON for default messages and for the named `event` type (`useSSE.js:49-96`); on error it closes and reconnects after `reconnectDelay` (`useSSE.js:63-82`).
- **Create and lobby** (2026-09-28): `CreateParty.jsx` asks for the name, the seat count (3-8) and the visibility — no human or bot per seat, no `botIds`, no `/bots` call. In `PartyLobby.jsx` the owner of a waiting party gets, on each free seat, an « Add a bot… » `<select>` of the six levels (a level whose bots all sit at the table is disabled, "none available"), which seats the first free bot of it and reloads the seats; and « Fill with bots and start », a dialog (`role="dialog"`, Easy / Medium / Hard, Medium checked) that calls fill-and-start and opens `/game/:id`, or shows why it was refused (`NOT_ENOUGH_BOTS`). Nothing fills or starts by itself. Tests: `__tests__/CreateParty.test.jsx`, `__tests__/PartyLobby.test.jsx` (« Bots in free seats »).
- GameBoard, PartyLobby and ConnectedPlayers all open `sseUrl()` (`services/sse.js`): `${VITE_API_URL without /api || window.location.origin}/suscribeupdate?token=<URL-encoded localStorage token>`, or no stream (`null`) without a token. The token matters on Rust: `/suscribeupdate` delivers a game's moves and a private party's events only to streams whose token names a player of that party, and registers the session for `/api/players/connected` (`zapzap-rust/src/api/sse.rs`, `should_deliver`; [[Api]]). EventSource cannot send an `Authorization` header, hence the query string.
- GameBoard reacts to `action` values `play`, `draw`, `selectHandSize`, `playerForfeited`, `playerReplaced`, `zapzap`, `roundStarted`, `gameFinished`, `partyDeleted` by refetching state or navigating (`GameBoard.jsx`, `handleSSEMessage`; `playerReplaced`: § Turn timer).
- The endpoint name `suscribeupdate` (sic) is shared with the backend (`zapzap-rust/src/api/mod.rs:24`) and the proxy — do not "fix" the spelling on one side only.

### Turn timer (2026-09-28)
- The rule: `GAME_RULES.md` "Turn Time Limit"; the contract: [[Api]] (`settings.turnTimeLimit`, the state's `turnTimeLimit`/`turnDeadline`/`serverTime`) and [[Backend]] § Turn timer (`playerReplaced`, then 403 `NOT_IN_PARTY`).
- **Creation**: `CreateParty.jsx` offers « Turn timer » as four radios, Off / 30 s / 60 s / 2 min (`TURN_TIME_LIMITS`, `services/party.js`), Off checked, at every seat count — who is human is known only at the start, and the server runs the clock only with two humans or more, as the hint under it says. It always sends `settings.turnTimeLimit` (0 when off).
- **Lobby**: `PartyLobby.jsx` adds « Turn timer: 30 s per turn » to the game settings when `settings.turnTimeLimit` is not 0 (`data-testid="turn-timer-setting"`).
- **Countdown**: `fetchGameState` stamps `performance.now()` when the state arrives and keeps `turnClockOf(gameState, receivedAt)` (`hooks/useTurnCountdown.js`): `turnDeadline − serverTime` minus the time elapsed here since, so neither the browser's clock nor its offset from the server's counts; each refetch resynchronises it. `TurnTimer.jsx` (`role="timer"`, m:ss, red under 10 s) sits on the current turn's row of `PlayerTable`, for every player, and under the round heading of the hand-size screen, which the clock covers too. No clock (`turnTimeLimit` 0, `turnDeadline` null: a bot's turn, between rounds, a game with one human): nothing shown.
- **Ejection**: on `playerReplaced` whose `replacedUserId` is the user, GameBoard navigates to `/parties` with `state.ejected` (`replace`), and PartyList shows « Vous avez été retiré de la partie (temps dépassé) » (`EJECTED_MESSAGE`, `role="status"`); for another player it refetches the state, and the seat shows the bot. A 403 `NOT_IN_PARTY` on a move or a refetch, once a state of the game was shown, is taken for an ejection whose event was missed (a reconnecting stream) and does the same; on the first load it stays « Failed to load game state ».
- Tests: `components/Party/__tests__/CreateParty.test.jsx` and `PartyLobby.test.jsx` (« Turn timer »), `components/Game/__tests__/TurnTimer.test.jsx` (the countdown under fake timers), `GameBoard.test.jsx` (« Turn timer »), `__tests__/integration/TurnTimerEjection.test.jsx` (the real router, board to party list).

### Google OAuth
- Client id from `import.meta.env.VITE_GOOGLE_OAUTH_CLIENT_ID` (build-time) — `App.jsx:22`, `components/Auth/Login.jsx:9`, `Register.jsx:9`. When empty, `GoogleOAuthProvider` is not mounted (`App.jsx:121-129`) and the button is hidden (`Login.jsx:56`).
- `GoogleLoginButton` sends the Google credential to `POST /api/auth/google` (`services/auth.js:174-195`), then stores token/user and navigates to `/parties` (`GoogleLoginButton.jsx:12-17`).
- The Rust backend serves `POST /api/auth/google` since 2026-09-24 (`zapzap-rust/src/api/routes/auth.rs:16`); it needs `GOOGLE_OAUTH_CLIENT_ID` on the backend, the same client id as `VITE_GOOGLE_OAUTH_CLIENT_ID` (see [[Api]], [[Backend]]).

### Environment variables
| Var | Where | Effect |
|---|---|---|
| `VITE_GOOGLE_OAUTH_CLIENT_ID` | `App.jsx:22`; Docker build arg `frontend/Dockerfile:11,13` | enables Google button |
| `VITE_API_URL` | `services/sse.js`; build arg `frontend/Dockerfile:10,12`; `frontend/.env.example` | only the SSE base URL; the axios client ignores it (always `/api`) despite `.env.example` suggesting `http://localhost:9999/api` |

### Dev server and build
- Vite dev proxy forwards `/api` and `/suscribeupdate` to `http://localhost:9999` — `vite.config.js:7-18`. Run the Rust backend on 9999, then `npm run dev`.
- ESLint flat config: recommended + react-hooks + react-refresh; `no-unused-vars` errors except variables matching `^([A-Z_]|motion$)` and arguments matching `^[A-Z_]` (core ESLint cannot see a JSX use: `<Icon>`, `<motion.div>`); Node globals allowed in `src/test/` and `__tests__/`; the vendored `public/elements.cardmeister.full.js` is ignored — `frontend/eslint.config.js`.

### Tests (vitest)
- Config lives in `vite.config.js:19-30`: `globals: true`, `environment: 'happy-dom'`, setup `./src/test/setup.js`.
- `src/test/setup.js` mocks `EventSource` (`setup.js:11-23`) and `localStorage` (`setup.js:26+`), and calls `cleanup()` after each test.
- Test files: component tests under `components/*/__tests__/`, `hooks/__tests__/useSSE.test.js`, `services/__tests__/`, `utils/__tests__/`, `__tests__/integration/GameFlow.test.jsx` (the real `GameBoard` driven through a scripted sequence of API states), and `__tests__/compliance/README.compliance.test.js` (asserts rules "specified in README.md (lines 315-428)"). `src/test/gameState.js` builds the game-state body those tests serve.
- State (2026-09-28): `npx vitest run` → 26 files, 342 tests, all green; `npm run lint` → 0 errors, 9 `react-hooks/exhaustive-deps` warnings. Both run in the `frontend` CI job, lint in the commit hook too; see [[Testing]].

### Docker image and nginx
- `frontend/Dockerfile`: stage 1 `node:20-alpine`, `npm ci`, `npm run build` (`Dockerfile:4-26`); stage 2 `nginx:alpine` serving `/usr/share/nginx/html` on port 80 with a `wget` healthcheck (`Dockerfile:29-45`).
- `frontend/nginx.conf`: `/assets/` cached `expires 1y`, `immutable` (`nginx.conf:12-16`); SPA fallback `try_files $uri $uri/ /index.html` (`nginx.conf:19-21`); gzip on.
- In compose, the image is built from `../frontend` with the Google client id build arg, container `zapzap-frontend` (`zapzap-rust/docker-compose.yml:28-34`), behind the `nginx` reverse proxy that routes `/api/` and `/suscribeupdate` to the backend (`nginx/nginx.conf`, mounted at `zapzap-rust/docker-compose.yml:53`).
- CI builds the image (`docker build -t zapzap-frontend:ci frontend`, `image` job of `.github/workflows/ci.yml`) and runs `npm run build` on Node 24 (`frontend` job) — the Dockerfile uses Node 20.

## Decisions & History
- 2026-09-28 (feat/turn-timer-react): the turn timer reached the React client (§ Turn timer). Chosen: radios rather than a `<select>` at creation, four short values seen at once; the choice offered always (user decision of 2026-09-28, the server decides at the start); the countdown from `performance.now()` since the response rather than `Date.now()` against the deadline, which a browser clock off by a minute would break; the ejection message carried to the party list in the navigation state, as DeleteAccount carries its own to Login, rather than a dialog on a board the user no longer plays; a 403 `NOT_IN_PARTY` after the game was shown taken for the ejection, the only way out of a game under way, so a missed `playerReplaced` still ends on the message rather than on an error screen.
- The frontend was rewritten from vanilla JS/EJS (`views/`, `public/` at the root, legacy) to React + Vite; the root docs were never updated.
- Google OAuth was added in commit 6cca2b1 ("add Google OAuth authentication support") against the Node backend; the Rust rewrite (e4f83da) did not port the route. A local wip entry about Google sign-up asks to check what works end to end.
- `VITE_API_URL` is optional by design: "In production (no VITE_API_URL), the app will use window.location.origin" (`frontend/Dockerfile:8-9,25`).
- Lint and vitest were left out of the CI gate when CI was introduced (commit 1e063d6) because both were already red. They joined the `frontend` job, and lint the commit hook, on 2026-09-23 once green ([[Testing]], Decisions).
- `PlayingCard` called `useEffect` after its joker early return (`react-hooks/rules-of-hooks`): a card switching between joker and standard would have broken React's hook order. The effect now runs before the branch (2026-09-23).
- The lobby and the game board opened `/suscribeupdate` without a token until 2026-09-24; Node broadcasts every event to every stream, so it did not matter. The Rust backend filters party events by the stream's token (#73), so both now pass it through `services/sse.js`, as ConnectedPlayers already did, before production switches to Rust.
- **The Node backend is removed (2026-09-25, chore/remove-node-backend).** This page lost the "or legacy Node" dev backend; the root Playwright suite (`tests/e2e`, `playwright.config.js`) that drove this client against Node went with it. Its code can still be read at `232f168` (the last master commit holding `src/`, e.g. `git show 232f168:tests/e2e`) and `0bfd407` (the last commit whose `docker-compose.yml` builds it, the former rollback target).
- 2026-09-27 (fix/account-deletion-followups): ProtectedRoute's `state.from` keeps `location.search` and `location.hash`, which it dropped, so a link with a query string survives the sign-in (tests in `ProtectedRoute.test.jsx`, through the real Login). The deletion page says a game in progress is forfeited, and the `ACTIVE_PARTY` message names only a waiting party.
- 2026-09-25 (feat/delete-own-account): the account deletion page is a route, `/account/delete`, rather than a modal, so that it is also the stable web URL Google Play requires for deleting an account without the app; ProtectedRoute's redirect-back (`state.from`) makes that URL work for a signed-out visitor.
