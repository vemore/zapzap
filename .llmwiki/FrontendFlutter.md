# FrontendFlutter

> Scope: the Flutter client in `frontend-flutter/` — Android app and PWA — its layout, API
> configuration and API layer (client, errors, models, repositories), authentication and
> routing guard, real-time channel (SSE), the parties, create-party and lobby screens, the
> game board, the history and statistics screens, theme, localisation, build and tests.
> Related: [[Architecture]] · [[Frontend]] · [[Api]] · [[Deployment]] · [[Testing]]
> Updated: 2026-09-23

## Facts

### Status

- **Playable.** Home, login, register, the parties list, create-party, one party's lobby,
  the game board (`/game/:id`), the history (`/history`), one finished game
  (`/history/:partyId`), the statistics (`/stats`), a start-up splash and a not-found screen
  (`frontend-flutter/lib/router.dart`), over the API layer, the session and the real-time
  channel (below), up to the end of the round and the end of the game (below). Still
  missing against the React client ([[Frontend]]): Google sign-in, admin.
- **History and statistics are reached from the app-bar menu** of every signed-in screen
  (`ZapZapAppBar`, below) — the history, the game details and the statistics carry that
  bar too, with a back button; the deep links (`/app/history`, `/app/stats`) still work. There is **no Admin entry**: `/admin` has the
  router guard but no screen, so the menu would lead to the not-found screen.
- The card model, play rules and card widgets (below) are what the board draws hands with.
- **The PWA is deployable**: its own image (`frontend-flutter/Dockerfile` +
  `frontend-flutter/nginx.conf`), the `frontend-flutter` service in both compose files, and
  the `/app/` route of the production proxy. See "The PWA image" below and [[Deployment]].
- CI: the `flutter` job (`.github/workflows/ci.yml`, Flutter pinned to 3.47.2 with
  `subosito/flutter-action`, JDK 17) runs `pub get --enforce-lockfile` (a stale
  `pubspec.lock` fails the job), `gen-l10n`, `analyze`, `test`,
  `build web --base-href /app/ --no-web-resources-cdn` (the image's flags) and
  `build apk --debug`. `scripts/ci_scope.sh` selects it
  **and the `image` job** for a path under `frontend-flutter/` (a `.md` there selects
  nothing), because the PWA image is built from those sources ([[Testing]]). It is not yet a required check of the branch protection ([[ParallelDelivery]]).
- Commit gate: `flutter pub get --offline`, `flutter gen-l10n`, `flutter analyze` when the
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
| `utils/validators.dart`, `utils/jwt.dart` | the React username/password rules; the JWT payload and `exp` reader |
| `utils/navigation.dart` | `popOrGo(fallback)`: the back button of a pushed screen; `replaceWith(location)`: a screen taking another's place (Back navigation, below) |
| `utils/date_format.dart` | `Formats`: date and time in the app's locale, percentages, one-decimal numbers (History and statistics, below) |
| `screens/` | `home_screen.dart`, `splash_screen.dart`, `login_screen.dart`, `register_screen.dart`, `parties_screen.dart`, `create_party_screen.dart`, `party_lobby_screen.dart`, `game_screen.dart` (the board), `history_screen.dart`, `game_details_screen.dart`, `stats_screen.dart`, `not_found_screen.dart` |
| `models/card.dart` | `GameCard` (not `Card`: Material has one) — id, suit, rank, value, face asset (below) |
| `utils/rules.dart` | `analyzePlay` / `isValidPlay` / `playType`, `handValue`, `isZapZapEligible`, `handValueDisplay`, `sortCards` (below) |
| `utils/card_l10n.dart` | `CardL10n` on `AppLocalizations`: suit and card names, `playErrorMessage(PlayError)` |
| `widgets/` | `playing_card.dart`, `card_back.dart`, `card_fan.dart` (below); `app_logo.dart`; `auth_form.dart` (the card, submit button and switch link shared by login and register, and the error-code → text mapping); `connection_indicator.dart` (Wifi icon of `SseProvider.connected`); `zapzap_app_bar.dart`, `connected_players.dart`, `party_card.dart`, `player_slot_selector.dart`, `player_seat_tile.dart`, `error_banner.dart` (and `partyErrorText`); `game_player_table.dart`, `game_table_area.dart`, `game_hand.dart`, `game_action_buttons.dart`, `game_hand_size_selector.dart`, `game_round_end.dart`, `game_error_text.dart` (the game board, below); `async_section.dart`, `history_*.dart`, `stats_*.dart` (History and statistics, below) |
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
  `AuthRepository` (login, register, loginWithGoogle — Node only), `PartyRepository` (list,
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
  `auth.js:42-88` live (`utils/validators.dart`: username trimmed, 3-30,
  `^[a-zA-Z0-9_-]+$`; password 6-100, not trimmed): a field shows its refusal once edited,
  and submit stays disabled until both pass. The username is sent trimmed (Node trims it
  too, `src/use-cases/auth/RegisterUser.js:93`). Server refusals map from
  `ApiException.code`: `INVALID_CREDENTIALS`, `USERNAME_EXISTS`, no response
  (`NETWORK_ERROR`/`TIMEOUT`), else a generic text. Success navigates by itself: the router
  follows `AuthProvider`.
- **Routing guard** (`authRedirect(auth, uri)`, run on every navigation and on every
  `AuthProvider` change via `refreshListenable`): not restored → `/splash?from=<path>`;
  signed out → public routes (`/`, `/login`, `/register`) stay, anything else →
  `/login?from=<path>`; signed in → `/`, `/login`, `/register` lead to `from` or
  `/parties`; `/admin` and `/admin/**` need `isAdmin`, else `/parties`. `from` is only
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

The server side is fixed ([[Architecture]]): `GET /suscribeupdate[?token=]`, one global
stream for every client; an initial `event: connected`, then every broadcast as `event:
event` + a JSON object, a `: heartbeat` comment every 20 s; Node also sends `retry: 1000`
(`src/api/server.js:69-130`), Rust a `type` on every broadcast (`zapzap-rust/src/api/sse.rs`,
`GameEvent`, `zapzap-rust/src/infrastructure/app_state.rs:189-204`).

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
  `userConnected`/`userDisconnected`/`userStatusChanged`. Every client gets every event: a
  screen keeps those of its `partyId`.
- **`SseProvider`** (`providers/sse_provider.dart`, a `ChangeNotifier`): `connect(token)`,
  `disconnect()`, `follow(token?)`, `events`, `connected` (notifies on change). One for the
  whole signed-in session: in `appProviders` a `ChangeNotifierProxyProvider<AuthProvider,
  SseProvider>`, not lazy, calls `follow(auth.isAuthenticated ? auth.token : null)` on every
  `AuthProvider` change — connected on sign-in or a restored session, closed on logout (a
  401 included), reopened when the token changes (`test/sse_session_test.dart`).
  `ZapZapApp(sseTransport:)` swaps the transport for tests.
- Node emits `userConnected` before subscribing the new stream, so a client never sees its
  own arrival (`src/api/server.js:101-106`, `:131`).
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
  statistics follow the same rule (below). `test/party_screens_test.dart` (`back
  navigation`) and `test/app_bar_test.dart` drive the system Back
  (`handlePopRoute`).
- **Screens own their provider**: each screen builds it in `initState` from the
  repositories it reads off the tree and disposes it, and draws with a `ListenableBuilder`;
  the widgets below take plain data. Only `ConnectedPlayersProvider` is app-wide.
- **`PartyListProvider`** (`providers/party_provider.dart`): `GET /party`, pull-to-refresh
  (`load(showSpinner: false)`), and `join` — which answers `true` on `ALREADY_IN_PARTY`
  too, because React navigates to the lobby on it (`PartyList.jsx:37-39`). The list is
  **not** refreshed by the event stream, as in React. A card shows the seats taken, the
  status and the one action: Join (disabled when full, playing or finished), Return to
  lobby, or Continue game for a party the caller is in (`isMember`). A row without
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
  requires (`src/use-cases/party/CreateParty.js:47-53`): shorter keeps Create disabled with
  its reason, longer cannot be typed — Node would answer a generic 500.
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
- **`ConnectedPlayersProvider`** (`providers/connected_players_provider.dart`), app-wide
  and lazy: `GET /players/connected` on sign-in (kept to five, as the events are), then
  `userConnected` (prepended, five at most), `userDisconnected` and `userStatusChanged`.
  Until the first answer or event (`loaded`), and after a failed one, the app bar shows
  `–` rather than a count: "0" would claim nobody is online. A client never sees the *broadcast*
  of its own arrival — Node emits `userConnected` before subscribing the new stream
  (`src/api/server.js:101-106` after `:99`) — but the session is registered first, so the
  `GET /players/connected` the client makes afterwards may already list it; which of the
  two wins the race decides whether a lone user sees 0 or 1. React behaves the same way. The app bar (`widgets/zapzap_app_bar.dart`) holds it, the connection
  indicator, sign-out and the navigation menu — icons only, so it fits a phone, which the
  React header does not.
- **The app-bar menu** (`widgets/zapzap_app_bar.dart`, key `app-bar-menu`) leads to the
  history (`menu-history`) and the statistics (`menu-stats`), with `context.push` so the
  Android system Back button returns to the screen below. A menu rather than one icon
  each: there is no URL bar on Android, and more icons would not fit a 360 px bar at a
  large system font. Admin is left out until an admin screen exists.
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
- **Widgets take plain data**, as the lobby's do: `GamePlayerTable` (a `GameSeat` per row,
  the player to move on a green edge, an eliminated one struck through, at most 5 card
  backs under 640 px and 8 above); `GameTableArea` (the `lastAction` message, the cards
  laid down this turn, the discard pile — tappable only in the draw phase —, and the
  "reshuffled" banner for 2.5 s, timed in the widget's state); `GameHand` (the `CardFan`,
  the count, `ZapZap n · Penalty n`, the eligibility badge and the deck button);
  `GameActionButtons` (the turn banner, the refusal, and Play / Draw-or-Take / ZapZap).
- **Back leads to `/parties`, not to the lobby**: `PartyLobbyProvider.load` sends a party
  that is `playing` straight back to `/game/:id`, so a back button pointing at the lobby is
  a flash and a full remount of the board, and no way out of the game.
- **Layouts**: under 800 px one column that fills the height — each section is `Flexible`
  over its own scroll view, so a large system font shrinks a section instead of
  overflowing the column —, above it the players beside the felt. `test/game_screen_test.dart`
  pumps every mode at 360x740 at text scales 1.0 **and** 1.5 — not my turn with a two-line
  waiting banner, the tallest action bar (two-line banner over the invalid-play reason)
  and a Golden Score hand of 10 included — and the wide layout at both scales too; the
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

### The end of a round and of the game (`widgets/game_round_end.dart`)

The port of `frontend/src/components/Game/RoundEnd.jsx`, fed by `GameBoard.jsx:374-400`.
`GameScreen._roundOver` builds it from `GameState` alone — never from the answer of
`zapzap`, whose `scores` are the running totals on Node and the round's own points on Rust
(API layer, above). It is the `finished` mode of the board, not a route: the phase is
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
  at text scales 1.0 and 1.5.
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
- **Statistics** (`screens/stats_screen.dart`): `StatsPersonal` (`GET /stats/me`),
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
  `(v*100).toStringAsFixed(1)`, as React; `—` for a missing value.
- Shared presentation lives in `widgets/stats_common.dart`: `SectionCard`, `StatTile`,
  `StatTileGrid` (2 columns under 640 px, 4 above), `RankBadge`, `GoldenScoreChip`,
  `MiniStat` and `StatsColors` — the green/red/purple/cyan accents of the React screens,
  kept out of `utils/app_theme.dart` because they belong to these screens only.
- **Every text beside another in a `Row` is `Flexible`**: a name, a figure or a label that
  is unconstrained overflows on a 360 px phone as soon as the system font is large — the
  standings' ZapZap record, the tiles' facts, the legend items, the leaderboard's win-rate
  column and the personal ZapZap header. In `SectionCard` the trailing badge is `Flexible`
  too, and `GoldenScoreChip` ellipsizes: with `Expanded` on the title alone the badge takes
  what it asks for, squeezes the title into a column of single letters and is clipped
  anyway. `test/history_screens_test.dart` and `test/stats_screen_test.dart` each end on a
  `phone width` group at 360×740, at text scale 1 and 1.5, scrolling to every card so it
  really lays out; an overflow is a layout error, which fails the test.

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
(the React client uses lucide).

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
- `isZapZapEligible`: hand ≤ 5 with jokers 0. Final scoring and the counteract penalty are
  not ported (the backend computes them).
- Widgets: `PlayingCard` (height = width × 1.4, radius 5 % of width ≥ 2, amber glow when
  selected, opacity 0.5 and no tap when disabled, a localised semantics label);
  `CardBack` (sizes `xxs` 16 … `lg` 80 px, as `CardBack.jsx`; a painted red lattice, no
  asset); `CardFan` (the arc of `CardFan.jsx`: under 640 px 50 px cards, ≤ 50°, 8°/card,
  100 px high, lift 15; else 70 px, ≤ 75°, 12°/card, 150 px, lift 25; selected cards on top;
  `CardFan.itemKey(i)`).
- Faces: `frontend-flutter/assets/cards/<rank>_of_<suit>.svg` — the CC0 "English pattern"
  deck by Dmitry Fomin (Wikimedia Commons) — and `joker_red.svg` / `joker_black.svg`
  copied from `frontend/public/`; rendered with `flutter_svg`. Licence:
  `frontend-flutter/THIRD_PARTY.md`. The 54 files weigh 1.26 MB after `svgo` (2.3 MB as
  published); the twelve court cards are 1.15 MB of it.

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
- `test/l10n_test.dart` fails when a key is in one ARB file and not the other.

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
| `flutter analyze` | lints, must be clean |
| `flutter test` | `test/api_config_test.dart`, `test/app_test.dart` (routing, fr/en, theme), `test/l10n_test.dart`, `test/android_config_test.dart`, `test/api_client_test.dart` (Bearer, 401 → `onUnauthorized`, network, timeout), `test/api_exception_test.dart` (every error shape), `test/models_test.dart` (every model from the fixtures, plus the Rust shapes), `test/repositories_test.dart` (each route's method, path, body), `test/auth_utils_test.dart` (validators, JWT), `test/auth_provider_test.dart` (restore, login, logout, parallel 401s, the web storage), `test/auth_screens_test.dart` (login/register widgets, the guard: expired JWT, admin, `from`); `test/auth_helpers.dart` builds unsigned test JWTs, `test/sse_parser_test.dart` (line format, split chunks), `test/sse_event_test.dart`, `test/sse_client_test.dart` (fake transport `test/sse_fakes.dart` + fake_async: token, 3 s reconnect, disconnect, token change; `SseProvider`), `test/sse_transport_io_test.dart` (`MockClient.streaming`: headers, chunks, non-200, idle timeout), `test/connection_indicator_test.dart`, `test/sse_session_test.dart` (the channel follows sign-in, logout, a new token), `test/party_provider_test.dart` (seat assignment — never the same bot twice, "none available", freeing a seat —, the create body, join on `ALREADY_IN_PARTY`, the lobby's events and its owner/only-human rules, two lobby loads answering out of order, presence and its five-player cap on the first load), `test/party_screens_test.dart` (the three screens end to end over `test/party_helpers.dart`'s fake backend: cards and their buttons, seat selectors, start disabled below 3, a player joining through the stream, start/leave/delete, a failed first load, a row without `maxPlayers`, a name under 3 characters, `NOT_IN_PARTY`, no presence count before the first answer, the system Back from the form, the lobby and the game (`back navigation`), and that each screen fits 360×740, and 360×740 again at a 1.5 text scale), `test/card_test.dart` + `test/rules_test.dart` (the React utils tests, ported), `test/card_widgets_test.dart` (every face of the 54 ids parses and renders; card, back, fan), `test/game_provider_test.dart` (the derived table, the selection and its reset, each move's body, a refused move that keeps the table, a failed refresh that keeps it too, two loads answering out of order, a discard card gone from the pile that is not posted, the hand-size range, the events — `partyStarted` included), `test/game_screen_test.dart` (the board end to end over `test/game_helpers.dart`'s fake backend: each mode, my turn and not my turn, an invalid play that keeps the board, a backend refusal in a snack bar, a ZapZap that held, a counteracted one with its penalty, a finished game with its winner, a refresh that fails leaving the table under its banner, Clear dropping the discard card, a Golden Score that ends pulling the hand size back into range, Back leading to the parties, a waiting client entering the board on `partyStarted` or by Retry, and every mode at 360×740 at text scales 1.0 and 1.5, the wide layout at both scales), `test/date_format_test.dart`, `test/history_screens_test.dart` (the two tabs, empty, failed and retried, opening the details; summary, standings, the round table and its legend, a counteracted caller in red even on the lowest hand, the system Back from the details, the signed-in app bar, an unknown game), `test/stats_screen_test.dart` (personal figures, my highlighted row and a row that is not mine, the bot filter and its fallback to All, one failing section among three), `test/app_bar_test.dart` (the app-bar menu opens the history and the statistics, the system Back returns to the list, history then statistics unwound one Back at a time, no Admin entry for either kind of session), and a `phone width` group in each at 360×740, text scale 1 and 1.5; `test/history_helpers.dart` builds a session for a given user id and an `ApiClient` routing each path to a fixture |
| `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:9999` | the web client against a local backend |
| `flutter build web --base-href /app/` | the PWA → `build/web/`, to be served under `/app/` |
| `flutter run -d <device> --dart-define=API_BASE_URL=http://10.0.2.2:9999` | the Android debug app on an emulator, against a backend on the host |
| `flutter build apk --debug` | `build/app/outputs/flutter-apk/app-debug.apk`; needs the Android SDK (`~/sdk/android`). Add `--dart-define=API_BASE_URL=http://<LAN IP>:9999` for a device on the LAN; without it the APK talks to production over HTTPS |
| `docker build -t zapzap-frontend-flutter:ci .` then `scripts/pwa_image_smoke.sh` (from the repository root) | the PWA image and its smoke test |

Build outputs (`frontend-flutter/build/`, `.dart_tool/`) are ignored by the root and the
project `.gitignore`.

## Decisions & History

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
- **App-bar menu rather than icons, and no Admin entry (2026-09-23,
  `feat/flutter-app-bar-links`).** The history and statistics routes exist since #33, so
  the app bar leads to them; a `PopupMenuButton` rather than two more `IconButton`s
  because the bar already carries the presence count, the connection indicator and
  sign-out, and 360 px at a 1.5 text scale leaves no room. `context.push`, not `go`: the
  screen stays on top of the parties list, so the Android system Back button returns to
  it. `/admin` still has only the router guard of #29, so an Admin entry would land on the
  not-found screen — it waits for the admin screen
  (`wip/todo_nr/2026-09-22-flutter-admin.md`), and a test keeps the menu free of it.
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
- **Android: `com.zapzap.app`, cleartext in debug only (2026-09-22).** The scaffold's
  generated `com.zapzap.zapzap` was replaced before any install existed. Plain HTTP is needed
  to reach a local backend from the emulator or the LAN, but a release build must never
  downgrade to it, so the network security config lives in `src/debug/` rather than in the
  main manifest.
