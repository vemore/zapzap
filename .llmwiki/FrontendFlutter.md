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
- Not deployed: no compose service, no nginx route for `/app/` yet ([[Deployment]]).
- CI: the `flutter` job (`.github/workflows/ci.yml`, Flutter pinned to 3.47.2 with
  `subosito/flutter-action`, JDK 17) runs `pub get`, `gen-l10n`, `analyze`, `test`,
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
| `screens/` | `home_screen.dart`, `login_screen.dart` (placeholder), `not_found_screen.dart` |
| `widgets/` | `app_logo.dart` |
| `models/`, `repositories/` | empty (`.gitkeep`), for the API models and their data access |
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
  commit gate and `worktree_setup.sh` run it explicitly. Keeps parallel pull requests that each add strings free of conflicts in
  generated code.
- `test/l10n_test.dart` fails when a key is in one ARB file and not the other.

### Build and test (from `frontend-flutter/`)

| Command | What |
|---|---|
| `flutter analyze` | lints, must be clean |
| `flutter test` | `test/api_config_test.dart`, `test/app_test.dart` (routing, fr/en, theme), `test/l10n_test.dart` |
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
- **CI job and commit gate (2026-09-22).** The gate is the analyzer only (seconds); tests
  and the two builds are CI's. No image flag: the client is not deployed yet.
- **Generated l10n not committed (2026-09-22)**, unlike countscore: several Flutter pull
  requests will add strings in parallel, and generated files would conflict on every one.
