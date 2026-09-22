# FrontendFlutter

> Scope: the Flutter client in `frontend-flutter/` — Android app and PWA — its layout, API
> configuration, theme, localisation, build and tests.
> Related: [[Architecture]] · [[Frontend]] · [[Api]] · [[Deployment]] · [[Testing]]
> Updated: 2026-09-22

## Facts

### Status

- **Scaffold.** A home screen that routes to a placeholder login screen, and a not-found
  screen (`frontend-flutter/lib/router.dart`). Parity with the React client ([[Frontend]]:
  game, lobby, history, stats, Google sign-in, admin) is the goal, not the state.
- The card model, play rules and card widgets exist (below) but no screen uses them yet.
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
| `providers/app_providers.dart` | `appProviders()` — the one list handed to `MultiProvider`; a new provider is one more entry |
| `services/api_config.dart` | `ApiConfig` (below) |
| `utils/app_theme.dart` | `AppColors`, `AppTheme.dark()` |
| `models/card.dart` | `GameCard` (not `Card`: Material has one) — id, suit, rank, value, face asset (below) |
| `utils/rules.dart` | `analyzePlay` / `isValidPlay` / `playType`, `handValue`, `isZapZapEligible`, `handValueDisplay`, `sortCards` (below) |
| `utils/card_l10n.dart` | `CardL10n` on `AppLocalizations`: suit and card names, `playErrorMessage(PlayError)` |
| `screens/` | `home_screen.dart`, `login_screen.dart` (placeholder), `not_found_screen.dart` |
| `widgets/` | `app_logo.dart`; `playing_card.dart`, `card_back.dart`, `card_fan.dart` (below) |
| `models/`, `repositories/` | the API models and their data access |
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
  (`frontend-flutter/.gitignore`): `flutter pub get` (and so `analyze`, `test`, `build`)
  regenerates them. Keeps parallel pull requests that each add strings free of conflicts in
  generated code.
- `test/l10n_test.dart` fails when a key is in one ARB file and not the other.

### Build and test (from `frontend-flutter/`)

| Command | What |
|---|---|
| `flutter analyze` | lints, must be clean |
| `flutter test` | `test/api_config_test.dart`, `test/app_test.dart` (routing, fr/en, theme), `test/l10n_test.dart`, `test/card_test.dart` + `test/rules_test.dart` (the React utils tests, ported), `test/card_widgets_test.dart` (every face of the 54 ids parses and renders; card, back, fan) |
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
- **Card faces from SVG assets (2026-09-22).** React draws faces with the `cardmeister` web
  component, which Flutter cannot use; the CC0 English-pattern deck was picked over drawing
  faces in code. `analyzePlay` returns codes, not React's English `reason` strings, so the
  UI localises them.
- **Generated l10n not committed (2026-09-22)**, unlike countscore: several Flutter pull
  requests will add strings in parallel, and generated files would conflict on every one.
