# FrontendFlutter

> Scope: the Flutter client in `frontend-flutter/` — Android app and PWA — its layout, API
> configuration and API layer (client, errors, models, repositories), theme, localisation,
> build and tests.
> Related: [[Architecture]] · [[Frontend]] · [[Api]] · [[Deployment]] · [[Testing]]
> Updated: 2026-09-22

## Facts

### Status

- **Scaffold.** A home screen that routes to a placeholder login screen, and a not-found
  screen (`frontend-flutter/lib/router.dart`). The API layer (client, errors, models,
  repositories, below) is in place; no screen uses it yet. Parity with the React client ([[Frontend]]:
  game, lobby, history, stats, Google sign-in, admin) is the goal, not the state.
- Not deployed: no compose service, no nginx route for `/app/` yet ([[Deployment]]).
- No CI job yet: `scripts/ci_scope.sh` has no `frontend-flutter/*` case, so a path there
  falls to the catch-all and runs **every** job; none of them runs Flutter. Verification is
  local (below).

### Stack

- Flutter 3.47.2 / Dart 3.13.2, SDK at `~/sdk/flutter` (not pinned in the repository);
  `environment.sdk: ^3.13.2` (`frontend-flutter/pubspec.yaml`).
- Platforms: `android` and `web` only (`flutter create --platforms=android,web --org
  com.zapzap`); application id `com.zapzap.zapzap`, label `ZapZap`
  (`frontend-flutter/android/app/src/main/AndroidManifest.xml`).
- Dependencies (`frontend-flutter/pubspec.yaml`): provider, http, go_router,
  shared_preferences, flutter_secure_storage, intl, flutter_localizations, flutter_svg;
  lints `flutter_lints` + `prefer_single_quotes` (`frontend-flutter/analysis_options.yaml`).
- Conventions follow `~/workspace/countscore`: Provider for state, `http` for the API, ARB +
  gen-l10n.

### Layout (`frontend-flutter/lib/`)

| Path | Role |
|---|---|
| `main.dart` | `runApp(ZapZapApp(apiConfig: ApiConfig.fromEnvironment()))`, nothing else |
| `app.dart` | `ZapZapApp`: `MultiProvider` + `MaterialApp.router` (theme, locales, router); `resolveLocale` |
| `router.dart` | `AppRoutes` (path constants) and `createRouter()` — the one `GoRouter`; a new screen is one more `GoRoute` |
| `providers/app_providers.dart` | `appProviders()` — the one list handed to `MultiProvider`; a new provider is one more entry. Holds `ApiConfig`, `ApiClient` and the six repositories |
| `services/api_config.dart` | `ApiConfig` (below) |
| `services/api_client.dart`, `services/api_exception.dart` | `ApiClient`, `ApiException`, `ApiErrorCode` (API layer, below) |
| `utils/app_theme.dart` | `AppColors`, `AppTheme.dark()` |
| `screens/` | `home_screen.dart`, `login_screen.dart` (placeholder), `not_found_screen.dart` |
| `widgets/` | `app_logo.dart` |
| `models/` | typed API models with `fromJson` (API layer, below); `json.dart` holds the lenient readers and `Page<T>` |
| `repositories/` | one per domain over `ApiClient`: auth, party, game, history, stats, admin |
| `l10n/` | `app_fr.arb` (template), `app_en.arb` |

### API configuration (`frontend-flutter/lib/services/api_config.dart`)

- `baseUrl` is, in order: `--dart-define=API_BASE_URL=<url>`; on the web, the page's
  origin (`Uri.base.origin`) — the PWA is served under `/app/` on the API's own domain, so
  there is no CORS (the Node backend only accepts `ALLOWED_ORIGINS`, `src/api/server.js:32-57`);
  elsewhere (Android), `https://zapzap.ombivince.synology.me`. Trailing slashes are stripped.
- `apiUri('/x')` → `<base>/api/x`; `sseUri` → `<base>/suscribeupdate` (the backend's spelling,
  [[Architecture]]).
- Android talking to a local backend from the emulator:
  `--dart-define=API_BASE_URL=http://10.0.2.2:9999`. The manifest sets no
  `usesCleartextTraffic`, so plain HTTP may be refused on recent Android; untested.
- `ApiConfig` is provided to the tree as `Provider<ApiConfig>` (`providers/app_providers.dart`).

### API layer (`frontend-flutter/lib/services/`, `models/`, `repositories/`)

- **`ApiClient`** (`services/api_client.dart`), the counterpart of the React `api.js`:
  `get`/`post`/`delete` to `ApiConfig.apiUri(path)`, JSON in and out, a `JsonMap` back,
  `ApiClient.defaultTimeout` 10 s. `token` (settable) is sent as `Authorization: Bearer`
  unless the call passes `authenticated: false` (login, register, Google, and the public
  reads: bots, connected players, public history, public stats).
- **401 → `onUnauthorized`** (settable callback): fires on a 401 to an *authenticated* call,
  before the `ApiException` is thrown. Unauthenticated calls never fire it, so a wrong
  password (401 `INVALID_CREDENTIALS`) logs nobody out. The auth pull request wires it to
  clearing the session and routing to login (the React client only clears, `api.js:34-38`).
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
  create, details, join, leave, start, delete, bots, connectedPlayers), `GameRepository`
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
  `zapzap` adds a `handPoints` map, Rust sends one number; `counteractedBy` is an index on
  Node, a string on Rust; Node play/draw answers carry a raw `gameState` with every hand and
  the deck, deliberately not parsed.
- **Fixtures** (`test/fixtures/*.json`): answers captured from the local Node backend
  (`PORT=9911 node app.js` on a worktree database after `npm run init-demo && npm run
  init-bots`, one game against EasyBot1 and MediumBot1 played through the API to its end),
  tokens replaced by placeholders. `error_*.json` are `{status, body}`. `test/fixtures.dart`
  loads them.

### Theme (`frontend-flutter/lib/utils/app_theme.dart`)

Dark only, from `frontend/tailwind.config.js`: slate `#0f172a` (background), `#1e293b`
(surfaces), `#334155`, `#475569` (outline); amber `#fbbf24` (primary), `#f59e0b`, `#d97706`;
the table felt is Tailwind green-900 `#14532d` / green-800 `#166534`. Icons are Material
(the React client uses lucide).

### Localisation

- `frontend-flutter/l10n.yaml`: `arb-dir: lib/l10n`, template `app_fr.arb`,
  `nullable-getter: false`. French is the default: `resolveLocale` (`app.dart`) picks the
  device's language when it is `fr` or `en`, else `fr`.
- **No user-facing string literal outside `lib/l10n/`**: every text goes through
  `AppLocalizations.of(context)`. The React client mixes French and English; the port
  unifies them in the ARB files.
- The generated `lib/l10n/app_localizations*.dart` are **not committed**
  (`frontend-flutter/.gitignore`): `flutter pub get` (and so `analyze`, `test`, `build`)
  regenerates them. Keeps parallel pull requests that each add strings free of conflicts in
  generated code.
- `test/l10n_test.dart` fails when a key is in one ARB file and not the other.

### Build and test (from `frontend-flutter/`)

| Command | What |
|---|---|
| `flutter analyze` | lints, must be clean |
| `flutter test` | `test/api_config_test.dart`, `test/app_test.dart` (routing, fr/en, theme), `test/l10n_test.dart`, `test/api_client_test.dart` (Bearer, 401 → `onUnauthorized`, network, timeout), `test/api_exception_test.dart` (every error shape), `test/models_test.dart` (every model from the fixtures, plus the Rust shapes), `test/repositories_test.dart` (each route's method, path, body) |
| `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:9999` | the web client against a local backend |
| `flutter build web --base-href /app/` | the PWA → `build/web/`, to be served under `/app/` |
| `flutter build apk --debug` | `build/app/outputs/flutter-apk/app-debug.apk`; needs the Android SDK (`~/sdk/android`) |

Build outputs (`frontend-flutter/build/`, `.dart_tool/`) are ignored by the root and the
project `.gitignore`.

## Decisions & History

- **Flutter client decided (2026-09-22).** The user wants an Android app and a PWA at parity
  with the React client. The PWA goes on the same domain under `/app/` (same origin as the
  API, no CORS change to the backend) while React stays on `/`; Android is debug-only for
  now. French and English from day one.
- **API layer (2026-09-22, `feat/flutter-api-client`).** Models parse both backends
  leniently rather than one strictly: production runs Node, the target is Rust, and their
  shapes differ in types more than in names. The 401 hook is a plain callback on
  `ApiClient`, not a dependency on the auth provider, so the client has no knowledge of
  routing and the auth pull request only has to set it. Error text stays out of the UI:
  screens map `ApiException.code` to ARB strings.
- **Generated l10n not committed (2026-09-22)**, unlike countscore: several Flutter pull
  requests will add strings in parallel, and generated files would conflict on every one.
