# FrontendFlutter

> Scope: the Flutter client in `frontend-flutter/` — Android app and PWA — its layout, API
> configuration and API layer (client, errors, models, repositories), authentication and
> routing guard, real-time channel (SSE), the parties, create-party and lobby screens, the
> game board, the history and statistics screens, the admin screen, theme, localisation, build and tests.
> Related: [[Architecture]] · [[Frontend]] · [[Api]] · [[Deployment]] · [[Testing]]
> Updated: 2026-09-24

## Facts

### Status

- **Playable.** Home, login, register, the parties list, create-party, one party's lobby,
  the game board (`/game/:id`), the history (`/history`), one finished game
  (`/history/:partyId`), the statistics (`/stats`), the admin screen (`/admin`, admins only),
  a start-up splash and a not-found screen
  (`frontend-flutter/lib/router.dart`), over the API layer, the session and the real-time
  channel (below), up to the end of the round and the end of the game (below). Still
  missing against the React client ([[Frontend]]): Google sign-in, the admin Parties and
  Statistics tabs (placeholders for now).
- **History and statistics are reached from the app-bar menu** of every signed-in screen
  (`ZapZapAppBar`, below) — the history, the game details and the statistics carry that
  bar too, with a back button; the deep links (`/app/history`, `/app/stats`) still work. An
  admin session also gets an **Admin** entry, leading to `/admin` (Admin, below).
- The card model, play rules and card widgets (below) are what the board draws hands with.
- **The PWA is deployable**: its own image (`frontend-flutter/Dockerfile` +
  `frontend-flutter/nginx.conf`), the `frontend-flutter` service in both compose files, and
  the `/app/` route of the production proxy. See "The PWA image" below and [[Deployment]].
- CI: the `flutter` job (`.github/workflows/ci.yml`, Flutter pinned to 3.47.2 with
  `subosito/flutter-action`, JDK 17) runs `pub get --enforce-lockfile` (a stale
  `pubspec.lock` fails the job), `gen-l10n`, `dart format --output=none
  --set-exit-if-changed lib test` (an unformatted file fails the job), `analyze`, `test`,
  `build web --base-href /app/ --no-web-resources-cdn` (the image's flags) and
  `build apk --debug`. `scripts/ci_scope.sh` selects it
  **and the `image` job** for a path under `frontend-flutter/` (a `.md` there selects
  nothing), because the PWA image is built from those sources ([[Testing]]). It is not yet a required check of the branch protection ([[ParallelDelivery]]).
- Commit gate: `flutter pub get --offline`, `flutter gen-l10n`, `dart format --output=none
  --set-exit-if-changed lib test` (the whole tree), `flutter analyze` when the
  commit leaves a non-`.md` file under `frontend-flutter/` (a README edit or a deletion runs
  none); no `.dart_tool` → a refusal naming `flutter pub get`; a `pubspec.lock` the pub get
  rewrites and that is left unstaged → a refusal ([[Hooks]]). `scripts/worktree_setup.sh`
  runs the pub get and gen-l10n (`--no-flutter` skips them); when they fail it still clears
  its setup marker, and exits 1 naming the command to rerun.

### Stack

- Flutter 3.47.2 / Dart 3.13.2, SDK at `~/sdk/flutter` (not pinned in the repository);
  `environment.sdk: ^3.13.2` (`frontend-flutter/pubspec.yaml`).
- Platforms: `android` and `web` only (`flutter create --platforms=android,web --org
  com.zapzap`). Android: the section below.
- Dependencies (`frontend-flutter/pubspec.yaml`): provider, http, go_router,
  shared_preferences, flutter_secure_storage, intl, flutter_localizations, flutter_svg,
  web (the `EventSource` of the SSE web transport); dev: fake_async (timer tests); lints `flutter_lints` + `prefer_single_quotes` (`frontend-flutter/analysis_options.yaml`).
- Conventions follow `~/workspace/countscore`: Provider for state, `http` for the API, ARB +
  gen-l10n.

### Layout (`frontend-flutter/lib/`)

| Path | Role |
|---|---|
| `main.dart` | `runApp(ZapZapApp(apiConfig: ApiConfig.fromEnvironment()))`, nothing else |
| `app.dart` | `ZapZapApp`: `MultiProvider` + `MaterialApp.router` (theme, locales, router); `resolveLocale` |
| `router.dart` | `AppRoutes` (path constants), `createRouter(auth:)` — the one `GoRouter`, built once below the providers; a new screen is one more `GoRoute` — and `authRedirect` (Authentication, below) |
| `providers/app_providers.dart` | `appProviders()` — the one list handed to `MultiProvider`; a new provider is one more entry. Holds `ApiConfig`, `ApiClient`, the six repositories, `AuthProvider`, `SseProvider` (which follows it) and `ConnectedPlayersProvider` (which follows both) |
| `providers/auth_provider.dart` | `AuthProvider`, the session (Authentication, below) |
| `providers/sse_provider.dart`, `services/sse_*.dart`, `models/sse_event.dart` | the real-time channel (below) |
| `services/token_storage*.dart` | `TokenStorage` and its platform implementations (Authentication, below) |
| `services/api_config.dart` | `ApiConfig` (below) |
| `services/api_client.dart`, `services/api_exception.dart` | `ApiClient`, `ApiException`, `ApiErrorCode` (API layer, below) |
| `utils/app_theme.dart` | `AppColors`, `AppTheme.dark()` |
| `utils/validators.dart`, `utils/jwt.dart`, `utils/field_touch.dart` | the React username/password rules; the JWT payload and `exp` reader; `FieldTouch`, when a form field may show its refusal |
| `utils/navigation.dart` | `popOrGo(fallback)`: the back button of a pushed screen, replacing the browser's entry; `replaceWith(location)`: a screen taking another's place (Back navigation, below) |
| `utils/date_format.dart` | `Formats`: date and time in the app's locale, percentages, one-decimal numbers (History and statistics, below) |
| `screens/` | `home_screen.dart`, `splash_screen.dart`, `login_screen.dart`, `register_screen.dart`, `parties_screen.dart`, `create_party_screen.dart`, `party_lobby_screen.dart`, `game_screen.dart` (the board), `history_screen.dart`, `game_details_screen.dart`, `stats_screen.dart`, `admin_screen.dart`, `not_found_screen.dart` |
| `models/card.dart` | `GameCard` (not `Card`: Material has one) — id, suit, rank, value, face asset (below) |
| `utils/rules.dart` | `analyzePlay` / `isValidPlay` / `playType`, `handValue`, `isZapZapEligible`, `handValueDisplay`, `zapZapProgress`, `hasJoker`, `counteractPenalty`, `sortCards` (below) |
| `utils/card_l10n.dart` | `CardL10n` on `AppLocalizations`: suit and card names, `cardShort` ("7♥"), `playMoveLabel`, `playErrorMessage(PlayError)` |
| `widgets/` | `playing_card.dart`, `card_back.dart`, `card_fan.dart` (below); `app_logo.dart`; `auth_form.dart` (the card, submit button and switch link shared by login and register, and the error-code → text mapping); `connection_indicator.dart` (Wifi icon of `SseProvider.connected`); `zapzap_app_bar.dart`, `connected_players.dart`, `party_card.dart`, `player_slot_selector.dart`, `player_seat_tile.dart`, `error_banner.dart` (and `partyErrorText`); `game_player_table.dart`, `game_table_area.dart`, `game_hand.dart`, `game_action_buttons.dart`, `game_zapzap_sheet.dart`, `game_hand_size_selector.dart`, `game_round_end.dart`, `game_error_text.dart` (the game board, below); `async_section.dart`, `history_*.dart`, `stats_*.dart` (History and statistics, below); `admin_users.dart` (Admin, below) |
| `providers/party_provider.dart`, `create_party_provider.dart`, `connected_players_provider.dart` | the lobby state (below) |
| `providers/game_provider.dart` | one party's board (below) |
| `models/` | `card.dart` (above) and the typed API models with `fromJson` (API layer, below); `json.dart` holds the lenient readers and `Page<T>` |
| `repositories/` | one per domain over `ApiClient`: auth, party, game, history, stats, admin |
| `l10n/` | `app_fr.arb` (template), `app_en.arb` |

### API configuration (`frontend-flutter/lib/services/api_config.dart`)

- `baseUrl` is, in order: `--dart-define=API_BASE_URL=<url>`; on the web, the page's
  origin (`Uri.base.origin`) — the PWA is served under `/app/` on the API's own domain, so
  there is no CORS (the Node backend only accepts `ALLOWED_ORIGINS`, `src/api/server.js:32-57`);
  elsewhere (Android), `https://zapzap.ombivince.synology.me`. Trailing slashes are stripped.
- `apiUri('/x')` → `<base>/api/x`; `sseUri` → `<base>/suscribeupdate` (the backend's spelling,
  [[Architecture]]).
- Android talking to a local backend: `--dart-define=API_BASE_URL=http://10.0.2.2:9999`
  from the emulator (`10.0.2.2` is the host's loopback), `http://<LAN IP>:9999` from a
  device. Plain HTTP works in the **debug** build only (section Android).
- `ApiConfig` is provided to the tree as `Provider<ApiConfig>` (`providers/app_providers.dart`).

### API layer (`frontend-flutter/lib/services/`, `models/`, `repositories/`)

- **`ApiClient`** (`services/api_client.dart`), the counterpart of the React `api.js`:
  `get`/`post`/`delete` to `ApiConfig.apiUri(path)`, JSON in and out, a `JsonMap` back,
  `ApiClient.defaultTimeout` 10 s. `token` (settable) is sent as `Authorization: Bearer`
  unless the call passes `authenticated: false` (login, register, Google, and the public
  reads: bots, connected players, public history, public stats).
- **401 → `onUnauthorized`** (settable callback): fires on a 401 to an *authenticated* call,
  before the `ApiException` is thrown. Unauthenticated calls never fire it, so a wrong
  password (401 `INVALID_CREDENTIALS`) logs nobody out. `AuthProvider` sets it to its
  `logout`, and the router follows to login (the React client only clears, `api.js:34-38`).
- **`ApiException(status, code, message, details)`** (`services/api_exception.dart`) reads
  every error shape: `{error, code, details?}` (auth/party/game, both backends);
  `{success:false, error}` and `{error}` (admin on Rust, history, stats, bots) — `code` then
  comes from the status (`BAD_REQUEST`, `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`,
  `CONFLICT`, `SERVER_ERROR`, else `HTTP_<n>`); `{error, code, message}` (Node 404/500
  fallbacks, `src/api/server.js:176-196`); `{message}`; the Rust bare 401 with no body.
  No response: status 0, `NETWORK_ERROR` or `TIMEOUT`; a 2xx that is not an object:
  `INVALID_RESPONSE`. `message` is the backend's text for logs — screens pick a localised
  text from `code` (`ApiErrorCode` names the codes they react to).
- **Repositories** (`repositories/*.dart`), stateless, each `XRepository(ApiClient)`:
  `AuthRepository` (login, register, loginWithGoogle), `PartyRepository` (list,
  create — `playerCount` required, Node rejects a create without it —, details, join,
  leave, start, delete, bots, connectedPlayers), `GameRepository`
  (state, selectHandSize, play, drawFromDeck, drawFromPlayed, zapZap, nextRound),
  `HistoryRepository` (mine = `GET /history`, public, details), `StatsRepository` (mine,
  user, leaderboard, bots), `AdminRepository` (users, deleteUser, setAdmin, parties,
  stopParty, deleteParty, statistics). Only routes both backends serve, plus
  `/auth/google`. A move's answer is not the new table: refetch `GameRepository.state`.
- **Models** (`models/`): `User`, `AuthSession` (`user.dart`); `Party`, `PartySettings`,
  `PartySummary`, `PartyPlayer`, `PartyDetails`, `CreatePartyResult`, `JoinPartyResult`,
  `RoundInfo`, `StartPartyResult`, `ConnectedPlayer` (`party.dart`); `Bot`; `GameSnapshot`
  (the `/state` answer), `GameState`, `GameAction` (enum of `currentAction`, `unknown` for a
  new value), `LastAction`, `GameWinner` (`game_state.dart`); `PlayResult`, `DrawResult`,
  `SelectHandSizeResult`, `ZapZapResult`, `NextRoundResult` (`game_results.dart`);
  `GameHistoryEntry`, `GameDetails`, `GameSummary`, `GamePlayerResult`, `RoundHistory`,
  `RoundPlayerScore` (`history.dart`); `UserStats`, `ZapZapStats`, `LeaderboardEntry`,
  `BotStats`, `BotTotals`, `BotStatsLine` (`stats.dart`); `AdminUser`, `AdminParty`,
  `AdminStatistics`, `GamePeriod`, `ActiveUser` (`admin.dart`); `Page<T>` (`json.dart`).
  Card ids stay `int` (0-53); no model is named `Card`.
- **Parsing rules** (`models/json.dart`), because the two backends disagree on types:
  maps keyed by player index arrive with string keys (`{"0": 28}`) and become `Map<int, …>`;
  Rust sends some of them as `[{playerIndex, score}]` (zapzap `scores`, nextRound), read too.
  A network failure of any kind (`ClientException`, and the `dart:io` socket/TLS errors that
  can escape it) is `NETWORK_ERROR`; the 10 s timeout is one deadline over headers and body.
  Timestamps are Unix seconds, or milliseconds when `>= 1e10` (`lastAction.timestamp`,
  `connectedAt`), or numeric/RFC 3339 strings (Rust `createdAt`); all become UTC `DateTime`.
  Ids are strings even when Node sends an integer (party seat `id`). Node's history
  `handCards` and admin party `settings` are JSON-encoded strings, decoded.
- **Node vs Rust shapes seen** (fixtures vs `zapzap-rust/src/api/routes/*.rs`): party
  settings are `{playerCount, allowSpectators, roundTimeLimit}` on Node — which **requires**
  `playerCount` 3-8 on create, else 500 `CREATE_PARTY_ERROR` — and `{handSize, maxScore,
  enableGoldenScore, goldenScoreThreshold}` on Rust, so `PartySettings` has both, all
  optional; history entries carry `totalRounds`/`winnerFinalScore` (Node) or
  `roundsPlayed`/`userPlacement`/`userScore` (Rust); Node `join` has no `playerIndex`; Node
  `zapzap` adds a `handPoints` map, Rust sends one number; zapzap `scores` are the running
  **totals** after the round on Node (an object, `src/use-cases/game/CallZapZap.js:121-125`)
  but the **round's own points** on Rust (a list, `zapzap-rust/src/domain/services/game_service.rs:228`),
  so `ZapZapResult` has `totalScores` (Node) or `roundScores` (Rust), never one `scores`;
  `counteractedBy` is an index on Node, a string on Rust; Node play/draw answers carry a raw `gameState` with every hand and
  the deck, deliberately not parsed.
  > **Status: Outdated** (2026-09-24) — Rust's `zapzap` now answers Node's shape
  > (`fix/rust-api-errors-contract`, [[Api]]): `scores` the running totals as an object,
  > `handPoints` a map, `counteractedBy` an index or `null`, plus the round's points under
  > `roundScores`. `ZapZapResult` so gets `totalScores` from both backends; it does not read
  > `roundScores` yet.
  > **Status: Outdated** (2026-09-24) — Node's `GET /history` now sends `userPlacement` and
  > `userScore` too (`src/use-cases/history/GetGameHistory.js`, from
  > `player_game_results`); `/history/public` carries neither, on both backends.
- **Fixtures** (`test/fixtures/*.json`): answers captured from the local Node backend
  (`PORT=9911 node app.js` on a worktree database after `npm run init-demo && npm run
  init-bots`, one game against EasyBot1 and MediumBot1 played through the API to its end),
  tokens replaced by placeholders. `error_*.json` are `{status, body}`. `test/fixtures.dart`
  loads them.

### Authentication (`providers/auth_provider.dart`, `services/token_storage*.dart`, `router.dart`)

- **`AuthProvider`** (a `ChangeNotifier`, in `appProviders()`, not lazy): `user`, `token`
  (`null` signed out), `isAuthenticated` (a user and a token whose `exp` is still ahead —
  re-checked on every read, so a session that expires while the app runs stops counting
  at the next navigation), `isAdmin`, `isRestored`; `restore()`, `login`, `register`,
  `logout`. It keeps `ApiClient.token` in step and owns `ApiClient.onUnauthorized`.
  `logout` is idempotent — the first of several parallel 401s does the work, the others
  return — and clears the storage. Other state that depends on the session (the SSE
  connection) listens to it and follows `token`; this provider knows nothing of SSE.
- **Start-up**: `restore()` reads the stored session; an expired, undecodable or
  `exp`-less token, or an unreadable user, is erased (`utils/jwt.dart`: payload decoded
  without checking the signature — the backend does that). Until it is done the router
  holds on `/splash`.
- **Storage** (`TokenStorage.platform()`, conditional import on `dart.library.js_interop`):
  `flutter_secure_storage` on Android (`token_storage_io.dart`), `shared_preferences` on
  the web (`token_storage_web.dart`, localStorage, keys prefixed `flutter.` by the plugin —
  no clash with the React client's own `token` on the same origin). Keys `token` and `user`
  (JSON of `User.toJson()`), those of the React client. `MemoryTokenStorage` for tests.
- **Screens**: login (`Login.jsx`) only requires both fields — as React, so an account
  that predates the rules still signs in; register (`Register.jsx`) checks the rules of
  `auth.js:42-88` (`utils/validators.dart`: username trimmed, 3-30,
  `^[a-zA-Z0-9_-]+$`; password 6-100, not trimmed). **Validate on touch or submit**
  (`FieldTouch`, also on the create-party name): a field shows its refusal once edited and
  left, or when submit is tapped, then live — never on a form just opened. Submit stays
  amber and active; a click with a field refused marks it, focuses it and sends nothing
  (C2). Both share `AuthCard` (`widgets/auth_form.dart`): the logo with its one-line pitch
  (`AppLogo(pitch: true)`, `authPitch`) above the title (C1); the fields in one
  `AutofillGroup`, Next moving on and Done submitting, the password with an eye
  (`AuthPasswordField`) (C3); a spinner in the button while the call runs, then the
  refusal in a red `ErrorBanner` (live region) just above the button (C4). The username
  is sent trimmed (Node trims it
  too, `src/use-cases/auth/RegisterUser.js:93`). Server refusals map from
  `ApiException.code`: `INVALID_CREDENTIALS`, `USERNAME_EXISTS`, no response
  (`NETWORK_ERROR`/`TIMEOUT`), else a generic text. Success navigates by itself: the router
  follows `AuthProvider`.
- **Routing guard** (`authRedirect(auth, uri)`, run on every navigation and on every
  `AuthProvider` change via `refreshListenable`): not restored → `/splash?from=<path>`;
  signed out → public routes (`/`, `/login`, `/register`) stay, anything else →
  `/login?from=<path>`; signed in → `/`, `/login`, `/register` lead to `from` or
  `/parties`; `/admin` and `/admin/**` need `isAdmin`, else `/parties` (the admin screen,
  Admin below). `from` is only
  followed when it is a local path (`/x`, not `//host` or a scheme). An unknown path shows
  the not-found screen, signed in or out (`test/app_test.dart`). React's
  `ProtectedRoute` checks only that a token exists, never its expiry
  (`frontend/src/components/Auth/ProtectedRoute.jsx:5`). On the web the route is the URL
  path under the base href (`/app/parties`): `lib/main.dart` calls `usePathUrlStrategy()`
  (`flutter_web_plugins`) before `runApp`, a no-op off the web; the browser path less
  `/app/` is go_router's initial route, which wins over `initialLocation`
  (`test/deep_link_test.dart`). A `push`ed screen shows its own path in the address bar:
  `createRouter` sets `GoRouter.optionURLReflectsImperativeAPIs = true` (go_router's
  default keeps the path of the screen below), so a reload of `/app/parties/new`, a lobby
  or a game stays on it and a lobby's URL can be shared (`test/deep_link_test.dart`, `the
  URL of a pushed screen`).

### Real-time channel (SSE)

The server side is fixed ([[Architecture]]): `GET /suscribeupdate[?token=]`. Node sends
every event to every stream; Rust filters per user ([[Backend]]): events without a party and
a public party's lifecycle events (`playerJoined`, `playerLeft`, `partyStarted`,
`partyDeleted`, `gameFinished`, what `PartyListProvider` reloads on) go to every stream, a
game's moves and every event of a private party only to its players' streams — so the
token matters; an initial `event: connected`, then every broadcast as `event:
event` + a JSON object, a `: heartbeat` comment every 20 s; Node also sends `retry: 1000`
(`src/api/server.js:69-130`), Rust a `type` on every broadcast (`zapzap-rust/src/api/sse.rs`,
`GameEvent`, `zapzap-rust/src/infrastructure/app_state.rs:230-244`).

- **`SseParser`** (`services/sse_parser.dart`): the `text/event-stream` format, pure, fed
  chunks of any size — `\n`/`\r\n`/`\r` line ends, `:` comments ignored, multi-line `data`
  joined with `\n`, blank-line dispatch (none without data), default name `message`, `id`,
  `retry` (read, not acted on). Emits `SseMessage(event, data, id)`.
- **`SseTransport`** (`services/sse_transport.dart`) opens one connection, never reconnects;
  `createPlatformTransport()` picks it by conditional import (`dart.library.js_interop`):
  - `HttpSseTransport` (`sse_transport_io.dart`, Android): a streamed `package:http`
    request, `Accept: text/event-stream`, UTF-8 → `SseParser`; one `http.Client` per
    connection, closed with it; a non-200 fails; **60 s** without a byte fails (heartbeats
    are every 20 s, so a half-open socket after a network change is noticed).
  - `EventSourceSseTransport` (`sse_transport_web.dart`, PWA): `package:web` `EventSource`,
    listeners on `event` and `message`; on `onerror` it closes the source, so the browser's
    own retry never runs alongside ours.
- **`SseClient`** (`services/sse_client.dart`, plain Dart): `connect(token)` opens
  `<sseUri>?token=<jwt>` — with the token the backend registers the user as online, so
  presence works (the React lobby and board connect tokenless, [[Frontend]]); the same token
  again is a no-op, a new one replaces the connection. On an error or end of stream it
  reopens **3 s** later (`defaultReconnectDelay`, React's `reconnectDelay`), until
  `disconnect()`. A generation counter drops late callbacks of a replaced connection.
  `events` is a broadcast `Stream<SseEvent>`: only `event`/`message` events whose data is a
  JSON object (the `connected` greeting is dropped).
- **`SseEvent`** (`models/sse_event.dart`): the payload (`data`) plus `type`, `partyId`,
  `userId`, `action`, `timestamp` through the lenient `Json` readers; `isPresence` for
  `userConnected`/`userDisconnected`/`userStatusChanged`. A client may get events of other
  parties (all of them on Node, public lifecycle ones on Rust): a screen keeps those of its
  `partyId`.
- **`SseProvider`** (`providers/sse_provider.dart`, a `ChangeNotifier`): `connect(token)`,
  `disconnect()`, `follow(token?)`, `events`, `connected` (notifies on change). One for the
  whole signed-in session: in `appProviders` a `ChangeNotifierProxyProvider<AuthProvider,
  SseProvider>`, not lazy, calls `follow(auth.isAuthenticated ? auth.token : null)` on every
  `AuthProvider` change — connected on sign-in or a restored session, closed on logout (a
  401 included), reopened when the token changes (`test/sse_session_test.dart`).
  `ZapZapApp(sseTransport:)` swaps the transport for tests.
- Node subscribes a new stream before it broadcasts `userConnected`, so a client hears its
  own arrival; a user is online while at least one of their streams is open (a second tab,
  or a reconnection whose new stream opens before the old one closes), and only the first
  stream's opening and the last one's closing are broadcast (`SessionManager` counts streams
  per user, `src/infrastructure/services/SessionManager.js`; `tests/unit/api/presence.test.js`).
  Rust still has the old behaviour (`zapzap-rust/src/api/sse.rs`).
- Checked against the local Node backend (2026-09-22): a `play` sent by curl as another user
  reached `HttpSseTransport` (a `dart run` script) and `EventSourceSseTransport` (the web build
  in Chromium); the token's user appeared in `GET /api/players/connected`; after the backend
  was stopped and restarted, the client reconnected 3 s after the drop.

### Parties, create-party and lobby

The React counterparts are `frontend/src/components/Party/{PartyList,CreateParty,PartyLobby,ConnectedPlayers}.jsx`.

- **Routes** (`router.dart`): `/parties` (the list), `/parties/new` (create — declared
  **before** `/parties/:id`, which would match it), `/parties/:id` (the lobby), `/game/:id`.
  `AppRoutes.partyPath(id)` and `AppRoutes.gamePath(id)` build the last two.
- **Back navigation**: a screen reached from another is `context.push`ed, never `go`ne
  to — `go` replaces the whole stack, and Android's system Back then leaves the app. The
  list pushes the form, the lobby and a game; the form's lobby and the lobby's game
  **replace** the screen they came from (`replaceWith`, `utils/navigation.dart`: a
  `pushReplacement` under `Router.neglect`, so the browser's history entry is replaced
  too), so Back from either — Android's or the browser's — returns to the list, not to a
  form whose party exists or a lobby that sends straight back to the game. A screen's own back button, and the lobby closing, call `popOrGo`
  (`utils/navigation.dart`): pop when something is below, else `go` to the list — a deep
  link or a reload of the PWA has nothing below. The history, the game details and the
  statistics follow the same rule (below). go_router reports a pop, like a `go`, to the
  browser as a *new* history entry (`replace: false`), so the browser's Back would reopen
  the screen just left; `popOrGo` runs under `Router.neglect`, which replaces the entry
  instead. `test/party_screens_test.dart` (`back navigation`) and `test/app_bar_test.dart`
  drive the system Back (`handlePopRoute`); `test/deep_link_test.dart` (`a back button
  replaces the screen it leaves`) reads what each back button reports on
  `SystemChannels.navigation`: `/parties (replace)` from the form, the lobby, the history
  and the statistics, `/history (replace)` from the details opened by a link.
- **Screens own their provider**: each screen builds it in `initState` from the
  repositories it reads off the tree and disposes it, and draws with a `ListenableBuilder`;
  the widgets below take plain data. Only `ConnectedPlayersProvider` is app-wide.
- **`PartyListProvider`** (`providers/party_provider.dart`): `GET /party`, pull-to-refresh
  (`load(showSpinner: false)`), and `join` — which answers `true` on `ALREADY_IN_PARTY`
  too, because React navigates to the lobby on it (`PartyList.jsx:37-39`). **The event
  stream keeps the list current** (React waits for a reload): `playerJoined`, `playerLeft`,
  `partyStarted`, `partyDeleted` and `gameFinished` (`refreshingActions`), about any party,
  reload it without a spinner `refreshDelay` (1 s) after the last one, so a burst of bot
  joins is one `GET /party`; a game move reloads nothing. Only the newest load's answer is
  kept (`_loadGeneration`, as in the lobby), so a pull and an event answering out of order
  never show the older list. Dispose cancels the pending reload and the subscription. No
  event announces a party being created: a new one appears with the next event about any
  party, or on pull-to-refresh. **The screen has two sections** (`screens/parties_screen.dart`):
  "My games" (`myParties`: the caller's, `isMember` — a running game first, then the
  lobbies, then the finished ones, each in the backend's order) and "Available games"
  (`openParties`, the heading `partiesHeading`). **A card is two lines**
  (`widgets/party_card.dart`): the name and a badge, then "seats · status · you host" and
  one button. A running game of mine has an amber border, an "In progress" badge and the
  only filled button, Resume; my lobby is green-bordered, Joined, with an outlined Lobby;
  someone else's party has an outlined Join (disabled when full, playing or finished).
  There is **no "your turn" badge**: neither `GET /party` (Node or Rust) says whose turn it
  is. While the first answer is on its way the list shows three skeleton cards; an empty
  "Available games" ends on an invitation (create yours — `push`es `/parties/new` —, or
  pull down to refresh), worded "no game available" when I have none either. The list
  ends with `PartiesScreen.fabClearance` (88 px) so the amber Create button never covers
  the last card's button. A row without
  `maxPlayers` (or with 0) falls back to `settings.playerCount`, then to 5
  (`defaultPartyPlayers`, `models/party.dart`), as React does — not "2 / 0" and Full. A
  failed load shows its error banner alone, not the "no party yet" empty state under it. The cards are laid out
  as rows of one to three (`_cards`, by width), not as a `SliverGrid`: a grid tile's height
  is decided before the card is laid out, and any fixed one overflows at a large system
  font size.
- **`CreatePartyProvider`** (`providers/create_party_provider.dart`): the form. Seat 0 is
  the creator and always human; every other seat is human or a bot of a difficulty
  (`botDifficulties`: `easy`, `medium`, `hard`, `hard_vince`, `llm`, `thibot` — the six
  React offers, not the backend's `ml`/`drl`). **A bot account can only sit once at a
  table**: choosing a difficulty takes the first bot of it no other seat holds, and when
  there is none left the seat stays human and the option shows "none available"
  (`CreateParty.jsx:47-74`). Changing the seat count keeps what was already configured
  (React resets). `POST /party` sends `{name, visibility, settings.playerCount, botIds}`.
  The name is 3 to 50 characters once trimmed (`partyNameMinLength`/`MaxLength`), as Node
  requires (`src/use-cases/party/CreateParty.js:47-53`): Create stays active, and a name
  too short shows its reason once the field was edited and left or Create tapped
  (`FieldTouch`), and sends nothing; longer cannot be typed — Node would answer a generic
  500.
- **`PartyLobbyProvider`** (`providers/party_provider.dart`): `GET /party/:id`, then the
  event stream filtered on `partyId` — `playerJoined`/`playerLeft` reload the seats without
  a spinner, `partyStarted` and `partyDeleted` set `outcome` (`LobbyOutcome.started` /
  `.closed`) and the screen navigates to `/game/:id` or `/parties`. A party already
  `playing` when it loads sets `started` too, so returning to it goes straight to the game.
  `isOwner` falls back to comparing `party.ownerId` with the session's user, because Node's
  answer carries neither `isOwner` nor `userPlayerIndex`; `canStart` needs the owner and 3
  players; `canDelete` is the owner **or** the only human at the table
  (`PartyLobby.jsx:140-144`). Delete asks first, in an `AlertDialog`. Its loads are
  sequenced as the board's are (`_loadGeneration`, below): two players joining a moment
  apart start two reloads, and an older answer arriving last is dropped.
  The hand size is only shown when the party carries one (Rust): on Node the starting
  player picks it each round (`GAME_RULES.md`), so React's "Hand Size: 7" is wrong there.
- **The lobby screen** (`screens/party_lobby_screen.dart`, S1–S4 of the UX study) opens on
  the invite code (`party.inviteCode`, both backends send it), 26 px mono amber with a
  Copy button (clipboard, then a snack bar); then the settings as one `Wrap` of chips
  (`InfoChip`, `widgets/player_seat_tile.dart`): seats, hand size (Rust), "you host", the
  status. A seat (`PlayerSeatTile`) shows a green "online" dot for a human the session
  knows is connected — the signed-in player, or one in `ConnectedPlayersProvider`, which
  holds five at most, so no dot means "not known", never "offline" —, a bot's level as an
  amber chip, the owner's crown. A free seat is text only, the first one pointing at the
  invite code: neither backend can seat a bot in an existing party, so there is no "add a
  bot". Under the list, pinned: the reason Start is or is not active (players missing,
  "can start", or "the host can start" for a guest), Start named with the player count,
  then Leave. **Delete is in the ⋮ menu** (`AppBarMenuAction`, key `delete-party`), no
  longer a red button next to Leave; it still confirms.
- **`ConnectedPlayersProvider`** (`providers/connected_players_provider.dart`), app-wide
  and lazy: `GET /players/connected` on sign-in (kept to five, as the events are), **again
  on every (re)connection of the event stream** (it follows `SseProvider.connected` through
  a `ChangeNotifierProxyProvider2` in `appProviders`), then `userConnected` (prepended, five
  at most), `userDisconnected` and `userStatusChanged`. The sign-in fetch usually answers
  before the backend has registered our stream — a lone player then saw 0 —, and what
  happened while the stream was down never arrives; the reload on connection covers both.
  An answer overtaken by a later load is dropped (`_loadGeneration`). Until the first
  answer or event (`loaded`), and after a failed one, the app bar shows `–` rather than a
  count: "0" would claim nobody is online (`test/party_provider_test.dart`). The app bar (`widgets/zapzap_app_bar.dart`) holds it, the connection
  indicator, sign-out and the navigation menu — icons only, so it fits a phone, which the
  React header does not.
- **The app-bar menu** (`widgets/zapzap_app_bar.dart`, key `app-bar-menu`) leads to the
  history (`menu-history`) and the statistics (`menu-stats`), with `context.push` so the
  Android system Back button returns to the screen below. A menu rather than one icon
  each: there is no URL bar on Android, and more icons would not fit a 360 px bar at a
  large system font. An admin session also gets `menu-admin` (`AuthProvider.isAdmin`, read
  when the menu opens), leading to `/admin`. A screen may add its
  own entries below a divider (`ZapZapAppBar.actions`, `AppBarMenuAction`): the lobby's
  Delete.
- **Error text** comes from `partyErrorText` (`widgets/error_banner.dart`), mapping
  `ApiException.code` (`PARTY_NOT_FOUND`, `PARTY_FULL`, `PARTY_STARTED`,
  `PARTY_ALREADY_PLAYING`, `NOT_OWNER`, `NOT_AUTHORIZED`, `NOT_IN_PARTY`, no answer) to
  ARB strings;
  `PartyErrorCode` (`providers/party_provider.dart`) names the party codes.

### The game board (`screens/game_screen.dart`, `providers/game_provider.dart`, `widgets/game_*.dart`)

The React counterparts are `frontend/src/components/Game/{GameBoard,PlayerTable,TableArea,PlayerHand,ActionButtons,HandSizeSelector}.jsx`.

- **`GameProvider`**, built and disposed by the screen as the lobby's providers are:
  `GET /game/:id/state`, then the event stream filtered on `partyId` — `play`, `draw`,
  `selectHandSize`, `zapzap`, `roundStarted`, `gameFinished` and `partyStarted` refetch
  without a spinner, `partyDeleted` sets `outcome` and the screen goes back to the list.
  `partyStarted` is what takes a client that opened `/game/:id` before the owner started
  off the "not started yet" page and onto the table with no reload; that page also has a
  Retry (`Key('retry-game')`) for an event missed while the channel was down. No move's answer
  carries the new table, so every move refetches the state (`GameBoard.jsx` does the same).
  It derives the caller's seat from the user id (`myPlayerIndex`, `isMyTurn`), the card
  counts, the scores, the eliminated players, `orderedPlayers` (turn order from
  `startingPlayer`), the two hand values and `zapZapEligible`.
- **Nothing takes a drawn table away.** Three fields, not one: a refused **move** fills
  `actionError`, which the screen reads once (`consumeActionError`) and shows in a snack
  bar; a **refresh that fails while a table is on screen** fills `refreshError`, and the
  board stays under a banner with a Retry (`Key('gameStaleBanner')`), cleared by the next
  answer; only a **load with nothing to fall back on** fills `error` and draws the error
  page. Text comes from `ApiException.code` through `gameErrorText`
  (`widgets/game_error_text.dart`, `GameErrorCode` in the provider). The React board sets
  one `error` for all three and draws an error page instead of the table
  (`GameBoard.jsx:220-235`) — including after a move that actually landed.
- **Loads are sequenced** (`_loadGeneration`, the guard of `services/sse_client.dart`):
  a move's refetch and the broadcast it triggers put two `GET /state` in flight a fraction
  of a second apart, and they can answer out of order. Only the newest answer is kept;
  an older one, good or bad, is dropped. Without it a bot party could leave the board a
  turn behind, every button disabled, with no event left to correct it.
- **One selection, in the provider**: the tapped ids in tap order, dropped whenever the
  hand changes. React keeps one in `PlayerHand` and another in `GameBoard`, and they drift
  apart. `invalidPlay` is `analyzePlay`'s code; the action bar shows its text and disables
  Play, and the board stays. The discard card is kept across a refresh that leaves the
  hand as it was, so `willTakeFromDiscard` checks it is still in `lastCardsPlayed`: a card
  gone from the pile is never posted, and Take falls back to Draw.
- **Modes**, from `gameState.currentAction`: `selectHandSize` shows
  `GameHandSizeSelector` (4-7, or 4-10 in Golden Score; it starts on the middle of the
  range, 5 or 7) to the starting player and a waiting card to everyone else; `play`/`draw`
  show the board; `finished` shows the end of the round (below).
- **Widgets take plain data**, as the lobby's do: `GamePlayerTable` (a `GameSeat` per
  line, below); `GameTableArea` (the `lastAction` message, the cards laid down this turn,
  the discard pile and the deck — both targets only in the draw step —, and the
  "reshuffled" banner for 2.5 s, timed in the widget's state); `GameHand` (the `CardFan`
  under the hand value); `GameActionButtons` (the step indicator, the one button naming
  the move, the refusal, and ZapZap). "The turn reads itself", below, has what each shows.
- **Back leads to `/parties`, not to the lobby**: `PartyLobbyProvider.load` sends a party
  that is `playing` straight back to `/game/:id`, so a back button pointing at the lobby is
  a flash and a full remount of the board, and no way out of the game. Every exit of the
  game — its back button, the body's back button, "back to the parties" at the end, a
  deleted party — calls `popOrGo(AppRoutes.parties)` (`utils/navigation.dart`), which
  replaces the game's browser entry by the list's (Back navigation, above), so the
  browser's Back from the list never reopens the game.
  `test/game_screen_test.dart` (`leaving the board`) checks list → game → back: `/parties`,
  `canPop()` false, reported as `(replace)`.
- **Layouts**: under 800 px one column that fills the height — each section over its own
  scroll view, so a large system font shrinks a section instead of overflowing the column
  —, above it the players beside the felt. The phone column is a `CustomMultiChildLayout`
  (`widgets/phone_board_layout.dart`, `PhoneBoardLayout`): the moves take what they need
  at the bottom, the players up to 3/11 of the rest, the hand what it needs as long as the
  felt keeps 1/5 (`feltFloor`), and the felt is laid out at exactly the height left between
  the players and the hand — no empty band between felt and hand, and the felt's content
  centred in it (`GameTableArea` fills a tight height: `StackFit.passthrough`, then a
  `minHeight` under its scroll view). A `Column` of `Flexible`s left the unused share as an
  empty band and cut the felt in the draw step (production, 390x844, 2026-09-23); the
  earlier delegate still left ~100 px between felt and hand at 360x740. In the draw step
  the hand, which cannot be played then, keeps at most 1/5 of the height
  (`drawHandShare`) and scrolls, and the felt gets the rest. The hand is then read, not
  played (`GameHand.compact`): its value alone — no gauge, no Clear, a picked pile card
  is dropped by tapping it again — over one row of 48 px cards, and the felt's cards
  played this turn shrink to 49 px (`GameTableArea.drawPlayedWidth`): #64's two rows of
  big cards in 3/20 showed only a strip of rank (production, 360x740, 2026-09-24). The
  `lastAction` message is
  hidden then — it is this player's own play, which the "Posées" row shows. The
  felt scrolls *inside* its own edge (`Key('gameTableScroll')`), so its border, amber in
  the draw step, is never cut. `test/game_felt_layout_test.dart` proves it at 360x740 and
  390x844, text scales 1.0 and 1.5, with Roboto loaded from the SDK (the test font's square
  glyphs are twice as wide): the whole felt, the deck and the take hint show, except at
  360x740 at 1.5, where the players and the moves take half the height and the felt's
  content scrolls inside a whole edge. The wide board's felt is `Expanded` too. Checked in the PWA (2026-09-23, Chromium at
  390x844, the web build against a stand-in API in the draw step). `test/game_screen_test.dart`
  pumps every mode at 360x740 at text scales 1.0, 1.5 **and** 2.0 — not my turn with a two-line
  waiting banner, the tallest action bar (two-line banner over the invalid-play reason)
  and a Golden Score hand of 10 included — and the wide layout at every scale too; the
  suite's default 1100x3000 hides clipping.
- Checked against the local Node backend (2026-09-23): a party of Vincent and two bots
  played through the web build in Chromium — hand size, play, take from the discard, draw,
  the bots' moves arriving over SSE, the end of the round and the next round. Known local
  limit: a round that ends does not advance on its own when bots are to act (the Node bot
  orchestrator has no `finished` branch), so the Next round button is what moves it on.
  The end of a round, Next round and the end of the game were checked the same way
  (2026-09-23): a game of Vincent and two bots played to its end over the local backend —
  a successful ZapZap with its standings and revealed hands, three rounds started from the
  client, an eliminated player's badge, and the winner banner with Back to games.

### The turn reads itself (J1–J6, T1, T2 of the UX study, 2026-09-23)

In the existing look (`utils/app_theme.dart`); the strings use "tu", as the study's
mockups do. `test/game_turn_ux_test.dart` proves each item, one group per item.

- **The step indicator** (J1, `GameActionButtons`, `TurnStepChip`): on the player's turn
  two chips, ① Jouer → ② Piocher (`GAME_RULES.md`, Turn Flow), the current one amber, the
  other grey — checked (✓ Jouer) once played. Another player's turn shows "En attente de
  X" (`Key('turnBanner')`) instead.
- **One button that names the move** (J2): full width, keyed `play-cards` in the play step
  and `draw-card` in the draw step. It reads "Jouer 7♥", "Jouer la paire de 7", "Jouer le
  groupe de 7 (3 cartes)", "Jouer la suite (3 cartes)" (`CardL10n.playMoveLabel`, from
  `analyzePlay`), plain "Jouer" when nothing or a refused play is selected, then
  "Piocher" or "Prendre 7♥" (`cardShort`: the rank and `Suit.symbol`), amber in both steps —
  the step chips say which step it is. The refusal reason
  stays, under it.
- **The hand value in plain words** (J3, `GameHand`): "Ta main · 29 pts" — jokers at 0,
  what ZapZap is decided on —, a gauge towards "ZapZap à 5" (`zapZapProgress`: 5 / value,
  full at 5 or under), and "En fin de manche : n pts (joker 25)" only when the hand holds a
  joker (`hasJoker`) — a joker counts 25 at the end of the round for anyone without the
  lowest hand, counteracted or not (`GAME_RULES.md`), so the label does not tie it to a
  counteract.
- **ZapZap with its risk** (J4): always shown; disabled, it says why — "main 29, il faut 5
  ou moins", or "au début de ton tour" outside the player's play step. A tap opens a
  bottom sheet (`widgets/game_zapzap_sheet.dart`, `confirmZapZap`) that states the
  counteract: the hand at 25 per joker + `counteractPenalty(activePlayers)` =
  (active players − 1) × 5 (`utils/rules.dart`), active players being those not in
  `eliminatedPlayers` (`GameProvider.activePlayerCount`), and in Golden Score that being
  counteracted loses the game. `ZapZapRisk.eligible` is the provider's `zapZapEligible`, so
  the button's reason and its enabled state come from one source. Only Confirm posts `/zapzap`; Cancel or a dismissal posts
  nothing.
- **The casino felt** (`GameTableArea`, `lib/widgets/felt_painter.dart`, 2026-09-24): a
  6 px dark wood rim (`Key('feltRim')`, `GameTableArea.rimWidth`, a linear gradient
  `rimLight` → `rimDark` and a drop shadow) around the felt (`Key('gameTable')`): a
  `RadialGradient` `feltCenter` → `feltEdge`, lit at the centre and dark at the edges, and
  under the cards a `FeltPainter` — short fibres from a fixed seed (the same felt on every
  frame), the ZapZap bolt and name as a faint watermark, the rim's shadow blurred along the
  inside of the edge. No image asset. The texture paints *inside* the felt's border, so the
  edge — a 1 px `rimInlay` line, amber and 2 px in the draw step — lies on the rim's inner
  lip, over everything; in the draw step the rim also glows amber. The content sits behind a
  `RepaintBoundary`, so a scroll of the felt does not repaint the texture. The rim takes
  6 px a side the plain felt did not: the felt's padding went from 8 to 6 × 4
  (`GameTableArea.feltPadding`) and two 4 px gaps to 2, so the draw step still fits
  390x844 at text scale 1.5. `test/game_felt_test.dart`.
- **The discard pile and the deck** (J5, `GameTableArea.step`, `TableStep`): the pile is
  labelled "À prendre ensuite" and dimmed while the player plays; in the draw step the
  felt takes an amber edge, says "Touche une carte pour la prendre, ou la pioche", the pile
  goes to full opacity, the card the draw will take (`takeCard`, the one the button names —
  never a pick the pile no longer holds) adds "Prendre 7♥ ajoute 7 points à ta main", or for
  a joker "0 point pour ZapZap, mais 25 en fin de manche si ta main n'est pas la plus
  basse", and the deck (`Key('draw-deck')`, moved from the hand onto the felt) is a target
  of its own — `GameProvider.draw(fromDeck: true)` draws from the deck even with a discard
  card picked, and keeps that pick if the draw is refused.
- **The hand-size choice** (T1, T2, `GameHandSizeSelector`): 58 × 50 buttons (≥ 48 dp)
  instead of chips, a line on what the choice changes ("Moins de cartes, ZapZap plus
  vite ; plus de cartes, plus de combinaisons"), and "Distribuer N cartes".
- **Compact opponents** (J6, `GamePlayerTable`): one line per player in turn order from the
  round's starting player (`orderedPlayers`), each a small card back and the count
  instead of a row of backs, a bar of the total towards 100 (red above 80, full once out)
  and the total; the player to move on an amber edge. Every line has the same height
  (`GamePlayerTable.rowHeight`, from the text scale), whatever it holds — a "Toi" badge,
  a card back or "Éliminé".

### The end of a round and of the game (`widgets/game_round_end.dart`)

The port of `frontend/src/components/Game/RoundEnd.jsx`, fed by `GameBoard.jsx:374-400`.
`GameScreen._roundOver` builds it from `GameState` alone — never from the answer of
`zapzap`, whose `scores` were the running totals on Node and the round's own points on Rust
(API layer, above; both send the totals since 2026-09-24). It is the `finished` mode of the board, not a route: the phase is
reached and left by `currentAction`, which every move and the other clients' `roundStarted`
change. A failed refresh leaves it on screen under the stale banner, as any other mode.

- **A player's round score** is `roundScores[index]`, else 0 for `lowestHandPlayerIndex`
  and `handPoints[index]` for everybody else, as React reads it. Players are laid out
  lowest round score first; ties keep turn order, which `List.sort` alone does not promise.
- **A table, not a card per player** (F1 of the UX study, 2026-09-23): one row per
  player — rank, name, the revealed hand (`allHands`) in miniature (22 px `PlayingCard`s
  that overlap as much as the column needs), `+` this round's points, the total —, under a
  header row; above a 1.2 text scale the miniature goes under the name. Four players and
  the button fit a 360x740 phone without scrolling, eight at a 1.0 text scale.
- **Markers**: a bolt for `zapZapCaller` and a crown for `lowestHandPlayerIndex`, icons with
  a tooltip and a semantic label so a row stays one line; "You" on the caller's own row,
  which is also tinted with an amber edge (`isMe`, from `myPlayerIndex`); Eliminated in
  words, not in colour alone. The rank column replaced the `#1` badge. **Eliminated** is
  `eliminatedPlayers` *or* a total above 100 (`GAME_RULES.md`): Node fills the list, React
  only compares the total, and either alone misses a case. A player who is out never gets
  the Lowest Hand badge, as in React: on the last round of a game Node points
  `lowestHandPlayerIndex` at a seat it has already eliminated, hand empty.
- **The ZapZap banner** is green when the call held and red when it was counteracted, and
  then names who counteracted and spells the penalty out:
  `handValue + (activePlayers − 1) × 5`, where `activePlayers` are those whose total
  *before* the round (`total − roundScore`) was 100 or less. React counts the totals after
  it instead, so it charges a player who was eliminated by this very round. Under its
  title, one sentence says why (F2): held — "their hand was worth n points, the lowest at
  the table: X scores 0"; counteracted — "Counteracted by Y (a ≤ b): hand + penalty". `a`
  and `b` are the hand values the call was decided on, a Joker counting 0
  (`handValue(allHands[i])`, `utils/rules.dart`); `hand` is `handPoints`, where the backend
  counts it 25 — so a caller holding a Joker reads "(1 ≤ 1): 26 + 15".
- **The danger zone** (F3): under each row a bar of the total towards 100, amber, red above
  80 (`RoundEndScoreBar`), full once the player is out.
- **Totals climb** (F5): the total and its bar go from `total − roundScore` to `total` in
  400 ms (`TweenAnimationBuilder`), at once when `MediaQuery.disableAnimations` is set.
- **The way on is pinned** under the scrolling table (F4): Next round (`POST /nextRound`,
  disabled while a move is in flight) with "Round n+1: X picks the hand size" above it, or,
  once `gameFinished`, Back to games, the winner banner (`winner.username`, its final
  score) heading the page. X is the seat after this round's `startingPlayer`, skipping
  whoever is out (`GAME_RULES.md` "Subsequent Rounds", `src/use-cases/game/NextRound.js`).
- Every name is `Flexible` inside its `Row` and every figure a `FittedBox`: a `Row` that
  sizes itself to its children hands an unbounded width to its text, which then runs off a
  360 px phone at a 1.5 text scale. `test/game_round_end_test.dart` proves F1–F5 at 360x740
  at text scales 1.0, 1.5 and 2.0.
- Checked in the PWA (2026-09-23, Chromium at 360x740, the web build against a stand-in API
  answering a finished round): the held and the counteracted round as in the study's
  mockup.

### History and statistics

The port of `frontend/src/components/History/GameHistory.jsx`, `GameDetails.jsx` and
`components/Stats/Statistics.jsx`. Three routes, all behind the session:
`/history`, `/history/:partyId` (`AppRoutes.gameDetails(partyId)`) and `/stats`.

- **`AsyncSection<T>`** (`widgets/async_section.dart`) is the one loading/failed/empty shell:
  a `FutureBuilder` plus a retry button and an `isEmpty` test. A section holds **one** read,
  so the statistics screen's three reads stand or fall on their own — a failing leaderboard
  leaves the personal figures and the bots. Its `errorMessage` is a function of the
  exception, never the backend's text: the game details map `ApiErrorCode.notFound` to
  "this game cannot be found" and everything else to a generic failure.
- **`startRead(future)`** (same file) returns the future after `ignore()`. An `AsyncSection`
  subscribes only on the next build, so a read that fails before that frame would be an
  unhandled zone error (and a red widget test). Every screen starts its reads through it.
- **History** (`screens/history_screen.dart`): a `SegmentedButton` over `HistoryTab.mine`
  (`GET /history`) and `.public` (`GET /history/public`), each row a `HistoryGameTile`
  (`widgets/history_game_tile.dart`) that opens the details — `push`ed, so Back returns
  to the list. The three screens carry `ZapZapAppBar` (presence, connection, the menu)
  with a back button that pops (`popOrGo`: to the list, or the history for the details,
  when opened by a link); the statistics are reached from the history through the menu,
  and Back unwinds them one at a time. Node fills `winnerFinalScore`
  and `totalRounds`, Rust neither, so the tile leaves out what is `null`.
- **My result first (H1–H3 of the UX study, `feat/flutter-history-ux`).** On My games each
  `HistoryGameTile` opens on a `PlacementBadge` ("1er"/"4e", amber when I won) and shows
  my score beside the winner's. Rust sends `userPlacement`/`userScore`; Node sends
  neither, so `myPlacement` (`widgets/history_game_tile.dart`) falls back to 1 when
  `winnerUserId` is mine and the badge is left out otherwise — on production (Node) only
  wins get a badge. The public tab shows no place. The list opens on `HistorySummary`
  (`widgets/history_summary.dart`): games and wins from `GET /stats/me` (the whole record,
  not the page of entries), the best place (1 as soon as the record holds a win, else the
  best `myPlacement` of the page), `—` for what is not known; tapping it `push`es
  `/stats`. My games has its own empty state, `HistoryInvite` ("your next finished games
  will show up here", a link that `push`es `/parties/new`), also at the end of a list
  shorter than `HistoryScreen.inviteBelow` (3); the public tab keeps `AsyncSection`'s
  empty message. Ordinals go through `placementLabel`: the ARB `plural` has no `=3`, so
  `historyPlacement` is a `select` on first/second/third/other.
  > **Status: Outdated** (2026-09-24) — Node sends `userPlacement`/`userScore` on
  > `GET /history` now, so production shows the place of a lost game too; the
  > `winnerUserId` fallback only serves an older Node. `test/fixtures/history_list.json`
  > carries both fields (Vincent, 3rd, 122).
- **Game details** (`screens/game_details_screen.dart`): the summary (winner banner,
  players, rounds, end date, visibility), `HistoryStandings` (finishing order, `RankBadge`
  gold/silver/bronze, ZapZap record, final score) and `HistoryRoundsTable` — a `DataTable`
  in a horizontal scroll view, one row per round and one column per player in standings
  order, each cell the round's points over the running total plus the markers (bolt green
  or red for a ZapZap that held or not, a crown for the lowest hand, a cross for an
  elimination; the points are red when counteracted, else green on the lowest hand —
  red first, because a caller tied for the lowest hand is counteracted all the same
  (`GAME_RULES.md`, Tie Handling), and the local database has such rows; React has it the
  other way), with the legend under it. The app bar takes the game's name once the read lands.
- **Statistics** (`screens/stats_screen.dart`): `StatsPersonal` (`GET /stats/me`: two
  `HeroStat`s — wins / games, the average score — then `StatLine`s for the win rate, the
  best score and the rounds, then the ZapZap block: a bar of successful over called and,
  with no call yet, the rule of when one may call — St1, St2 of the UX study),
  `StatsLeaderboard` (`GET /stats/leaderboard?minGames=1&limit=20`, React's own query) and
  `StatsBots` (`GET /stats/bots`) — totals, a `ChoiceChip` per difficulty found in the
  answer, a card per difficulty with its strategy, and the per-bot breakdown once one is
  picked; a reload that no longer carries the picked difficulty falls back to all of
  them. `difficultyStyle` (`widgets/stats_bots.dart`) holds the eight known difficulties'
  name, strategy and colour and falls back to the raw name, so a new bot kind shows rather
  than breaks.
- **My row in the leaderboard**: `LeaderboardRow.isCurrentUser` from
  `AuthProvider.user?.id`, as React compares it against its own `useAuth()` user
  (`frontend/src/components/Stats/Statistics.jsx:8`, `:194`).
- **Formats** (`utils/date_format.dart`): dates through `intl` in
  `Localizations.localeOf(context)` (React hard-codes `fr-FR`) — the models already turned
  the backend's Unix seconds into UTC `DateTime`, so only `toLocal()` is left; the clock
  is the locale's (`add_jm`: `14:26` in French, `2:26 PM` in English); percentages
  `(v*100).toStringAsFixed(1)`, as React; `Formats.number` for a score or an average
  (`134`, not `134.0`; `12.5`); `—` for a missing value.
- Shared presentation lives in `widgets/stats_common.dart`: `SectionCard`, `StatTile`,
  `StatTileGrid` (2 columns under 640 px, 4 above), `HeroStat`, `StatLine`, `RankBadge`, `GoldenScoreChip`,
  `MiniStat` and `StatsColors` — the green/red/purple/cyan accents of the React screens,
  kept out of `utils/app_theme.dart` because they belong to these screens only.
- **Every text beside another in a `Row` is `Flexible`**: a name, a figure or a label that
  is unconstrained overflows on a 360 px phone as soon as the system font is large — the
  standings' ZapZap record, the tiles' facts, the legend items, the leaderboard's win-rate
  column and the personal ZapZap header. In `SectionCard` the trailing badge is `Flexible`
  too, and `GoldenScoreChip` ellipsizes: with `Expanded` on the title alone the badge takes
  what it asks for, squeezes the title into a column of single letters and is clipped
  anyway. `test/history_screens_test.dart` and `test/stats_screen_test.dart` each end on a
  `phone width` group at 360×740, at text scale 1, 1.5 and 2.0, scrolling to every card so
  it really lays out; an overflow is a layout error, which fails the test. At 2.0 the
  standings score is `Flexible` beside the name (alone it took the whole row), the rounds
  table's rows have no maximum height (`dataRowMaxHeight: double.infinity`, a fixed 76
  clipped a cell) and the winner label wraps beside its icon.
- **Text scale**: every screen is pinned at 360×740 at text scales 1.5 and 2.0, the
  largest Android offers. The screens with no phone group of their own — home, splash,
  login, register, not-found and the game screen's loading, load-failed and "not started"
  states — are in `test/text_scale_test.dart`, which also checks their key controls lie
  inside the screen: a clip inside a fixed-size box raises no overflow error.

### Admin (`screens/admin_screen.dart`, `widgets/admin_users.dart`)

The React counterparts are `frontend/src/components/Admin/{AdminRoute,AdminLayout}.jsx` and
`Users/UserList.jsx` ([[Frontend]]).

- **Routes** (`lib/router.dart`): `/admin` opens the Users tab; `/admin/users`,
  `/admin/parties`, `/admin/statistics` (`AppRoutes.adminTab(AdminTab)`) open that tab, any
  other `/admin/<x>` is the not-found screen. `authRedirect` sends a session without
  `isAdmin` to `/parties` before any of them builds. The guard is cosmetic: the backend
  refuses every `/api/admin` call to a non-admin ([[Api]]).
- **`AdminScreen`**: `ZapZapAppBar` with a back button (`popOrGo(/parties)`), then a
  scrollable `TabBar` (Users, Parties, Statistics — keys `admin-tab-*`) over an
  `IndexedStack`, so the users list keeps its page and search while another tab shows. A
  tab change does not change the URL. Parties and Statistics are "Coming soon"
  placeholders (`admin-parties-placeholder`, `admin-statistics-placeholder`) until their
  entries land.
- **`AdminUsersView`**: `GET /admin/users?limit=50&offset=` (`AdminUsersView.pageSize`),
  the total, a search field (`admin-users-search`) that filters the page on show by
  username, case-insensitively, as React does; Previous / `first–last sur total` / Next
  (`admin-users-previous`, `-range`, `-next`) when the total passes 50. A row
  (`AdminUserTile`, `admin-user-<id>`): name, a "Toi" badge on one's own, an Admin badge,
  created, last login ("Jamais connecté" when null), games and play time (`2h 5m`, React's
  format). Toggle admin (`admin-toggle-<id>`) and delete (`admin-delete-<id>`) show on
  every row but one's own and `admin`'s (`AdminUsersView.defaultAdmin`, the account Node
  never lets anyone delete, `src/use-cases/admin/DeleteUser.js:46`); each asks first in an
  `AlertDialog` (`admin-confirm-ok`), then posts and reloads the page. A refusal is a snack
  bar and the list stays: `adminErrorText` maps 400 (Node's code-less refusal for oneself
  or the default admin) to "Action refusée", `ADMIN_REQUIRED`/403, 404 and no answer to
  their texts. A failed first load is an `ErrorBanner` with Retry. A deleted last row of a
  later page goes back a page.

### Android (`frontend-flutter/android/`)

- **Debug only** for now: no release signing (the `release` build type still signs with the
  debug key, as generated), no store.
- Application id and namespace `com.zapzap.app` (`android/app/build.gradle.kts`);
  `MainActivity` in `android/app/src/main/kotlin/com/zapzap/app/`. Label `ZapZap`.
- `INTERNET` is in the **main** manifest (`android/app/src/main/AndroidManifest.xml`), so
  every build type reaches the API, not only debug.
- Cleartext HTTP is allowed in the **debug** build only: `android/app/src/debug/AndroidManifest.xml`
  sets `android:networkSecurityConfig` to `android/app/src/debug/res/xml/network_security_config.xml`
  (`cleartextTrafficPermitted="true"`, system CAs). Profile and release keep Android's
  default, HTTPS only — so they only talk to the production default URL or an `https://` one.
- The app sends no `Origin` header, which the Node CORS accepts (`src/api/server.js:39-40`).
- Launcher icon: the lucide `zap` bolt (the React client's icon set) in amber `#fbbf24` on
  slate `#0f172a`. Sources `frontend-flutter/assets/icon/icon.svg` and `icon_foreground.svg`
  (adaptive-icon foreground, inside the safe zone); the PNGs next to them are rendered with
  `rsvg-convert -w 1024 -h 1024 <x>.svg -o <x>.png`, then `dart run flutter_launcher_icons`
  (config in `frontend-flutter/flutter_launcher_icons.yaml`, not in `pubspec.yaml`) writes
  the `mipmap-*`, `drawable-*` and `values/colors.xml` resources.
- `test/android_config_test.dart` pins the id, the main-manifest `INTERNET` and the
  debug-only cleartext.
- Emulator: `~/sdk/android` has an `android-31` `google_apis` x86_64 image but no AVD, and
  the emulator needs KVM (`/dev/kvm`, group `kvm`); without it, check the APK instead:
  `~/sdk/android/build-tools/36.0.0/aapt2 dump badging <apk>` (package, label,
  permissions) and `aapt2 dump xmltree --file AndroidManifest.xml <apk>`
  (`networkSecurityConfig` present in the debug APK only).

### Theme (`frontend-flutter/lib/utils/app_theme.dart`)

Dark only, from `frontend/tailwind.config.js`: slate `#0f172a` (background), `#1e293b`
(surfaces), `#334155`, `#475569` (outline); amber `#fbbf24` (primary), `#f59e0b`, `#d97706`;
the table felt is Tailwind green-900 `#14532d` / green-800 `#166534`. Icons are Material
(the React client uses lucide). The game board's felt has its own tokens: `feltCenter` `#1c7a45` /
`feltEdge` `#0b3b1f` (its radial gradient), `feltFleckLight`/`feltFleckDark` (the texture),
`feltWatermark`, and the rim's `rimLight` `#5b3a22` / `rimDark` `#2b170b` and `rimInlay`
`#8a6a3a`; `table`/`tableLight` stay for the theme's `tertiary`.

### Cards and play rules

- Ids as the backend's (`GameRules`): 0-51 = suit `id ~/ 13` (spades, hearts, clubs,
  diamonds) × rank `id % 13 + 1` (Ace 1 .. King 13); 52 red joker, 53 black joker
  (`lib/models/card.dart`). Value = rank; joker 0, or 25 with `penalty: true`.
- `analyzePlay(List<int>)` (`lib/utils/rules.dart`), ported from
  `frontend/src/utils/validation.js` and checked against `GAME_RULES.md`: a single card; a
  same-rank group ≥ 2, jokers wild, all-joker groups valid (as the backend); a one-suit
  sequence ≥ 3, jokers filling gaps or extending an end, Ace low only, no K-A wrap, at most
  13 cards. It returns a `PlayType` and, when refused, a `PlayError` code that the UI turns
  into text with `playErrorMessage` — no message in `rules.dart`.
- **Stricter than React:** a repeated id (`[c, c]`) is refused (`PlayError.duplicateCard`);
  React and the Rust backend accept it ([[GameRules]]).
- `isZapZapEligible`: hand ≤ 5 with jokers 0. Final scoring is not ported (the backend
  computes it); `counteractPenalty(activePlayers)` is, only to warn before a call (above).
- Widgets: `PlayingCard` (height = width × 1.4, radius 5 % of width ≥ 2; selected: a 2 px
  amber edge drawn in front of the face and a small amber glow; opacity 0.5 and no tap when
  disabled; a localised semantics label whose `onTap` is the card's tap — none when
  disabled, so a screen reader selects a card as a finger does);
  `CardBack` (sizes `xxs` 16 … `lg` 80 px, as `CardBack.jsx`; a painted red lattice, no
  asset); `CardFan` (the hand — no longer the arc of `CardFan.jsx`: cards a quarter of the
  width wide, 76 to 96 px, overlapping left to right with a step of ¾ of a card, never
  less than 48 px of each left visible; a hand that cannot keep 48 px on one row goes onto
  balanced rows — 7 cards at 360 px are 4 + 3 —, each row drawn over the lower half of the
  one above; a row bows 4 px down at its ends; a selected card rises 20 px and keeps its
  place in the paint order, so its neighbours stay as easy to tap; `CardFan.layoutFor(n,
  width)` gives each card's rect and its visible part; `CardFan.itemKey(i)`; `compact`, the
  hand in the draw step on a phone: one straight row of opaque cards at most 48 px wide, no
  lift). The sizes are
  tokens, `CardSizes` in `utils/app_theme.dart`: hand 76–96, 48 visible, compact 48, the
  felt's cards 70 px on a phone and 84 on a wide board (the deck `CardBackSize.md`), the
  cards played this turn 49 on a phone in the draw step, lift 20, edge 2.
- Faces: `frontend-flutter/assets/cards/<rank>_of_<suit>.svg` — the CC0 "English pattern"
  deck by Dmitry Fomin (Wikimedia Commons) — and `joker_red.svg` / `joker_black.svg`, David
  Bellot's LGPL SVG-cards jokers reframed into the faces' `0 0 360 540` frame (same outline,
  same scale for both, no `<use>`, `<text>` or `<style>`); rendered with `flutter_svg`,
  stretched into the width × 1.4 box (`BoxFit.fill`). `frontend/public/joker-*.svg` are the
  same bytes. Licence and the changes made: `frontend-flutter/THIRD_PARTY.md`. The 54 files
  weigh 1.32 MB after `svgo` (the jokers 31.6 and 24.5 KB); the twelve court cards are
  1.15 MB of it. `test/card_widgets_test.dart` pins the jokers' frame and pumps them beside a
  face at 38 and 80 px.

### Localisation

- `frontend-flutter/l10n.yaml`: `arb-dir: lib/l10n`, template `app_fr.arb`,
  `nullable-getter: false`. French is the default: `resolveLocale` (`app.dart`) picks the
  device's language when it is `fr` or `en`, else `fr`.
- **No user-facing string literal outside `lib/l10n/`**: every text goes through
  `AppLocalizations.of(context)`. The React client mixes French and English; the port
  unifies them in the ARB files.
- The generated `lib/l10n/app_localizations*.dart` are **not committed**
  (`frontend-flutter/.gitignore`): `flutter gen-l10n` writes them. A `flutter pub get`
  sometimes does too, but not reliably (not when it finds nothing to resolve), and `flutter
  analyze` never does (checked 2026-09-22): after an ARB change, run `gen-l10n`. CI, the
  commit gate and `worktree_setup.sh` run it explicitly. Keeps parallel pull requests that
  each add strings free of conflicts in generated code.
- `test/l10n_test.dart` fails when a key is in one ARB file and not the other, and when
  a French message says "vous" (`vousMarkers`: vous, votre, vos, êtes, faites, dites and
  any word ending in "-ez", but not "rendez-vous", "chez", "nez", "assez").
- **The French client says "tu"** to the player, everywhere: "Toi", "à toi de choisir",
  "Choisis…", "Ce n'est pas ton tour.", "Réessaie.".

### The PWA image (`frontend-flutter/Dockerfile`, `frontend-flutter/nginx.conf`)

- Stage 1 is `debian:bookworm-slim` + the official Flutter SDK archive, **pinned to 3.47.2**
  with its sha256 (`ARG FLUTTER_VERSION`, `ARG FLUTTER_SHA256`) — the version
  `.github/workflows/ci.yml` pins; bump the two together. It builds as a non-root user
  (`flutter` and `pub` refuse to run as root), runs `pub get --enforce-lockfile`, `gen-l10n`
  and `flutter build web --release --base-href /app/ --no-web-resources-cdn`.
- **`--no-web-resources-cdn` is load-bearing**: without it the bundle fetches CanvasKit from
  `www.gstatic.com` at runtime, so a client with no route to Google shows a blank page while
  the 36 MB `canvaskit/` in the image goes unused. The CI `flutter` job passes the same flag,
  so it builds what the image builds.
- Stage 2 is `nginx:alpine` with the bundle at `/usr/share/nginx/html/app`, so a request path
  matches the public one. `frontend-flutter/nginx.conf`: `/healthz` for the container health
  check, `/app` → relative 301 `/app/` keeping the query (`$is_args$args`),
  `no-cache, no-store, must-revalidate` on `index.html`, `flutter_bootstrap.js` and
  `flutter_service_worker.js`, `no-cache` on the rest, a 404 (not the fallback) under
  `/app/assets/`, `/app/canvaskit/`, `/app/icons/` and for any path with a file extension,
  and the SPA fallback `try_files $uri $uri/ /app/index.html` for everything else under
  `/app/`. The extension rule is what keeps the smoke test honest: with a blanket fallback a
  deleted icon or `main.dart.js` answers 200 `text/html` and every status check still
  passes.
- `web/manifest.json`: `start_url` and `scope` `/app/`, `id` `/app/`, `display` standalone,
  `#0f172a`, and the four icons below. Chrome reports no installability error for it
  (checked with `Page.getInstallabilityErrors` against the built image).
- `web/icons/Icon-{192,512}.png` are rendered from `assets/icon/icon.svg`,
  `Icon-maskable-{192,512}.png` from `assets/icon/icon_maskable.svg` (the bolt inside the
  66% safe zone on the slate background), `web/favicon.png` from `icon.svg` at 64 px:
  `rsvg-convert -w <n> -h <n> assets/icon/<x>.svg -o web/<path>`.
- `scripts/pwa_image_smoke.sh [image]` runs the built image on a free port and checks all of
  that (35 checks); the `image` CI job runs it. It asserts content types, not only statuses,
  the exact `Cache-Control` value (an `add_header` beside an `expires` emits two), that a
  missing file 404s, and that CanvasKit comes from the bundle.
- Deep links are path URLs (`usePathUrlStrategy()`, above): `/app/parties` and
  `/app/history/<partyId>` open their screen from a cold tab or a reload, the fallback
  serving `index.html` and the app reading the route off the path. No in-app URL carries
  `#`. The extension rule is why a route may never contain a dot.

### Build and test (from `frontend-flutter/`)

| Command | What |
|---|---|
| `dart format lib test` | the formatter; `--output=none --set-exit-if-changed` is the gate (hook and CI) |
| `flutter analyze` | lints, must be clean |
| `flutter test` | `test/api_config_test.dart`, `test/app_test.dart` (routing, fr/en, theme), `test/l10n_test.dart`, `test/android_config_test.dart`, `test/api_client_test.dart` (Bearer, 401 → `onUnauthorized`, network, timeout), `test/api_exception_test.dart` (every error shape), `test/models_test.dart` (every model from the fixtures, plus the Rust shapes), `test/repositories_test.dart` (each route's method, path, body), `test/auth_utils_test.dart` (validators, JWT), `test/auth_provider_test.dart` (restore, login, logout, parallel 401s, the web storage), `test/auth_screens_test.dart` (login/register widgets — C1–C4: the pitch, validate on submit with an active button, the eye, Next/Done and the `AutofillGroup`, the spinner and the banner above the button, at 360×740 at text scales 1.0 and 1.5 —, the guard: expired JWT, admin, `from`), `test/create_party_form_test.dart` (the name's refusal: none on opening, on Create, on leaving the field); `test/auth_helpers.dart` builds unsigned test JWTs, `test/sse_parser_test.dart` (line format, split chunks), `test/sse_event_test.dart`, `test/sse_client_test.dart` (fake transport `test/sse_fakes.dart` + fake_async: token, 3 s reconnect, disconnect, token change; `SseProvider`), `test/sse_transport_io_test.dart` (`MockClient.streaming`: headers, chunks, non-200, idle timeout), `test/connection_indicator_test.dart`, `test/sse_session_test.dart` (the channel follows sign-in, logout, a new token), `test/party_provider_test.dart` (seat assignment — never the same bot twice, "none available", freeing a seat —, the create body, join on `ALREADY_IN_PARTY`, the lobby's events and its owner/only-human rules, two lobby loads answering out of order, presence and its five-player cap on the first load), `test/party_screens_test.dart` (the three screens end to end over `test/party_helpers.dart`'s fake backend (its `partiesGate` holds `GET /party` back): cards and their buttons, seat selectors, start disabled below 3, a player joining through the stream, start/leave/delete, a failed first load, a row without `maxPlayers`, `NOT_IN_PARTY`, no presence count before the first answer, the system Back from the form, the lobby and the game (`back navigation`), and that each screen fits 360×740, and 360×740 again at text scales 1.5 and 2.0), `test/parties_ux_test.dart` (P1–P4 in Roboto at 360×740, text scales 1.0 and 1.5: my games first and the running one on top with its badge and amber border, no "your turn" badge, two-line cards with one button — Resume filled, Lobby and Join outlined —, the amber Create button clear of the last card, the skeletons, the invitation and its push to the form, pull-to-refresh, a failed refresh keeping the list), `test/lobby_ux_test.dart` (S1–S4 in Roboto at 360×740, text scales 1.0 and 1.5: the invite code and Copy to the clipboard, the settings chips on one line, the online dots, the bot level chip, the free seat's hint and no add-a-bot button, the reason line, Start above Leave on screen, Delete only in the ⋮ menu and still confirmed), `test/card_test.dart` + `test/rules_test.dart` (the React utils tests, ported), `test/card_widgets_test.dart` (every face of the 54 ids parses and renders; card — its amber edge, a screen reader's tap, none when disabled —, back, fan — widths, balanced rows, 48 px visible for 1 to 13 cards at 300 to 600 px, a tap at the centre of each visible part, the lift that keeps its place), `test/game_provider_test.dart` (the derived table, the selection and its reset, each move's body, a refused move that keeps the table, a failed refresh that keeps it too, two loads answering out of order, a discard card gone from the pile that is not posted, the hand-size range, the events — `partyStarted` included), `test/game_screen_test.dart` (the board end to end over `test/game_helpers.dart`'s fake backend: each mode, my turn and not my turn, an invalid play that keeps the board, a backend refusal in a snack bar, a ZapZap that held, a counteracted one with its penalty, a finished game with its winner, a refresh that fails leaving the table under its banner, Clear dropping the discard card, a Golden Score that ends pulling the hand size back into range, Back leading to the parties — from the list, popped and replacing the game's browser entry —, the cards (seven in hand at 360×740: 76 px or more, a tap at the centre of each visible part selects that card; the felt's cards 70 px on a phone and 84 wide, the played ones 49 on a phone in the draw step; a screen reader's tap on `7 de Cœur` in the hand and in the pile, no tap on a disabled hand; at 1.5, no overflow and under 24 px between felt and hand), a waiting client entering the board on `partyStarted` or by Retry, and every mode at 360×740 at text scales 1.0, 1.5 and 2.0, the wide layout at each scale), `test/game_turn_ux_test.dart` (J1–J6, T1, T2: the step chips, the named button, the hand value and its gauge, the ZapZap sheet — cancel and confirm —, the felt in each step and the deck as a target, the hand-size hint and 48 dp targets, the compact opponents at 390×844 and 1280×800 at text scales 1.0, 1.5 and 2.0, and the new pieces at 360×740), `test/game_felt_test.dart` (the casino felt: the radial gradient, the 6 px rim, the painted texture and watermark and no image, the amber draw edge on the rim with a contrast over 4.5 against both ends of the wood, no overflow at 360×740 at 1.5), `test/game_felt_layout_test.dart` (the phone felt in the draw step at 360×740 and 390×844, text scales 1.0 and 1.5, in Roboto: never cut, the deck and the take hint in view; in the draw step, 7 and 10 cards in hand each show their rank-and-suit corner and 60 % of their height; the amber draw button), `test/date_format_test.dart`, `test/history_screens_test.dart` (the two tabs, empty, failed and retried, opening the details; summary, standings, the round table and its legend, a counteracted caller in red even on the lowest hand, the system Back from the details, the signed-in app bar, an unknown game), `test/history_ux_test.dart` (H1–H3, St1, St2: the place badge on Rust and Node entries, my score, no place on the public tab, the fr/en ordinals, the summary and its push to the statistics, the invitation and its push to the create-party form, the hero figures, `134` without `.0`, the ZapZap bar with and without calls, all at 360×740 at text scales 1.0, 1.5 and 2.0), `test/stats_screen_test.dart` (personal figures, my highlighted row and a row that is not mine, the bot filter and its fallback to All, one failing section among three), `test/app_bar_test.dart` (the app-bar menu opens the history and the statistics, the system Back returns to the list, history then statistics unwound one Back at a time, no Admin entry for a player, an admin's leading to `/admin` and Back), `test/admin_screen_test.dart` (a non-admin on `/admin` or `/admin/users` lands on `/parties` with no admin call, the three tabs, `/admin/statistics` and an unknown tab, the placeholders keeping the users list; over a paging fake backend: `limit=50&offset=0`, 50 rows a page of 120 and Next/Previous, the search filtering the page, no actions on one's own row and `admin`'s, grant then revoke with the body sent, cancel sends nothing, delete, a 400 refusal in a snack bar, a failed load and Retry; the users tab at 360×740 at text scales 1.0, 1.5 and 2.0), and a `phone width` group in each at 360×740, text scale 1, 1.5 and 2.0; `test/text_scale_test.dart` (home, splash, login, register, not-found and the game screen's three message states at 360×740, text scale 1.5 and 2.0); `test/history_helpers.dart` builds a session for a given user id and an `ApiClient` routing each path to a fixture |
| `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:9999` | the web client against a local backend |
| `flutter build web --base-href /app/` | the PWA → `build/web/`, to be served under `/app/` |
| `flutter run -d <device> --dart-define=API_BASE_URL=http://10.0.2.2:9999` | the Android debug app on an emulator, against a backend on the host |
| `flutter build apk --debug` | `build/app/outputs/flutter-apk/app-debug.apk`; needs the Android SDK (`~/sdk/android`). Add `--dart-define=API_BASE_URL=http://<LAN IP>:9999` for a device on the LAN; without it the APK talks to production over HTTPS |
| `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/play_round_test.dart -d web-server --dart-define=API_BASE_URL=http://localhost:<port>` | the end-to-end test: a fresh user plays a round against two bots on a live backend; needs the backend and a chromedriver — procedure in [[Testing]] |
| `docker build -t zapzap-frontend-flutter:ci .` then `scripts/pwa_image_smoke.sh` (from the repository root) | the PWA image and its smoke test |

Build outputs (`frontend-flutter/build/`, `.dart_tool/`) are ignored by the root and the
project `.gitignore`.

## Decisions & History

- **The game felt is a casino table (2026-09-24, `feat/flutter-casino-felt`).** Next to
  the enlarged cards the plain green gradient looked dull. Painted rather than an image:
  no asset to ship in the PWA and the APK, and the felt scales to any size. The amber edge
  of the draw step stays the felt's own border, drawn over the texture and against the dark
  rim, rather than moving onto the rim: the tests that prove the edge is never cut keep
  their meaning. The padding given back keeps the draw step whole at 390x844, text x1.5.

- **Presence count (2026-09-24, `fix/flutter-connected-count`).** The app bar read 0 for a
  lone signed-in player on Node: the sign-in `GET /players/connected` answered before the
  stream was registered, and Node broadcast `userConnected` before subscribing the new
  stream, so the client never learnt of itself; any stream of a user closing (a second tab,
  the PWA's first-load reconnection) also removed a user who was still connected. Fixed on
  both sides — Node counts streams per user and subscribes before broadcasting, the client
  reloads the list on each connection — so the client is right against the Rust backend
  too, which keeps the old server behaviour for now.

- **Node's `GET /history` sends the caller's place and score (2026-09-24,
  `fix/node-history-user-placement`).** The Rust parity fields were missing on the backend
  production runs, so a lost game showed no place. `getFinishedGamesForUser` already joined
  `player_game_results`; the use case now maps `user_position`/`user_final_score`. The
  fixture was regenerated from a local Node (`PORT=9911`) on a database seeded with the
  fixture game's ids and scores, not from a replayed game.
- **Flutter client decided (2026-09-22).** The user wants an Android app and a PWA at parity
  with the React client. The PWA goes on the same domain under `/app/` (same origin as the
  API, no CORS change to the backend) while React stays on `/`; Android is debug-only for
  now. French and English from day one.
- **CI job and commit gate (2026-09-22, `chore/flutter-ci-gates`).** The commit gate is the
  analyzer only (seconds); the tests and the two builds are CI's. No image flag: the client
  was not deployed yet.
  > **Status: Outdated** (2026-09-23) — `frontend-flutter/*` now also raises the `image`
  > flag, and the `image` job builds the PWA image and smoke-tests it.
- **The PWA image builds the SDK in, rather than reusing a published Flutter image
  (2026-09-23, `feat/flutter-pwa-deploy`).** `ghcr.io/cirruslabs/flutter` publishes no
  `3.47.2` tag, and a floating tag would silently change the SDK under the deploy; the
  official archive plus its sha256 pins it exactly. The bundle also gets its own image and
  container rather than being copied into the React one, so the two clients are built and
  rolled back separately ([[Deployment]]).
- **The end of a round is a table (2026-09-23, `feat/flutter-round-end-ux`).** The UX
  study (F1–F5) found a card per player, ~200 px each, showed three players of four and
  made comparing a matter of scrolling. A table row per player, the result in one sentence,
  the player's own row and a bar towards 100, the button pinned with who deals next, and
  totals that climb, all in the existing theme. The badges of the lowest hand and the
  caller became icons so a row stays one line.
- **The turn reads itself (2026-09-23, `feat/flutter-turn-ux`).** The UX study found three
  buttons of equal weight lighting up in turn, a hand header of two numbers of which one
  counts, a ZapZap that went off without a word of its risk, and rows of card backs that
  had to be counted. One named primary button per step rather than three: the step
  indicator says which step it is, so the button can say what it does. The deck moved from
  the hand to the felt, beside the pile, so the draw step has one place to look. The new
  strings say "tu", as the mockups the user approved; the rest of the app still says
  "vous" (a wip entry). `gameHandValues`, `gameZapZapEligible`, `gameTurnPlay`,
  `gameTurnDraw`, `gamePlayButton`, `gamePlayButtonCount`, `gameTakeButton`,
  `gameTableDiscardLabel` and `gameSeatCards` lost their callers and were dropped. Absorbed:
  the player-list entry of 2026-09-22 (one equal-height line per player, turn order from
  the round's first player).
  > **Status: Outdated** (2026-09-23) — the whole app says "tu" now (the entry below).
- **Tutoiement everywhere (2026-09-23, `chore/flutter-tu-voice`).** The user chose "tu",
  as in the UX study, over the "vous" the first screens used: on the board, the "Vous"
  badge sat next to "Ton tour". Twenty French strings changed wording only, no key was
  renamed, and English is unchanged. `test/l10n_test.dart` keeps "vous" out of
  `app_fr.arb`.
- **The web icons are the launcher icon (2026-09-23).** Flutter's default web icons shipped
  until then; they are now rendered from the same `assets/icon/` SVGs as the Android
  launcher icon, plus a maskable variant for the install prompt.
- **API layer (2026-09-22, `feat/flutter-api-client`).** Models parse both backends
  leniently rather than one strictly: production runs Node, the target is Rust, and their
  shapes differ in types more than in names. The 401 hook is a plain callback on
  `ApiClient`, not a dependency on the auth provider, so the client has no knowledge of
  routing and the auth pull request only has to set it. Error text stays out of the UI:
  screens map `ApiException.code` to ARB strings.
- **Session and guard (2026-09-22, `feat/flutter-auth`).** The guard checks the JWT's `exp`,
  which React never does, so an expired session goes to login instead of failing on its
  first call. The router follows `AuthProvider` (`refreshListenable`) rather than screens
  navigating after login or logout, so a 401 anywhere lands on login the same way a logout
  does. The splash route exists so a deep link survives the asynchronous storage read at
  start-up. Secure storage on Android only: the web has no secure store, and the React
  client keeps the same token in localStorage.
- **Real-time channel (2026-09-22, `feat/flutter-sse`).** One connection per signed-in
  session with the token, rather than React's one per screen without it: presence needs the
  token, and the stream is global anyway. Two transports because `package:http` on the web
  does not stream a response the way `EventSource` does, and Android has no `EventSource`.
  The reconnection lives in `SseClient`, not in the transports, so both platforms retry on
  the same 3 s and a fake transport tests it. The idle timeout exists only on Android:
  `EventSource` notices a dead connection itself.
- **Card faces from SVG assets (2026-09-22).** React draws faces with the `cardmeister` web
  component, which Flutter cannot use; the CC0 English-pattern deck was picked over drawing
  faces in code. `analyzePlay` returns codes, not React's English `reason` strings, so the
  UI localises them.
- **Bellot jokers (2026-09-23, `feat/joker-artwork`).** The home-made 80 × 112 clown
  jokers clashed with the English-pattern faces; the user picked David Bellot's Wikimedia
  jokers. They are bundled, never hot-linked, so the PWA works offline; the red original's
  `<use>` references are inlined because `flutter_svg` support for them is the part least
  worth betting on. At 38 px the "JOKER" index is unreadable, as the faces' indices are, but
  the red jester silhouette tells a joker from any face.
- **History and statistics (2026-09-22, `feat/flutter-history`).** One `AsyncSection` per
  read rather than one loading state per screen: the statistics screen asks three
  independent endpoints and React hides all three behind three flags anyway. The bot
  difficulties come from the answer instead of React's hard-coded list of eight, so a bot
  kind the backend adds appears on its own; only the name, strategy and colour are looked
  up, with a fallback. `StatsColors` sits with the screens rather than in `AppTheme`: they
  are the only users, and the theme is shared with the game board. The leaderboard marks
  the signed-in row, as React does. Review found six rows that overflowed a 360 px phone —
  two of them without any text scaling — so every text beside another in a `Row` became
  `Flexible` and the screens gained a `phone width` test group, as the lobby screens have.
- **Generated l10n not committed (2026-09-22)**, unlike countscore: several Flutter pull
  requests will add strings in parallel, and generated files would conflict on every one.
- **Parties, create and lobby (2026-09-22, `feat/flutter-lobby`).** Each screen owns its
  provider instead of a global one, because the lobby's state is one party's and dies with
  the screen; presence is the exception, being app-wide, and is the only new entry in
  `appProviders`. Navigation out of the lobby goes through one `outcome` field rather than
  callbacks per action, so a button here and an event from another client leave the same
  way. `/game/:id` gets a placeholder screen rather than no route at all, so a started
  party has somewhere to land before the board exists. The app bar deliberately carries no
  History, Stats or Admin entry yet: those routes do not exist, and a dead link is worse
  than a missing one.
- **The game board (2026-09-23, `feat/flutter-game-board`).** One `GameProvider` per party,
  built by the screen like the lobby's, rather than an app-wide one: a board's state is one
  party's and dies with the screen. A refused *move* is a snack bar and the board stays,
  while only a failed *load* replaces it — the React board replaces itself on any error at
  all, which loses the table on a stray 400. The selection lives in the provider alone, so
  the hand and the buttons cannot disagree the way `PlayerHand` and `GameBoard` do. The
  phone layout is `Flexible` sections over scroll views instead of fixed heights: it fits
  360x740 at a 1.5 text scale, which a fixed layout does not, and the tests pump both
  scales because the suite's default size hid two earlier clipping bugs. The end of a round
  was deliberately minimal here and became its own pull request.
  Review of #34 found the headline claim half true: a failed *refresh* still went
  through the same `error` field and took the table away after a move that had landed,
  and two loads in flight could answer out of order and put the board a turn behind.
  Hence three error fields and the generation guard, both above.
- **The admin shell and its users tab (2026-09-24, `feat/flutter-admin-users`).** One
  screen with a `TabBar` rather than a `ShellRoute` per tab: the tabs share nothing but
  the header, and a `go` between shell routes would replace the stack the Android Back
  needs. `/admin/<tab>` exists for deep links only; the URL does not follow a tab change,
  because replacing the route would rebuild the users list and lose its page. Rows are
  cards, not React's 800 px table, so a phone needs no horizontal scroll. The search
  filters the page on show, as React's does, since `GET /admin/users` has no search
  parameter. The client hides the actions on the default admin by name, as React does;
  the backend refuses them anyway. Checked with a throwaway `flutter drive` test against a
  local Node backend on a scratch database: signed in as `admin`, the menu's Admin entry,
  Vincent granted admin then revoked, the badge following each time.
- **App-bar menu rather than icons, and no Admin entry (2026-09-23,
  `feat/flutter-app-bar-links`).** The history and statistics routes exist since #33, so
  the app bar leads to them; a `PopupMenuButton` rather than two more `IconButton`s
  because the bar already carries the presence count, the connection indicator and
  sign-out, and 360 px at a 1.5 text scale leaves no room. `context.push`, not `go`: the
  screen stays on top of the parties list, so the Android system Back button returns to
  it. `/admin` still has only the router guard of #29, so an Admin entry would land on the
  not-found screen — it waits for the admin screen
  (`wip/todo_nr/2026-09-22-flutter-admin.md`), and a test keeps the menu free of it.
  > **Status: Outdated** (2026-09-24) — the admin screen exists (`feat/flutter-admin-users`),
  > and admins get the Admin entry; the test now checks it leads to `/admin`.
- **The end of a round (2026-09-23, `feat/flutter-round-end`).** A widget taking plain
  data (`GameRoundEnd`), not a route of its own: the round's end is a phase of the board,
  reached and left by `currentAction`, and a route would have to be pushed and popped by
  every event that changes it. The standings are read from `GameState` rather than from the
  `zapzap` answer, because the two backends disagree on what that answer's scores mean.
  `lowestHandPlayerIndex` decides the crown, where React looks for the first player who
  scored 0 and is still alive — the same thing until two players tie on 0 — but a player
  the round has just put out never keeps it: checked against the local backend, Node names
  an already-eliminated, empty-handed seat on the last round of a game. The counteract
  penalty is spelled out from the rule (`GAME_RULES.md`) with the players who were active
  *before* the round, which is what the backend charged; React's own arithmetic is wrong
  here (`wip/todo_nr/2026-09-22-react-utils-disagree-with-game-rules.md`). The three ARB
  keys the minimal state used (`gameRoundOverCaller`, `gameRoundScoreLabel`,
  `gameTotalScoreLabel`) were replaced rather than kept: "Manche 49" for a score read as a
  round number.
- **Bigger cards, and the game's exits replace their browser entry (2026-09-24,
  `feat/flutter-bigger-cards`).** At 360x740 the hand's cards were 50 px wide and each
  showed 18 px to the next one: a tap hit the neighbour, and the ranks were hard to read;
  the felt's were 45 px. The user asked for cards larger than the first proposal (64–72
  px): the hand's are now 76–96 px (82 at 360x740), the felt's 70/84. The arc went: with
  rotated cards the part a finger can reach is a skewed sliver, and at these sizes seven
  cards do not fit in one arc on a phone — two flat, overlapping rows keep 48 px of every
  card reachable, which a test taps. A selected card stays in the paint order rather than
  on top, as React draws it: on top, it covered 32 of the 48 px of the next card. The felt
  now fills the height between players and hand, so the ~100 px empty band under it went
  and its cards got the room; in the draw step the hand yields to it (3/20) and the
  duplicate "X a posé N cartes" line is dropped, which keeps the whole draw step in view
  at 360x740 and 390x844 at 1.0. The game's exits called `leaveFor`, `popOrGo` under
  `Router.neglect` (since folded into `popOrGo`): `popOrGo` alone would still have pushed a
  browser entry — checked by the reported route information, which a
  pop sends with `replace: false`. Before/after renders at 360x740 are described in the
  pull request.
- **Back navigation: `push`, and `popOrGo` (2026-09-23, `fix/flutter-back-navigation`).**
  Every screen but the app-bar menu's destinations was reached with `go`, so Android's
  system Back left the app from the form, the lobby, the history, the details and the
  statistics, and one tap on the history's statistics shortcut threw away the stack the
  menu had built. The shortcuts went with the hand-rolled app bars: `ZapZapAppBar`'s menu
  already leads to both. The form's lobby and the lobby's game replace their screen rather
  than stack on it. Absorbed in the same change: the `maxPlayers` fallback, the 3-50 name,
  `NOT_IN_PARTY`, the sequenced lobby loads, the presence count before `loaded`, the
  12-hour English clock, the bot filter reset, and red over green in the rounds table.
  `authErrorNetwork`/`authErrorGeneric` duplicated `errorNetwork`/`errorGeneric` word for
  word, and `backToParties`/`backToHistory` lost their callers to `BackButton`: all four
  keys were dropped.
- **Pushed screens own the URL (2026-09-23, `fix/flutter-pushed-route-urls`).** After
  `push` replaced `go`, the address bar stayed on `/app/parties` under the form, a lobby
  or a game, so a reload dropped the user on the list and a lobby could not be shared.
  go_router advises against `optionURLReflectsImperativeAPIs` because a pushed route's
  path is not always a deep link; here every route is top-level and loads itself from its
  path parameters, so it is. `pushReplacement` alone still added a browser history entry,
  and the browser's Back returned to the replaced form: `Router.neglect` makes it replace
  the entry instead. Checked on a web build behind `frontend-flutter/nginx.conf` against a
  local Node backend on a fresh database: list, form (`/app/parties/new`), lobby
  (`/app/parties/<id>`, history length unchanged), reload on the lobby, Back to the list,
  Back out of the app.
- **Every back button replaces the browser's entry (2026-09-24,
  `fix/flutter-back-replaces-history`).** Only the game's exits used `leaveFor`; the form,
  the lobby, the history, the statistics and the details still popped with a plain
  `popOrGo`, which go_router reports as a new browser entry, so after list → history →
  back the browser's Back reopened the history. `leaveFor` was folded into `popOrGo`.
  Absorbed in the same change: seven ARB keys without a caller since the compact party
  card and the lobby's chips (`partyContinueButton`, `partyReturnToLobbyButton`,
  `partyInProgressButton`, `lobbySettingsTitle`, `lobbyMaxPlayers`, `lobbyHandSize`,
  `lobbyStartButton`) were dropped.
- **The lobby shows its invite code and hides Delete (2026-09-24, `feat/flutter-lobby-ux`).**
  The UX study (S1–S4) found the invite code — the only way into a private party — never
  on screen, a 120 px settings card, seats that did not say who was there, and three
  full-width buttons with a red Delete a thumb away from Leave. The mockup's "add a bot"
  on a free seat was dropped at refinement: no backend route seats a bot in an existing
  party (wip `2026-09-23-add-bot-to-waiting-party`). The party's name left the body: the
  app bar carries it. Checked on a web build against a local Node backend on a fresh
  database at 360×740.
- **History and statistics put my own result first (2026-09-23, `feat/flutter-history-ux`).**
  The UX study (H1–H3, St1, St2) found the history row said who won but not how I did, the
  history and the statistics linked only through the menu, an empty list said nothing to
  do, and six equal tiles made nothing stand out. The texts keep the app's "vous", not the
  mockup's "tu" (outdated: "tu" everywhere since 2026-09-23). The summary's games and wins come from `/stats/me` rather than the
  history, which is one page of entries (Node answers 20 by default).
- **Android: `com.zapzap.app`, cleartext in debug only (2026-09-22).** The scaffold's
  generated `com.zapzap.zapzap` was replaced before any install existed. Plain HTTP is needed
  to reach a local backend from the emulator or the LAN, but a release build must never
  downgrade to it, so the network security config lives in `src/debug/` rather than in the
  main manifest.
- **The parties list puts my games first (2026-09-24, `feat/flutter-parties-ux`).** The UX
  study (P1–P4) found "Continue" and "Join" with the same amber button on the same ~160 px
  card, a running game lost in the list, a Create button over the last Join, and an empty
  list with nothing to do. The study's "your turn" badge was dropped at refinement: the
  list does not carry the current player, and one state call per running party was not
  worth it (`wip/todo_nr/2026-09-23-party-list-current-turn.md`), so the badge says "In
  progress". The second section keeps the "Available games" heading rather than the
  mockup's "Open games": the auth tests land on that text, and the meaning is the same.
  The player count is an icon rather than the word, so the line fits beside the button on
  a phone; the P1–P4 tests load Roboto, as the felt test does, because the test font's
  square glyphs wrap every compact line.
