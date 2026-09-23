# Frontend

> Scope: the React + Vite single-page client in `frontend/` — structure, routing, API and SSE clients, Google sign-in, build, tests, image.
> Related: [[Architecture]] · [[Api]] · [[Backend]] · [[Testing]]
> Updated: 2026-09-23

## Facts

### Stack
- React 19 (`react` ^19.2.1), React Router 7 (`react-router-dom` ^7.9.5), axios ^1.13.2, framer-motion, lucide-react, Tailwind 3 — `frontend/package.json:15-43`.
- Vite 7 (`vite` ^7.2.6) with `@vitejs/plugin-react` — `frontend/package.json:31,42`, `frontend/vite.config.js:6`.
- Not vanilla JS: the root `CLAUDE.md` and root `README.md` ("vanilla JavaScript") describe the pre-React era; `frontend/README.md` is the untouched Vite template.
- Card faces are drawn by the `cardmeister` web component loaded as a global script: `frontend/index.html:9` (`/elements.cardmeister.full.js`, shipped in `frontend/public/`). `frontend/src/utils/cardAdapter.js:2` converts ZapZap numeric ids (0-53, see [[GameRules]]) to cardmeister `cid`. `deck-of-cards` is still a dependency (`frontend/package.json:20`) but no source file imports it.
- Jokers are not cardmeister's: `PlayingCard.jsx` shows `/joker-red.svg` or `/joker-black.svg` (`frontend/public/`) in an `<img>` — David Bellot's LGPL jokers, the same files as the Flutter client's ([[FrontendFlutter]]); licence in `frontend/THIRD_PARTY.md`.
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
| `services/auth.js` | login/register/Google login, client-side validation |
| `hooks/useSSE.js` | EventSource hook |
| `components/Auth/` | Login, Register, ProtectedRoute, GoogleLoginButton |
| `components/Party/` | PartyList, CreateParty, PartyLobby, ConnectedPlayers |
| `components/Game/` | GameBoard (535 lines) and card/table widgets, HandSizeSelector, RoundEnd |
| `components/History/`, `components/Stats/` | game history, statistics/leaderboard |
| `components/Admin/` | AdminRoute, AdminLayout (renders `<Outlet />`, `AdminLayout.jsx:69`), users/parties/statistics |
| `utils/` | `cards.js`, `scoring.js`, `validation.js` (client-side copies of the rules), `cardAdapter.js` |
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
| `/admin` → `users`, `parties`, `statistics` (index redirects to `/admin/users`) | AdminLayout + children | AdminRoute |
| `/`, `*` | redirect to `/login` | — |
- `ProtectedRoute` only checks that a non-empty `token` exists in localStorage (`components/Auth/ProtectedRoute.jsx:5`, `services/auth.js:156-159`); no expiry check.
- `AdminRoute` additionally requires `user.isAdmin` from the stored user object, else redirects to `/parties` (`components/Admin/AdminRoute.jsx:26`). This is cosmetic: the backend must enforce admin rights (see [[Api]]).

### API client (`frontend/src/services/api.js`)
- axios `baseURL: '/api'`, `timeout: 10000` — `api.js:4-10`. Always relative: works behind the proxy (`nginx/nginx.conf` `/api/`) and in dev via the Vite proxy.
- Request interceptor adds `Authorization: Bearer <localStorage.token>` — `api.js:13-24`.
- On 401 it clears `token` and `user`, but the redirect to `/login` is commented out (`api.js:34-38`): the user stays on a page whose calls keep failing until a navigation hits `ProtectedRoute`.
- Endpoints called (all exist in the Rust router except the Google one): auth `login`/`register`/`google` (`services/auth.js:19,110,180`); `/party`, `/party/:id{,/join,/leave,/start}`, DELETE `/party/:id` (`PartyList.jsx:21,33`, `PartyLobby.jsx:55-92`); `/bots` (`CreateParty.jsx:20`); `/game/:id/{state,play,draw,zapzap,selectHandSize,nextRound}` (`GameBoard.jsx:42-292`); `/history`, `/history/public`, `/history/:id`; `/stats/{me,leaderboard,bots}` (`Statistics.jsx:26-50`); `/players/connected` (`ConnectedPlayers.jsx:38`); `/admin/{users,parties,statistics}` and their mutations (`UserList.jsx:27-66`, `AdminPartyList.jsx:29-63`, `AdminStats.jsx:29`).

### Real-time (SSE)
- `useSSE(url, {onMessage, onError, onOpen, reconnectDelay = 3000})` — `hooks/useSSE.js:13-19`. Parses `event.data` as JSON for default messages and for the named `event` type (`useSSE.js:49-96`); on error it closes and reconnects after `reconnectDelay` (`useSSE.js:63-82`).
- GameBoard and PartyLobby connect to `${VITE_API_URL without /api || window.location.origin}/suscribeupdate` with no token (`GameBoard.jsx:146-150`, `PartyLobby.jsx:42-46`); ConnectedPlayers connects to `/suscribeupdate?token=...` so the backend can register the session (`ConnectedPlayers.jsx:80-82`; backend side `zapzap-rust/src/api/sse.rs:15-24`).
- GameBoard reacts to `action` values `play`, `draw`, `selectHandSize`, `zapzap`, `roundStarted`, `gameFinished`, `partyDeleted` by refetching state or navigating (`GameBoard.jsx:113-135`).
- The endpoint name `suscribeupdate` (sic) is shared with the backend (`zapzap-rust/src/main.rs:41`) and the proxy — do not "fix" the spelling on one side only.

### Google OAuth
- Client id from `import.meta.env.VITE_GOOGLE_OAUTH_CLIENT_ID` (build-time) — `App.jsx:22`, `components/Auth/Login.jsx:9`, `Register.jsx:9`. When empty, `GoogleOAuthProvider` is not mounted (`App.jsx:121-129`) and the button is hidden (`Login.jsx:56`).
- `GoogleLoginButton` sends the Google credential to `POST /api/auth/google` (`services/auth.js:174-195`), then stores token/user and navigates to `/parties` (`GoogleLoginButton.jsx:12-17`).
- **The Rust backend has no `/api/auth/google` route**: its auth router declares only `/register` and `/login` (`zapzap-rust/src/api/routes/auth.rs:12-13`). The route existed in the legacy Node backend (commit 6cca2b1). With a client id configured, Google sign-in would answer 404 once production runs Rust. The Rust user entity keeps a `google_id` column (`zapzap-rust/src/domain/entities/user.rs:82`).

### Environment variables
| Var | Where | Effect |
|---|---|---|
| `VITE_GOOGLE_OAUTH_CLIENT_ID` | `App.jsx:22`; Docker build arg `frontend/Dockerfile:11,13` | enables Google button |
| `VITE_API_URL` | `GameBoard.jsx:146`, `PartyLobby.jsx:42`; build arg `frontend/Dockerfile:10,12`; `frontend/.env.example` | only the SSE base URL; the axios client ignores it (always `/api`) despite `.env.example` suggesting `http://localhost:9999/api` |

### Dev server and build
- Vite dev proxy forwards `/api` and `/suscribeupdate` to `http://localhost:9999` — `vite.config.js:7-18`. Run the Rust backend (or legacy Node) on 9999, then `npm run dev`.
- ESLint flat config: recommended + react-hooks + react-refresh; `no-unused-vars` errors except variables matching `^([A-Z_]|motion$)` and arguments matching `^[A-Z_]` (core ESLint cannot see a JSX use: `<Icon>`, `<motion.div>`); Node globals allowed in `src/test/` and `__tests__/`; the vendored `public/elements.cardmeister.full.js` is ignored — `frontend/eslint.config.js`.

### Tests (vitest)
- Config lives in `vite.config.js:19-30`: `globals: true`, `environment: 'happy-dom'`, setup `./src/test/setup.js`.
- `src/test/setup.js` mocks `EventSource` (`setup.js:11-23`) and `localStorage` (`setup.js:26+`), and calls `cleanup()` after each test.
- Test files: component tests under `components/*/__tests__/`, `hooks/__tests__/useSSE.test.js`, `services/__tests__/`, `utils/__tests__/`, `__tests__/integration/GameFlow.test.jsx` (the real `GameBoard` driven through a scripted sequence of API states), and `__tests__/compliance/README.compliance.test.js` (asserts rules "specified in README.md (lines 315-428)"). `src/test/gameState.js` builds the game-state body those tests serve.
- State (2026-09-23): `npx vitest run` → 21 files, 294 tests, all green; `npm run lint` → 0 errors, 9 `react-hooks/exhaustive-deps` warnings. Both run in the `frontend` CI job, lint in the commit hook too; see [[Testing]].

### Docker image and nginx
- `frontend/Dockerfile`: stage 1 `node:20-alpine`, `npm ci`, `npm run build` (`Dockerfile:4-26`); stage 2 `nginx:alpine` serving `/usr/share/nginx/html` on port 80 with a `wget` healthcheck (`Dockerfile:29-45`).
- `frontend/nginx.conf`: `/assets/` cached `expires 1y`, `immutable` (`nginx.conf:12-16`); SPA fallback `try_files $uri $uri/ /index.html` (`nginx.conf:19-21`); gzip on.
- In compose, the image is built from `../frontend` with the Google client id build arg, container `zapzap-frontend` (`zapzap-rust/docker-compose.yml:28-34`), behind the `nginx` reverse proxy that routes `/api/` and `/suscribeupdate` to the backend (`nginx/nginx.conf`, mounted at `zapzap-rust/docker-compose.yml:53`).
- CI builds the image (`docker build -t zapzap-frontend:ci frontend`, `image` job of `.github/workflows/ci.yml`) and runs `npm run build` on Node 24 (`frontend` job) — the Dockerfile uses Node 20.

## Decisions & History
- The frontend was rewritten from vanilla JS/EJS (`views/`, `public/` at the root, legacy) to React + Vite; the root docs were never updated.
- Google OAuth was added in commit 6cca2b1 ("add Google OAuth authentication support") against the Node backend; the Rust rewrite (e4f83da) did not port the route. A local wip entry about Google sign-up asks to check what works end to end.
- `VITE_API_URL` is optional by design: "In production (no VITE_API_URL), the app will use window.location.origin" (`frontend/Dockerfile:8-9,25`).
- Lint and vitest were left out of the CI gate when CI was introduced (commit 1e063d6) because both were already red. They joined the `frontend` job, and lint the commit hook, on 2026-09-23 once green ([[Testing]], Decisions).
- `PlayingCard` called `useEffect` after its joker early return (`react-hooks/rules-of-hooks`): a card switching between joker and standard would have broken React's hook order. The effect now runs before the branch (2026-09-23).
