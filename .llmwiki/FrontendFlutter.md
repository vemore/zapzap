# FrontendFlutter

> Scope: the Flutter client in `frontend-flutter/` — Android app and PWA — its status, stack,
> layout, API configuration and API layer (client, errors, models, repositories), theme,
> build and tests; the hub of the Flutter pages, one per sub-topic (below).
> Related: [[FlutterAuth]] · [[FlutterRealtime]] · [[FlutterParties]] · [[FlutterGameBoard]] ·
> [[FlutterGameUi]] · [[FlutterHistoryAdmin]] · [[FlutterI18n]] · [[FlutterAndroidPwa]] ·
> [[Architecture]] · [[Frontend]] · [[Api]] · [[Deployment]] · [[Testing]]
> Updated: 2026-09-27

## Facts

### Status

- **Playable.** Home, login, register, the parties list, create-party, one party's lobby,
  the game board (`/game/:id`), the history (`/history`), one finished game
  (`/history/:partyId`), the statistics (`/stats`), the admin screen (`/admin`, admins only),
  a start-up splash and a not-found screen
  (`frontend-flutter/lib/router.dart`), over the API layer, the session and the real-time
  channel (below), up to the end of the round and the end of the game (below). Nothing of
  the React client ([[Frontend]]) is missing any more: Google sign-in is below, after
  Authentication.
- **History and statistics are reached from the app-bar menu** of every signed-in screen
  (`ZapZapAppBar`, below) — the history, the game details and the statistics carry that
  bar too, with a back button; the deep links (`/app/history`, `/app/stats`) still work. An
  admin session also gets an **Admin** entry, leading to `/admin` (Admin, below). The same
  menu opens **the rules** in a bottom sheet and holds **Sign out**, confirmed (below).
- **An example game teaches the game offline** (`/tutorial`, "The example game" below):
  offered once on the app's first opening, signed out, then reached from the ⋮ menu and the
  login screen.
- The card model, play rules and card widgets (below) are what the board draws hands with.
- **The PWA is deployable**: its own image (`frontend-flutter/Dockerfile` +
  `frontend-flutter/nginx.conf`), the `frontend-flutter` service in both compose files, and
  the `/app/` route of the production proxy. See "The PWA image" below and [[Deployment]].
- CI: the `flutter` job (`.github/workflows/ci.yml`, Flutter pinned to 3.47.2 with
  `subosito/flutter-action`, JDK 17) runs `pub get --enforce-lockfile` (a stale
  `pubspec.lock` fails the job), `gen-l10n`, `dart format --output=none
  --set-exit-if-changed lib test` (an unformatted file fails the job), `analyze`, `test`,
  `build web --base-href /app/ --no-web-resources-cdn` (the image's flags),
  `build apk --debug` (uploaded, below), `build apk --release` (R8, and the debug-key
  fallback: CI has no `key.properties` — [[FlutterAndroidPwa]]) and `build appbundle --release`,
  which must fail there, naming `key.properties`. `scripts/ci_scope.sh` selects it
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
  web (the `EventSource` of the SSE web transport), google_sign_in + google_sign_in_web
  (Google sign-in, below); dev: fake_async (timer tests); lints `flutter_lints` + `prefer_single_quotes` (`frontend-flutter/analysis_options.yaml`).
- Conventions follow `~/workspace/countscore`: Provider for state, `http` for the API, ARB +
  gen-l10n.

### Layout (`frontend-flutter/lib/`)

| Path | Role |
|---|---|
| `main.dart` | `runApp(ZapZapApp(apiConfig: ApiConfig.fromEnvironment(), tutorialOffer: PreferencesTutorialOfferStore()))`, nothing else |
| `app.dart` | `ZapZapApp`: `MultiProvider` + `MaterialApp.router` (theme, locales, router); `resolveLocale` |
| `router.dart` | `AppRoutes` (path constants), `createRouter(auth:)` — the one `GoRouter`, built once below the providers; a new screen is one more `GoRoute` — and `authRedirect` (Authentication, below) |
| `providers/app_providers.dart` | `appProviders()` — the one list handed to `MultiProvider`; a new provider is one more entry. Holds `ApiConfig`, `ApiClient`, the six repositories, `AuthProvider`, `SseProvider` (which follows it) and `ConnectedPlayersProvider` (which follows both) |
| `providers/auth_provider.dart` | `AuthProvider`, the session (Authentication, below) |
| `providers/sse_provider.dart`, `services/sse_*.dart`, `models/sse_event.dart` | the real-time channel (below) |
| `services/token_storage*.dart` | `TokenStorage` and its platform implementations (Authentication, below) |
| `services/api_config.dart` | `ApiConfig` (below) |
| `services/google_sign_in_service.dart`, `services/google_sign_in_button_*.dart`, `services/google_sign_in_script_*.dart` | `GoogleSignInConfig`, `GoogleSignInService` and its plugin implementation, Google's web button, the release of Google's held-back script (Google sign-in, below) |
| `services/api_client.dart`, `services/api_exception.dart` | `ApiClient`, `ApiException`, `ApiErrorCode` (API layer, below) |
| `utils/app_theme.dart` | `AppColors`, `AppTheme.dark()` |
| `utils/validators.dart`, `utils/jwt.dart`, `utils/field_touch.dart` | the React username/password rules; the JWT payload and `exp` reader; `FieldTouch`, when a form field may show its refusal |
| `utils/navigation.dart` | `popOrGo(fallback)`: the back button of a pushed screen, replacing the browser's entry; `replaceWith(location)`: a screen taking another's place (Back navigation, below) |
| `utils/motion.dart` | `Motion`: the board's animation durations and `Motion.of(context, d)`, zero under `MediaQuery.disableAnimations` (J9, "The turn reads itself", below) |
| `utils/date_format.dart` | `Formats`: date and time in the app's locale, percentages, one-decimal numbers (History and statistics, below) |
| `screens/` | `home_screen.dart`, `splash_screen.dart`, `login_screen.dart`, `register_screen.dart`, `parties_screen.dart`, `create_party_screen.dart`, `party_lobby_screen.dart`, `game_screen.dart` (the board), `history_screen.dart`, `game_details_screen.dart`, `stats_screen.dart`, `admin_screen.dart`, `not_found_screen.dart`, `tutorial_screen.dart` (the example game, below) |
| `models/card.dart` | `GameCard` (not `Card`: Material has one) — id, suit, rank, value, face asset (below) |
| `utils/rules.dart` | `analyzePlay` / `isValidPlay` / `playType`, `handValue`, `isZapZapEligible`, `handValueDisplay`, `zapZapProgress`, `hasJoker`, `counteractPenalty`, `sortCards`, `suggestPlays` / `PlaySuggestion` (below) |
| `utils/card_l10n.dart` | `CardL10n` on `AppLocalizations`: suit and card names, `cardShort` ("7♥"), `playMoveLabel`, `playErrorMessage(PlayError)` |
| `widgets/` | `playing_card.dart`, `card_back.dart`, `card_fan.dart` (below); `app_logo.dart`; `auth_form.dart` (the card, submit button and switch link shared by login and register, and the error-code → text mapping); `google_sign_in_section.dart` (Google sign-in, below); `connection_indicator.dart` (Wifi icon of `SseProvider.connected`); `zapzap_app_bar.dart`, `connected_players.dart`, `party_card.dart`, `player_slot_selector.dart`, `player_seat_tile.dart`, `error_banner.dart` (and `partyErrorText`); `game_player_table.dart`, `game_table_area.dart`, `game_hand.dart`, `hand_suggestions.dart`, `game_action_buttons.dart`, `game_zapzap_sheet.dart`, `game_hand_size_selector.dart`, `game_round_end.dart`, `game_error_text.dart` (the game board, below); `async_section.dart`, `history_*.dart`, `stats_*.dart` (History and statistics, below); `admin_common.dart`, `admin_users.dart`, `admin_parties.dart`, `admin_stats.dart` (Admin, below) |
| `providers/party_provider.dart`, `create_party_provider.dart`, `connected_players_provider.dart` | the lobby state (below) |
| `providers/game_provider.dart` | one party's board (below) |
| `providers/tutorial_game.dart`, `services/tutorial_offer_store.dart`, `widgets/tutorial_offer.dart` | the example game's script and state, the first opening's flag and offer (The example game, below) |
| `models/` | `card.dart` (above) and the typed API models with `fromJson` (API layer, below); `json.dart` holds the lenient readers and `Page<T>` |
| `repositories/` | one per domain over `ApiClient`: auth, party, game, history, stats, admin |
| `l10n/` | `app_fr.arb` (template), `app_en.arb`, and eight translated: `app_{es,pt,de,ru,ja,hi,id,ar}.arb` |

### API configuration (`frontend-flutter/lib/services/api_config.dart`)

- `baseUrl` is, in order: `--dart-define=API_BASE_URL=<url>`; on the web, the page's
  origin (`Uri.base.origin`) — the PWA is served under `/app/` on the API's own domain, so
  there is no cross-origin request;
  elsewhere (Android), `https://zapzap.ombivince.synology.me`. Trailing slashes are stripped.
- `apiUri('/x')` → `<base>/api/x`; `sseUri` → `<base>/suscribeupdate` (the backend's spelling,
  [[Architecture]]).
- Android talking to a local backend: `--dart-define=API_BASE_URL=http://10.0.2.2:9999`
  from the emulator (`10.0.2.2` is the host's loopback), `http://<LAN IP>:9999` from a
  device. Plain HTTP works in the **debug** build only ([[FlutterAndroidPwa]]).
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
  every error shape: `{error, code, details?}` (auth/party/game);
  `{success:false, error}` and `{error}` (admin on Rust, history, stats, bots) — `code` then
  comes from the status (`BAD_REQUEST`, `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`,
  `CONFLICT`, `SERVER_ERROR`, else `HTTP_<n>`); `{error, code, message}` (the 404 of an unknown route); `{message}`; a response with no body.
  No response: status 0, `NETWORK_ERROR` or `TIMEOUT`; a 2xx that is not an object:
  `INVALID_RESPONSE`. `message` is the backend's text for logs — screens pick a localised
  text from `code` (`ApiErrorCode` names the codes they react to).
- **Repositories** (`repositories/*.dart`), stateless, each `XRepository(ApiClient)`:
  `AuthRepository` (login, register, loginWithGoogle, deleteAccount — `DELETE /auth/me`
  with `{password}` or `{credential}`, the only authenticated auth call; `ApiClient.delete`
  takes a JSON `body` for it), `PartyRepository` (list,
  create — `playerCount` required —, details, join,
  leave, start, delete, bots, connectedPlayers), `GameRepository`
  (state, selectHandSize, play, drawFromDeck, drawFromPlayed, zapZap, nextRound),
  `HistoryRepository` (mine = `GET /history`, public, details), `StatsRepository` (mine,
  user, leaderboard, bots), `AdminRepository` (users, deleteUser, setAdmin, parties,
  stopParty, deleteParty, statistics). A move's answer is not the new table: refetch `GameRepository.state`.
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
- **Parsing rules** (`models/json.dart`), lenient on types (written when the client met two backends):
  maps keyed by player index arrive with string keys (`{"0": 28}`) and become `Map<int, …>`;
  Rust's `nextRound` sent them as `[{playerIndex, score}]` (and `eliminatedPlayers`/`winner`
  as bare indexes) until 2026-09-24; it now sends maps too, and the tolerant parsing
  stays for such older responses.
  A network failure of any kind (`ClientException`, and the `dart:io` socket/TLS errors that
  can escape it) is `NETWORK_ERROR`; the 10 s timeout is one deadline over headers and body.
  Timestamps are Unix seconds, or milliseconds when `>= 1e10` (`lastAction.timestamp`,
  `connectedAt`), or numeric/RFC 3339 strings (what Rust sent before 2026-09-24); all
  become UTC `DateTime`. Ids are strings even when the backend sends an integer (party seat
  `id`). Admin party `settings` arrive as a JSON-encoded string, decoded.
- **Shapes** (`zapzap-rust/src/api/routes/*.rs`): party settings are `{playerCount,
  allowSpectators, roundTimeLimit}` since 2026-09-24 — `playerCount` 3-8 is required on
  create (else 400 `VALIDATION_ERROR`). `PartySettings` reads and sends those three keys
  only; `PartyRepository.create` always sends `playerCount`. `GET /party/:id` carries
  `isOwner` and `userPlayerIndex`, which the lobby reads as they are; a `join` answers the
  `playerIndex` taken. The move answers (play, draw, selectHandSize) carry no `gameState`.
- **Shapes the models read**: `zapzap` answers `scores` (the running totals, an object → `totalScores`),
  `handPoints` (a map), `counteractedBy` (an index or `null` →
  `counteractedByPlayerIndex`) and the round's own points under
  `roundScores` (`ZapZapResult.roundScores`; the finished round's
  `/state` carries them too). `nextRound` sends no golden-score flag: `NextRoundResult`
  has none. History entries (`GET /history`, `/history/public`) carry
  `winnerUserId`, `winnerFinalScore`, `totalRounds`, `wasGoldenScore`, all non-null in
  `GameHistoryEntry`; `userPlacement` and `userScore` on `GET /history` only, `visibility` too. Paging is `pagination {limit, offset, hasMore}`
  (history, leaderboard), `pagination {total, limit, offset}` (admin) or top-level `total,
  limit, offset` (`GET /party`), and `Page` reads each. History `handCards` are a list.
  Error bodies (`ApiException`): `{error, code, details?}` (party, game, auth),
  `{success: false, error, code}` (the admin middleware), `{success: false, error}` or
  `{error}` (admin refusals, stats, history: the code comes from the status),
  `{error, code, path, message}` (a path no route serves).
- **Fixtures** (`test/fixtures/*.json`): the backend's answers on a database seeded with the
  demo users and the bots, one game against EasyBot1 and MediumBot1 played through the API
  to its end, tokens replaced by placeholders. `error_*.json` are `{status, body}`.
  `test/fixtures.dart` loads them. First captured from the Node backend; on 2026-09-25
  every route was captured again from a local Rust backend (`seed --demo`, Vincent made
  admin, a script driving the same game) and each fixture's shape — its key paths and value
  types — compared with that capture: the ten that differed (`bots`, `error_create_party`,
  `game_play`, `game_draw`, `game_select_hand_size`, `game_zapzap`, `history_details`,
  `party_details`, `party_join`, `party_list`) were brought to Rust's shape, keeping the
  values the tests assert on. `admin_statistics.json` keeps its `gamesOverTime` rows, which
  Rust's struct has but always sends empty (`wip` `2026-09-25-rust-admin-statistics-daily-empty`).

### Authentication

Moved to [[FlutterAuth]] (session, storage, login and register screens, routing guard).

### Google sign-in

Moved to [[FlutterAuth]] (web and Android).

### Real-time channel (SSE)

Moved to [[FlutterRealtime]].

### Parties, create-party and lobby

Moved to [[FlutterParties]] (with back navigation and the app-bar menu).

### The game board

Moved to [[FlutterGameBoard]].

### The turn reads itself

Moved to [[FlutterGameUi]] (J1–J9, T1–T3, the felt, board motion).

### The end of a round and of the game

Moved to [[FlutterGameBoard]].

### The example game

Moved to [[FlutterGameBoard]] (`/tutorial` and its first-opening offer).

### History and statistics

Moved to [[FlutterHistoryAdmin]].

### Admin

Moved to [[FlutterHistoryAdmin]].

### Android

Moved to [[FlutterAndroidPwa]] (CI APK, release signing, keys, Google sign-in on Android).

### Theme (`frontend-flutter/lib/utils/app_theme.dart`)

Dark only, from `frontend/tailwind.config.js`: slate `#0f172a` (background), `#1e293b`
(surfaces), `#334155`, `#475569` (outline); amber `#fbbf24` (primary), `#f59e0b`, `#d97706`;
the table felt is Tailwind green-900 `#14532d` / green-800 `#166534`. Icons are Material
(the React client uses lucide). The game board's felt has its own tokens: `feltCenter` `#1c7a45` /
`feltEdge` `#0b3b1f` (its radial gradient), `feltFleckLight`/`feltFleckDark` (the texture),
`feltWatermark`, and the rim's `rimLight` `#5b3a22` / `rimDark` `#2b170b` and `rimInlay`
`#8a6a3a`; `table`/`tableLight` stay for the theme's `tertiary`.

### Cards and play rules

Moved to [[FlutterGameUi]] (card model, `analyzePlay`, card widgets, faces).

### Localisation

Moved to [[FlutterI18n]].

### The PWA image

Moved to [[FlutterAndroidPwa]].

### Build and test (from `frontend-flutter/`)

| Command | What |
|---|---|
| `dart format lib test` | the formatter; `--output=none --set-exit-if-changed` is the gate (hook and CI) |
| `flutter analyze` | lints, must be clean |
| `flutter test` | `test/api_config_test.dart`, `test/app_test.dart` (routing, fr/en, theme), `test/l10n_test.dart`, `test/l10n_locales_test.dart` (the eight translated languages: § Localisation), `test/android_config_test.dart`, `test/api_client_test.dart` (Bearer, 401 → `onUnauthorized`, network, timeout), `test/api_exception_test.dart` (every error shape), `test/models_test.dart` (every model from the fixtures, plus the cases a fixture does not show; the three party settings keys), `test/repositories_test.dart` (each route's method, path, body; create sends no `handSize`/`maxScore`), `test/auth_utils_test.dart` (validators, JWT), `test/auth_provider_test.dart` (restore, login, logout — Google signed out, a failing or silent Google sign-out not holding it —, parallel 401s, the web storage), `test/google_sign_in_test.dart` (`GoogleSignInConfig`: none without the define, `clientId` on the web, `serverClientId` = the web id on Android; the login screen with no button by default, the button above the fields, a token posted as `credential` to `/api/auth/google` landing on the parties, a backend refusal and a Google failure staying on login with the banner, a closed dialog silent, a failure `signIn` throws, a token dropped while a password login is in flight, the web button built once across keystrokes, no network, English, register, signing out (⋮ menu, confirmed) signing out of Google, Google never ready — after 8 s no placeholder and no "ou" on login and register, the next screen without the section, the section back when Google is ready late, a failed initialisation hiding it with no banner —, 360×740 at 1.0/1.5/2.0; the fake is `test/google_fakes.dart`), `test/google_sign_in_plugin_test.dart` (`PluginGoogleSignInService` over a fake `GoogleSignInPlatform`: `serverClientId`, a token, a closed dialog, a Google failure once on the stream, a platform or initialisation failure thrown by `signIn`, `ready`, a failed initialisation failing `ready` and silent on `idTokens`, `signOut` once initialised and not before), `test/pwa_build_config_test.dart` (the image's `GOOGLE_CLIENT_ID` argument; `index.html` holding the GIS script back under the name the app releases it by), `test/auth_screens_test.dart` (login/register widgets — C1–C4: the pitch, validate on submit with an active button, the eye, Next/Done and the `AutofillGroup`, the spinner and the banner above the button, at 360×740 at text scales 1.0 and 1.5 —, the guard: expired JWT, admin, `from`), `test/create_party_form_test.dart` (the name's refusal: none on opening, on Create, on leaving the field); `test/auth_helpers.dart` builds unsigned test JWTs, `test/sse_parser_test.dart` (line format, split chunks), `test/sse_event_test.dart`, `test/sse_client_test.dart` (fake transport `test/sse_fakes.dart` + fake_async: token, 3 s reconnect, disconnect, token change; `SseProvider`), `test/sse_transport_io_test.dart` (`MockClient.streaming`: headers, chunks, non-200, idle timeout), `test/connection_indicator_test.dart`, `test/sse_session_test.dart` (the channel follows sign-in, logout, a new token), `test/party_provider_test.dart` (seat assignment — never the same bot twice, "none available", freeing a seat —, the create body, join on `ALREADY_IN_PARTY`, the lobby's events and its owner/only-human rules, two lobby loads answering out of order, presence and its five-player cap on the first load), `test/party_screens_test.dart` (the three screens end to end over `test/party_helpers.dart`'s fake backend (its `partiesGate` holds `GET /party` back): cards and their buttons, seat selectors, start disabled below 3, a player joining through the stream, start/leave/delete, a failed first load, a row without `maxPlayers`, `NOT_IN_PARTY`, no presence count before the first answer, the system Back from the form, the lobby and the game (`back navigation`), and that each screen fits 360×740, and 360×740 again at text scales 1.5 and 2.0), `test/parties_ux_test.dart` (P1–P4 in Roboto at 360×740, text scales 1.0 and 1.5: my games first and the running one on top with its badge and amber border, no "your turn" badge, two-line cards with one button — Resume filled, Lobby and Join outlined —, the amber Create button clear of the last card, the skeletons, the invitation and its push to the form, pull-to-refresh, a failed refresh keeping the list), `test/lobby_ux_test.dart` (S1–S4 in Roboto at 360×740, text scales 1.0 and 1.5: the invite code and Copy to the clipboard, the settings chips on one line, the online dots, the bot level chip, the free seat's hint and no add-a-bot button, the reason line, Start above Leave on screen, Delete only in the ⋮ menu and still confirmed), `test/card_test.dart` + `test/rules_test.dart` (the React utils tests, ported; `suggestPlays` — the run a joker completes, the mockup hand, 500 random hands whose suggestions are all legal plays), `test/hand_suggestions_test.dart` (J8: the chips above the cards, a chip selecting its cards and a card tap deselecting one, the fr/en labels, no chip on a disabled or compact hand, 360×740 at text scale 1.5), `test/card_widgets_test.dart` (every face of the 54 ids parses and renders; card — its three looks, each stronger, no colour filter in any, a screen reader's tap, none when disabled —, back and its width, fan — widths, balanced rows, 48 px visible for 1 to 13 cards at 300 to 600 px, a tap at the centre of each visible part, the lift that keeps its place), `test/game_provider_test.dart` (the derived table, the selection and its reset, each move's body, a refused move that keeps the table, a failed refresh that keeps it too, two loads answering out of order, a discard card gone from the pile that is not posted, the hand-size range, the events — `partyStarted` included), `test/game_screen_test.dart` (the board end to end over `test/game_helpers.dart`'s fake backend: each mode, my turn and not my turn, an invalid play that keeps the board, a backend refusal in a snack bar, a ZapZap that held, a counteracted one with its penalty, a finished game with its winner, a refresh that fails leaving the table under its banner, Clear dropping the discard card, a Golden Score that ends pulling the hand size back into range, the players and their scores above the hand-size selector (T3), Back leading to the parties — from the list, popped and replacing the game's browser entry —, the cards (seven in hand at 360×740: 76 px or more, a tap at the centre of each visible part selects that card; the felt's cards 70 px on a phone and 84 wide, the played ones 49 on a phone in the draw step; a screen reader's tap on `7 de Cœur` in the hand and in the pile, no tap on a disabled hand; at 1.5, no overflow and under 24 px between felt and hand), a waiting client entering the board on `partyStarted` or by Retry, and every mode at 360×740 at text scales 1.0, 1.5 and 2.0, the wide layout at each scale), `test/game_turn_ux_test.dart` (J1–J6, T1, T2: the step chips, the named button, the hand value and its gauge, the ZapZap sheet — cancel and confirm —, the felt in each step and the deck as a target, the hand-size hint and 48 dp targets, the compact opponents at 390×844 and 1280×800 at text scales 1.0, 1.5 and 2.0, and the new pieces at 360×740), `test/game_felt_test.dart` (the casino felt: the radial gradient, the 6 px rim, the painted texture and watermark and no image, the amber draw edge on the rim with a contrast over 4.5 against both ends of the wood, no overflow at 360×740 at 1.5; the deck as big as a pile card at 70 and 84 px, its label above in the pile label's rendered style, tops in line, its stack thinning, its edge only when drawable), `test/game_table_message_test.dart` (a discard take named and shown small, in fr and en, a joker by its name; a deck draw with a `cardId` naming nothing; a discard take without one; nothing in the draw step), `test/game_felt_layout_test.dart` (the phone felt in the draw step at 360×740 and 390×844, text scales 1.0 and 1.5, in Roboto: never cut, the deck and the take hint in view; in the draw step, 7 and 10 cards in hand each show their rank-and-suit corner and 60 % of their height; the amber draw button), `test/date_format_test.dart`, `test/history_screens_test.dart` (the two tabs, empty, failed and retried, opening the details; summary, standings, the round table and its legend, a counteracted caller in red even on the lowest hand, the system Back from the details, the signed-in app bar, an unknown game), `test/history_ux_test.dart` (H1–H3, St1, St2: the place badge from `userPlacement`, none without it, my score, no place on the public tab, the fr/en ordinals, the summary and its push to the statistics, the invitation and its push to the create-party form, the hero figures, `134` without `.0`, the ZapZap bar with and without calls, all at 360×740 at text scales 1.0, 1.5 and 2.0), `test/stats_screen_test.dart` (personal figures, my highlighted row and a row that is not mine, the bot filter and its fallback to All, one failing section among three), `test/delete_account_test.dart` (the menu entry, the dialog, `DELETE /api/auth/me` with the password and the Bearer, the login screen with the storage erased; cancel sending nothing; 403 `INVALID_PASSWORD`, 409 `ACTIVE_PARTY` and `LAST_ADMIN` shown in the dialog, still signed in; a Google account sending a fresh token as `credential`, and its refusal; `playerName` in fr/en; « Joueur supprimé » in the game details and the history list, never the stand-in username), `test/tutorial_test.dart` (The example game, above), `test/app_bar_test.dart` (the app-bar menu opens the history and the statistics, the system Back returns to the list, history then statistics unwound one Back at a time, no Admin entry for a player, an admin's leading to `/admin` and Back; no sign-out icon in the bar, Sign out in the menu, Cancel keeping the session and the screen, confirming landing on login with the storage erased, the dialog in English; the rules sheet over the parties and over the game screen at 360×740 with the table behind, closed by Back, its values those of `GAME_RULES.md`, scrolled to its end at 360×740 at text scales 1.0, 1.5 and 2.0), `test/admin_screen_test.dart` (a non-admin on `/admin` or `/admin/users` lands on `/parties` with no admin call, the three tabs, `/admin/statistics` and an unknown tab, a tab loading on its first show only; over `test/admin_helpers.dart`'s paging fake backend: `limit=50&offset=0`, 50 rows a page of 120 and Next/Previous, the search filtering the page, no actions on one's own row and `admin`'s, grant then revoke with the body sent, cancel sends nothing, delete, a 400 refusal in a snack bar, a failed load and Retry; the users tab at 360×740 at text scales 1.0, 1.5 and 2.0), `test/admin_parties_test.dart` (the rows and the seats from the `settings` JSON string, the status filter sent as `status=` and narrowing the list, no stop on a finished party, cancel and a tap outside sending nothing, stop then the status reading finished, delete, a 400 in a snack bar, a failed load and Retry; at 360×740 at 1.0, 1.5 and 2.0), `test/admin_stats_test.dart` (the 30 UTC days and the painter drawing 30 bars on a recording canvas; the cards, the breakdown, the chart and its semantics label, the most active; a Rust-precision rate, an empty `daily` and no active player, a failed load and Retry; at 360×740 at 1.0, 1.5 and 2.0), and a `phone width` group in each at 360×740, text scale 1, 1.5 and 2.0; `test/text_scale_test.dart` (home, splash, login, register, not-found and the game screen's three message states at 360×740, text scale 1.5 and 2.0); `test/history_helpers.dart` builds a session for a given user id and an `ApiClient` routing each path to a fixture |
| `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:9999` | the web client against a local backend; add `--dart-define=GOOGLE_CLIENT_ID=<web client id>` for the Google button (the popup then refuses any origin the web client does not list: `localhost` ports are not listed) |
| `flutter build web --base-href /app/` | the PWA → `build/web/`, to be served under `/app/` |
| `flutter run -d <device> --dart-define=API_BASE_URL=http://10.0.2.2:9999` | the Android debug app on an emulator, against a backend on the host |
| `flutter build apk --debug` | `build/app/outputs/flutter-apk/app-debug.apk`; needs the Android SDK (`~/sdk/android`). Add `--dart-define=API_BASE_URL=http://<LAN IP>:9999` for a device on the LAN; without it the APK talks to production over HTTPS |
| `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/play_round_test.dart -d web-server --dart-define=API_BASE_URL=http://localhost:<port>` | the end-to-end test: a fresh user plays a round against two bots on a live backend; needs the backend and a chromedriver — procedure in [[Testing]]. `scripts/flutter_e2e.sh` (repository root) starts the Rust backend on a fresh database and runs it, as the CI job `flutter-e2e` does |
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
- **API layer (2026-09-22, `feat/flutter-api-client`).** Models parse both backends
  leniently rather than one strictly: production runs Node, the target is Rust, and their
  shapes differ in types more than in names. The 401 hook is a plain callback on
  `ApiClient`, not a dependency on the auth provider, so the client has no knowledge of
  routing and the auth pull request only has to set it. Error text stays out of the UI:
  screens map `ApiException.code` to ARB strings.
- **The Node backend is removed (2026-09-25, chore/remove-node-backend).** This page lost its Node-vs-Rust comparisons (CORS, SSE, presence, shapes, the refusals the client pre-empts); the client code kept its Node-shape branches until refactor/flutter-drop-node-branches (2026-09-25), which checked each against `zapzap-rust/src/api/routes/*.rs` and `api/sse.rs` and dropped those Rust never reaches: the `isOwner` fallback on `ownerId`, the `winnerUserId` placement fallback, the JSON-string `handCards`, the unnamed SSE `message` and `userStatusChanged`, `NextRoundResult.isGoldenScore`/`enteringGoldenScore`, a `null` `roundScores`, a `join` without `playerIndex`, a leaderboard row without `averageScore`, and the old Rust party settings keys with the lobby's hand-size chip (`lobbyHandSizeChip`). The parsing kept for Rust answers before 2026-09-24 (list-shaped maps, bare indexes, RFC 3339 dates) was left alone. Its code can still be read at `232f168` (the last master commit holding `src/`, e.g. `git show 232f168:src/api/server.js`) and `0bfd407` (the last commit whose `docker-compose.yml` builds it, the former rollback target).
- **The page is split by sub-topic (2026-09-27, `docs/split-frontend-flutter`).** At 1645
  lines any Flutter task loaded the whole page to find one section. Its sections moved
  unchanged, each with its Decisions & History items, to [[FlutterAuth]], [[FlutterRealtime]],
  [[FlutterParties]], [[FlutterGameBoard]], [[FlutterGameUi]], [[FlutterHistoryAdmin]],
  [[FlutterI18n]] and [[FlutterAndroidPwa]], each under 400 lines; this page keeps the
  status, stack, layout, API configuration and layer, theme, build and tests, and a pointer
  where each moved section stood.
