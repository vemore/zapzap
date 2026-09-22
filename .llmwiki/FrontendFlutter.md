# FrontendFlutter

> Scope: the Flutter client in `frontend-flutter/` — Android app and PWA — its layout, API
> configuration and API layer (client, errors, models, repositories), authentication and
> routing guard, real-time channel (SSE), the parties, create-party and lobby screens,
> theme, localisation, build and tests.
> Related: [[Architecture]] · [[Frontend]] · [[Api]] · [[Deployment]] · [[Testing]]
> Updated: 2026-09-22

## Facts

### Status

- **Up to the lobby.** Home, login, register, the parties list, create-party, one party's
  lobby, a start-up splash and a not-found screen (`frontend-flutter/lib/router.dart`),
  over the API layer, the session and the real-time channel (below). `/game/:id` is a
  placeholder screen (`screens/pending_game_screen.dart`) the lobby sends a started party
  to; the game board replaces it. Still missing against the React client ([[Frontend]]):
  the game board, history, stats, Google sign-in, admin — and the app bar has no entry
  point to history, stats or admin until those screens exist.
- The card model, play rules and card widgets exist (below) but no screen uses them yet.
- Not deployed: no compose service, no nginx route for `/app/` yet ([[Deployment]]).
- CI: the `flutter` job (`.github/workflows/ci.yml`, Flutter pinned to 3.47.2 with
  `subosito/flutter-action`, JDK 17) runs `pub get --enforce-lockfile` (a stale
  `pubspec.lock` fails the job), `gen-l10n`, `analyze`, `test`,
  `build web --base-href /app/` and `build apk --debug`. `scripts/ci_scope.sh` selects it,
  and only it, for a path under `frontend-flutter/` (a `.md` there selects nothing)
  ([[Testing]]). It is not yet a required check of the branch protection ([[ParallelDelivery]]).
- Commit gate: `flutter pub get --offline`, `flutter gen-l10n`, `flutter analyze` when the
  commit touches `frontend-flutter/`; no `.dart_tool` → a refusal naming `flutter pub get`
  ([[Hooks]]). `scripts/worktree_setup.sh` runs the pub get and gen-l10n (`--no-flutter`
  skips them).

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
| `screens/` | `home_screen.dart`, `splash_screen.dart`, `login_screen.dart`, `register_screen.dart`, `parties_screen.dart`, `create_party_screen.dart`, `party_lobby_screen.dart`, `pending_game_screen.dart` (stands in for the board at `/game/:id`), `not_found_screen.dart` |
| `models/card.dart` | `GameCard` (not `Card`: Material has one) — id, suit, rank, value, face asset (below) |
| `utils/rules.dart` | `analyzePlay` / `isValidPlay` / `playType`, `handValue`, `isZapZapEligible`, `handValueDisplay`, `sortCards` (below) |
| `utils/card_l10n.dart` | `CardL10n` on `AppLocalizations`: suit and card names, `playErrorMessage(PlayError)` |
| `widgets/` | `playing_card.dart`, `card_back.dart`, `card_fan.dart` (below); `app_logo.dart`; `auth_form.dart` (the card, submit button and switch link shared by login and register, and the error-code → text mapping); `connection_indicator.dart` (Wifi icon of `SseProvider.connected`); `zapzap_app_bar.dart`, `connected_players.dart`, `party_card.dart`, `player_slot_selector.dart`, `player_seat_tile.dart`, `error_banner.dart` (and `partyErrorText`) |
| `providers/party_provider.dart`, `create_party_provider.dart`, `connected_players_provider.dart` | the lobby state (below) |
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
  (`frontend/src/components/Auth/ProtectedRoute.jsx:5`). On the web the route sits in the
  URL fragment (`/#/parties`, Flutter's default URL strategy).

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
- **Screens own their provider**: each screen builds it in `initState` from the
  repositories it reads off the tree and disposes it, and draws with a `ListenableBuilder`;
  the widgets below take plain data. Only `ConnectedPlayersProvider` is app-wide.
- **`PartyListProvider`** (`providers/party_provider.dart`): `GET /party`, pull-to-refresh
  (`load(showSpinner: false)`), and `join` — which answers `true` on `ALREADY_IN_PARTY`
  too, because React navigates to the lobby on it (`PartyList.jsx:37-39`). The list is
  **not** refreshed by the event stream, as in React. A card shows the seats taken, the
  status and the one action: Join (disabled when full, playing or finished), Return to
  lobby, or Continue game for a party the caller is in (`isMember`). The cards are laid out
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
- **`PartyLobbyProvider`** (`providers/party_provider.dart`): `GET /party/:id`, then the
  event stream filtered on `partyId` — `playerJoined`/`playerLeft` reload the seats without
  a spinner, `partyStarted` and `partyDeleted` set `outcome` (`LobbyOutcome.started` /
  `.closed`) and the screen navigates to `/game/:id` or `/parties`. A party already
  `playing` when it loads sets `started` too, so returning to it goes straight to the game.
  `isOwner` falls back to comparing `party.ownerId` with the session's user, because Node's
  answer carries neither `isOwner` nor `userPlayerIndex`; `canStart` needs the owner and 3
  players; `canDelete` is the owner **or** the only human at the table
  (`PartyLobby.jsx:140-144`). Delete asks first, in an `AlertDialog`.
  The hand size is only shown when the party carries one (Rust): on Node the starting
  player picks it each round (`GAME_RULES.md`), so React's "Hand Size: 7" is wrong there.
- **`ConnectedPlayersProvider`** (`providers/connected_players_provider.dart`), app-wide
  and lazy: `GET /players/connected` on sign-in, then `userConnected` (prepended, five at
  most), `userDisconnected` and `userStatusChanged`. A client never sees the *broadcast*
  of its own arrival — Node emits `userConnected` before subscribing the new stream
  (`src/api/server.js:101-106` after `:99`) — but the session is registered first, so the
  `GET /players/connected` the client makes afterwards may already list it; which of the
  two wins the race decides whether a lone user sees 0 or 1. React behaves the same way. The app bar (`widgets/zapzap_app_bar.dart`) holds it, the connection
  indicator and sign-out — icons only, so it fits a phone, which the React header does not.
- **Error text** comes from `partyErrorText` (`widgets/error_banner.dart`), mapping
  `ApiException.code` (`PARTY_NOT_FOUND`, `PARTY_FULL`, `PARTY_STARTED`,
  `PARTY_ALREADY_PLAYING`, `NOT_OWNER`, `NOT_AUTHORIZED`, no answer) to ARB strings;
  `PartyErrorCode` (`providers/party_provider.dart`) names the party codes.

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
  the `mipmap-*`, `drawable-*` and `values/colors.xml` resources. The web icons
  (`web/icons/`) are still Flutter's defaults.
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

### Build and test (from `frontend-flutter/`)

| Command | What |
|---|---|
| `flutter analyze` | lints, must be clean |
| `flutter test` | `test/api_config_test.dart`, `test/app_test.dart` (routing, fr/en, theme), `test/l10n_test.dart`, `test/android_config_test.dart`, `test/api_client_test.dart` (Bearer, 401 → `onUnauthorized`, network, timeout), `test/api_exception_test.dart` (every error shape), `test/models_test.dart` (every model from the fixtures, plus the Rust shapes), `test/repositories_test.dart` (each route's method, path, body), `test/auth_utils_test.dart` (validators, JWT), `test/auth_provider_test.dart` (restore, login, logout, parallel 401s, the web storage), `test/auth_screens_test.dart` (login/register widgets, the guard: expired JWT, admin, `from`); `test/auth_helpers.dart` builds unsigned test JWTs, `test/sse_parser_test.dart` (line format, split chunks), `test/sse_event_test.dart`, `test/sse_client_test.dart` (fake transport `test/sse_fakes.dart` + fake_async: token, 3 s reconnect, disconnect, token change; `SseProvider`), `test/sse_transport_io_test.dart` (`MockClient.streaming`: headers, chunks, non-200, idle timeout), `test/connection_indicator_test.dart`, `test/sse_session_test.dart` (the channel follows sign-in, logout, a new token), `test/party_provider_test.dart` (seat assignment — never the same bot twice, "none available", freeing a seat —, the create body, join on `ALREADY_IN_PARTY`, the lobby's events and its owner/only-human rules, presence), `test/party_screens_test.dart` (the three screens end to end over `test/party_helpers.dart`'s fake backend: cards and their buttons, seat selectors, start disabled below 3, a player joining through the stream, start/leave/delete, and that each screen fits 360×740, and 360×740 again at a 1.5 text scale), `test/card_test.dart` + `test/rules_test.dart` (the React utils tests, ported), `test/card_widgets_test.dart` (every face of the 54 ids parses and renders; card, back, fan) |
| `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:9999` | the web client against a local backend |
| `flutter build web --base-href /app/` | the PWA → `build/web/`, to be served under `/app/` |
| `flutter run -d <device> --dart-define=API_BASE_URL=http://10.0.2.2:9999` | the Android debug app on an emulator, against a backend on the host |
| `flutter build apk --debug` | `build/app/outputs/flutter-apk/app-debug.apk`; needs the Android SDK (`~/sdk/android`). Add `--dart-define=API_BASE_URL=http://<LAN IP>:9999` for a device on the LAN; without it the APK talks to production over HTTPS |

Build outputs (`frontend-flutter/build/`, `.dart_tool/`) are ignored by the root and the
project `.gitignore`.

## Decisions & History

- **Flutter client decided (2026-09-22).** The user wants an Android app and a PWA at parity
  with the React client. The PWA goes on the same domain under `/app/` (same origin as the
  API, no CORS change to the backend) while React stays on `/`; Android is debug-only for
  now. French and English from day one.
- **CI job and commit gate (2026-09-22, `chore/flutter-ci-gates`).** The commit gate is the
  analyzer only (seconds); the tests and the two builds are CI's. No image flag: the client
  is not deployed yet.
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
- **Android: `com.zapzap.app`, cleartext in debug only (2026-09-22).** The scaffold's
  generated `com.zapzap.zapzap` was replaced before any install existed. Plain HTTP is needed
  to reach a local backend from the emulator or the LAN, but a release build must never
  downgrade to it, so the network security config lives in `src/debug/` rather than in the
  main manifest.
