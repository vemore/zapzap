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
- No CI job yet: `scripts/ci_scope.sh` has no `frontend-flutter/*` case, so a path there
  falls to the catch-all and runs **every** job; none of them runs Flutter. Verification is
  local (below).

### Stack

- Flutter 3.47.2 / Dart 3.13.2, SDK at `~/sdk/flutter` (not pinned in the repository);
  `environment.sdk: ^3.13.2` (`frontend-flutter/pubspec.yaml`).
- Platforms: `android` and `web` only (`flutter create --platforms=android,web --org
  com.zapzap`). Android: the section below.
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
- Android talking to a local backend: `--dart-define=API_BASE_URL=http://10.0.2.2:9999`
  from the emulator (`10.0.2.2` is the host's loopback), `http://<LAN IP>:9999` from a
  device. Plain HTTP works in the **debug** build only (section Android).
- `ApiConfig` is provided to the tree as `Provider<ApiConfig>` (`providers/app_providers.dart`).

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
| `flutter test` | `test/api_config_test.dart`, `test/app_test.dart` (routing, fr/en, theme), `test/l10n_test.dart`, `test/android_config_test.dart` |
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
- **Generated l10n not committed (2026-09-22)**, unlike countscore: several Flutter pull
  requests will add strings in parallel, and generated files would conflict on every one.
- **Android: `com.zapzap.app`, cleartext in debug only (2026-09-22).** The scaffold's
  generated `com.zapzap.zapzap` was replaced before any install existed. Plain HTTP is needed
  to reach a local backend from the emulator or the LAN, but a release build must never
  downgrade to it, so the network security config lives in `src/debug/` rather than in the
  main manifest.
