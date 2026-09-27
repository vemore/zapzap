# FlutterAndroidPwa

> Scope: the Flutter client's two targets: the Android app (CI APK, release signing, keys, OAuth
> clients, manifest, icons, system bars) and the PWA image (Dockerfile, nginx, manifest).
> Related: [[FrontendFlutter]] · [[FlutterAuth]] · [[Release]] · [[Deployment]] · [[Testing]] · [[Hooks]]
> Updated: 2026-09-27

## Facts

### Android (`frontend-flutter/android/`)

- **No store yet**: the release build signs with the upload key when there is one (below),
  but no bundle has been sent to Play. The procedure that builds, verifies
  (`scripts/verify_aab.sh`) and publishes (`scripts/play_publish.py`) a bundle is the
  **`release-android`** skill; the Play state is [[Release]]. Driving the app on the user's
  phone (Wi-Fi adb, the screenshot loop, the integration round against a LAN backend) is the
  **`flutter-device-test`** skill.
- **Download the debug APK from CI**: every run of the `flutter` job (a pull request or a
  push touching `frontend-flutter/`) uploads it as the artifact **`app-debug`**, kept 14 days —
  the run's page (Actions → CI → the run) → *Artifacts* → `app-debug`, a zip holding
  `app-debug.apk`; or `gh run download <run id> -n app-debug`. Install with
  `adb install -r app-debug.apk`. It talks to production over HTTPS by default. Signed with
  the runner's throwaway debug key, so Google sign-in fails on it (below); sign in with a
  password. CI installs `platforms;android-36` and `build-tools;36.0.0` with `sdkmanager`
  and caps the Gradle heap in `~/.gradle/gradle.properties` (the project's asks for 8 GB).
- **Release signing** (`android/app/build.gradle.kts`, ported from countscore): when
  `frontend-flutter/android/key.properties` exists, the `release` build type signs with the
  keystore it names (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; a missing or
  empty one fails the build naming it — `android/key.properties: missing storePassword` —,
  never printing a value). Without the file — CI, a worktree:
  - a **release APK** (`flutter build apk --release`, Gradle `assembleRelease`) is signed
    with the **debug key** and still builds, printing `WARNING: no android/key.properties --
    this release build is signed with the DEBUG key` (through `logger.error`: `flutter
    build` hides Gradle's stdout, so a `logger.warn` would only show under `-v`);
  - a **release bundle** (`flutter build appbundle --release`, `bundleRelease`) is
    **refused** before any task runs (`gradle.taskGraph.whenReady`): `No android/key.properties:
    a release bundle … must be signed with the upload key` — a Play bundle is never
    debug-signed.
  Both are CI steps of the `flutter` job ("Release build without key.properties",
  "Release bundle without key.properties is refused"). The release build also runs R8
  (`isMinifyEnabled`, `isShrinkResources`, keep rules in `android/app/proguard-rules.pro`:
  the Flutter embedding and plugins, Credential Manager's Play services provider and
  `googleid` for google_sign_in, flutter_secure_storage). A class R8 strips shows up at run
  time as `ClassNotFoundException` in logcat — add a `-keep` rule. Checked on the Pixel 9 Pro XL on
  2026-09-26 (release 1.0.0+1, upload-key signed, `GOOGLE_CLIENT_ID` set): Google sign-in,
  the SSE indicator up, still signed in after a force-stop, a turn played against two bots,
  and no `ClassNotFoundException` / `NoSuchMethodException` / `FATAL EXCEPTION` in logcat.
- **The keys**:
  - **Upload key** — alias `zapzap-upload`, JKS, RSA 2048, ~27 years — made **once** by
    `scripts/generate_keystore.sh`, which writes `~/zapzap-upload-keystore.jks` (`keytool` under `umask 077`, then mode 600;
    `ZAPZAP_KEYSTORE=<absolute path>` overrides it), refuses a path inside a git work tree
    — `$HOME` itself being a dotfiles repository passes only if that repository ignores the
    keystore (`git check-ignore`) — and never overwrites an existing keystore. Then copy
    `frontend-flutter/android/key.properties.template` to `android/key.properties` (next to
    the template) and fill it in. Neither the keystore nor `key.properties` is in the
    repository: `android/.gitignore` ignores `key.properties`, `*.jks`, `*.keystore`, the root
    `.gitignore` `*service-account*.json`, and the commit hook refuses all of them, whatever their case, and any added text
    file holding a Google credential `"type"` — `service_account`, `authorized_user`,
    `external_account`, `impersonated_service_account` — whatever its name ([[Hooks]]).
  - **Backup**: the keystore file **and** its password, in the password manager plus an
    offline copy (encrypted USB). Lost, the app can only be updated after an upload-key
    reset requested from the Play Console (days, and only once Play App Signing is on).
  - **Play App Signing key** — once the app exists in the Play Console, Google re-signs
    what it serves with its own app-signing key; the upload key only proves the upload.
    Its SHA-1 is in Play Console → the app → Test and release → App integrity → App
    signing.
  - **SHA-1s to register** as Android OAuth clients (package `com.zapzap.app`) in
    `zapzap-481109` (Google sign-in on Android, below): the local debug key (done
    2026-09-24), the **upload key** (`keytool -list -v -keystore ~/zapzap-upload-keystore.jks
    -alias zapzap-upload`, the `SHA1:` line) for a release APK installed by hand, and
    **Play App Signing's** for what users install from Play. Both registered 2026-09-25:
    "ZapZap Android upload" and "ZapZap Android Play" (SHA-1s in [[Release]] § Keys).
  - Check which key signed a build: `jarsigner -verify -verbose -certs -keystore
    ~/zapzap-upload-keystore.jks build/app/outputs/bundle/release/app-release.aab` prints
    `(zapzap-upload)` after each signer; without `-keystore` the alias shows as the
    `META-INF/ZAPZAP-U.SF`/`.RSA` names. For an APK: `~/sdk/android/build-tools/36.0.0/apksigner
    verify --print-certs <apk>` (`CN=Android Debug` is the debug fallback).
- Application id and namespace `com.zapzap.app` (`android/app/build.gradle.kts`);
  `MainActivity` in `android/app/src/main/kotlin/com/zapzap/app/`. Label `ZapZap`.
- `INTERNET` is in the **main** manifest (`android/app/src/main/AndroidManifest.xml`), so
  every build type reaches the API, not only debug.
- Cleartext HTTP is allowed in the **debug** build only: `android/app/src/debug/AndroidManifest.xml`
  sets `android:networkSecurityConfig` to `android/app/src/debug/res/xml/network_security_config.xml`
  (`cleartextTrafficPermitted="true"`, system CAs). Profile and release keep Android's
  default, HTTPS only — so they only talk to the production default URL or an `https://` one.
- The app sends no `Origin` header; the backend's CORS layer is permissive anyway (`zapzap-rust/src/api/mod.rs`).
- Launcher icon: the lucide `zap` bolt (the React client's icon set) in amber `#fbbf24` on
  slate `#0f172a`. Sources `frontend-flutter/assets/icon/icon.svg` and `icon_foreground.svg`
  (adaptive-icon foreground, inside the safe zone); the PNGs next to them are rendered with
  `rsvg-convert -w 1024 -h 1024 <x>.svg -o <x>.png`, then `dart run flutter_launcher_icons`
  (config in `frontend-flutter/flutter_launcher_icons.yaml`, not in `pubspec.yaml`) writes
  the `mipmap-*`, `drawable-*` and `values/colors.xml` resources.
- System bars: the navigation bar is the app's slate `#0f172a` with light buttons, the status
  bar transparent with light icons — `AppTheme.systemOverlayStyle`
  (`lib/utils/app_theme.dart`), set as an `AnnotatedRegion` around every route
  (`MaterialApp.router`'s `builder` in `lib/app.dart`) and as `appBarTheme.systemOverlayStyle`.
  `systemNavigationBarContrastEnforced: false`: with targetSdk 36 the app is edge-to-edge on
  Android 15+, where the colour is ignored and the contrast scrim is what drew a light grey
  bar under 3-button navigation. Before the first frame, `LaunchTheme` and `NormalTheme`
  (`android/app/src/main/res/values{,-night}/styles.xml`) set the same bar.
  `test/system_ui_test.dart` pins the style the app sends and the window themes.
- `test/android_config_test.dart` pins the id, the main-manifest `INTERNET`, the
  debug-only cleartext, the release signing with its debug-key fallback and R8, the
  Flutter and google_sign_in keep rules, the ignored `key.properties`, keystores and Gradle
  root `build/` (`android/.gitignore`: a failed Gradle build writes
  `android/build/reports/problems/`), and the template's commented-out `playServiceAccount=`
  line (the Play API key, [[Release]]).
- **Google sign-in on Android** needs, in the Google Cloud project that owns the web client
  id (`zapzap-481109`), an OAuth client of type **Android**
  for the package `com.zapzap.app` and the SHA-1 of the key that signs the APK. Nothing of
  it is in the repository: no `google-services.json`, no client secret — the app sends the
  web client id as `serverClientId`, and Google matches the running app by package and
  signature. Registered 2026-09-24: "ZapZap Android debug", the SHA-1 of the local debug
  keystore `~/.android/debug.keystore` (`98:33:9F:AE:5E:05:7E:18:34:DE:01:C2:7E:51:DF:B1:AE:15:C4:E1`);
  2026-09-25: "ZapZap Android upload" (the upload key's SHA-1) and "ZapZap Android Play"
  (Play App Signing's), both in [[Release]] § Keys.
  Every other signing key (another machine's debug keystore, a release key, Play app
  signing) needs its own Android client — or its SHA-1 added — or `authenticate()` fails
  with a configuration error. To register one:
  1. `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey
     -storepass android -keypass android` (the keystore appears with the first
     `flutter build apk --debug`), and copy the `SHA1:` line;
  2. console.cloud.google.com → project `zapzap-481109` → Google Auth Platform → Clients →
     Create client → type Android, package `com.zapzap.app`, that SHA-1 → Create (it can
     take minutes to hours to apply);
  3. build with the web client id: `flutter build apk --debug
     --dart-define=GOOGLE_CLIENT_ID=<web client id>` (the NAS `.env`'s
     `VITE_GOOGLE_OAUTH_CLIENT_ID`).
  Google sign-in passed on the user's Pixel 9 Pro XL on 2026-09-25 (debug build, local
  debug key); the `flutter-device-test` skill repeats the check.
- Emulator: `~/sdk/android` has an `android-31` `google_apis` x86_64 image but no AVD, and
  the emulator needs KVM (`/dev/kvm`, group `kvm`); without it, check the APK instead:
  `~/sdk/android/build-tools/36.0.0/aapt2 dump badging <apk>` (package, label,
  permissions) and `aapt2 dump xmltree --file AndroidManifest.xml <apk>`
  (`networkSecurityConfig` present in the debug APK only). A real phone is the
  `flutter-device-test` skill.

### The PWA image (`frontend-flutter/Dockerfile`, `frontend-flutter/nginx.conf`)

- Stage 1 is `debian:bookworm-slim` + the official Flutter SDK archive, **pinned to 3.47.2**
  with its sha256 (`ARG FLUTTER_VERSION`, `ARG FLUTTER_SHA256`) — the version
  `.github/workflows/ci.yml` pins; bump the two together. It builds as a non-root user
  (`flutter` and `pub` refuse to run as root), runs `pub get --enforce-lockfile`, `gen-l10n`
  and `flutter build web --release --base-href /app/ --no-web-resources-cdn
  --dart-define=GOOGLE_CLIENT_ID=…`.
- **`ARG GOOGLE_CLIENT_ID`**, empty by default: both compose files pass the `.env`'s
  `VITE_GOOGLE_OAUTH_CLIENT_ID` (the React image's own build argument), so production shows
  the Google button on the same, already authorised origin; a build without it (CI's
  `image` job) has no button. `test/pwa_build_config_test.dart` pins the ARG and the two
  compose files.
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
- Deep links are path URLs (`usePathUrlStrategy()`, [[FlutterAuth]]): `/app/parties` and
  `/app/history/<partyId>` open their screen from a cold tab or a reload, the fallback
  serving `index.html` and the app reading the route off the path. No in-app URL carries
  `#`. The extension rule is why a route may never contain a dot.

## Decisions & History

- **The PWA image builds the SDK in, rather than reusing a published Flutter image
  (2026-09-23, `feat/flutter-pwa-deploy`).** `ghcr.io/cirruslabs/flutter` publishes no
  `3.47.2` tag, and a floating tag would silently change the SDK under the deploy; the
  official archive plus its sha256 pins it exactly. The bundle also gets its own image and
  container rather than being copied into the React one, so the two clients are built and
  rolled back separately ([[Deployment]]).
- **The web icons are the launcher icon (2026-09-23).** Flutter's default web icons shipped
  until then; they are now rendered from the same `assets/icon/` SVGs as the Android
  launcher icon, plus a maskable variant for the install prompt.
- **Android: `com.zapzap.app`, cleartext in debug only (2026-09-22).** The scaffold's
  generated `com.zapzap.zapzap` was replaced before any install existed. Plain HTTP is needed
  to reach a local backend from the emulator or the LAN, but a release build must never
  downgrade to it, so the network security config lives in `src/debug/` rather than in the
  main manifest.
- **Release signing ported from countscore (2026-09-25, feat/flutter-android-release-signing).**
  Play refuses a bundle signed with a debug key, so the `release` build type gained
  countscore's `key.properties` signing config, R8 and the keystore script. Unlike
  countscore, a missing `key.properties` falls back to the debug key instead of an empty
  signing config, so CI and worktrees keep building a release APK — but only an APK: the
  review of #113 made `bundleRelease` fail without it, since a Play bundle must never be
  debug-signed and a worktree has no `key.properties`. The script refuses a path inside a
  repository (`$HOME` itself only when that repository ignores the keystore) and runs `keytool` under `umask 077`. The real upload key and its OAuth client are the user's
  manual steps.
