---
name: flutter-device-test
description: Drive the ZapZap Android app (com.zapzap.app) on the user's real phone (Pixel 9 Pro XL) from WSL2 — Wi-Fi adb with the phone's ip:port asked of the user (never scanned), install a debug or release APK, the screenshot → read → tap loop for functional and UX/UI checks, logcat, `pm clear` for a clean start, and the integration_test round against two bots run on the phone against a Rust backend started on this machine's LAN address (never production). Use when testing the Flutter client on a phone, checking Google sign-in, the SSE channel or secure token storage on Android, smoke-testing the R8 release APK, or running integration_test on a device. Triggers: "teste sur mon téléphone", "test on my phone", "test sur le pixel", "real device", "adb", "screenshot the app", "integration test on the phone", "release APK smoke".
---

# Testing ZapZap on the phone

The app's Android-only code — the SSE transport (`lib/services/sse_transport_io.dart`), the
secure token storage (`lib/services/token_storage_io.dart`), Google sign-in through Credential
Manager, R8 in the release build — is unit-tested only on the host. This skill runs it on the
user's phone. No emulator: `/dev/kvm` is not usable here (`.llmwiki/FrontendFlutter.md`
§ Android). Adapted from countscore's skill of the same name.

## The device

| Detail | Value |
|---|---|
| Model | Pixel 9 Pro XL, Android 16 (API 36) |
| adb id | `<ip>:<port>` over Wi-Fi — changes each time wireless debugging restarts; **ask the user** |
| Screen | 1008×2244 logical px (`adb shell wm size`) — `input tap` takes these directly |
| `adb` | `/home/vemore/sdk/android/platform-tools/adb` |
| Package | `com.zapzap.app`, activity `com.zapzap.app/.MainActivity` |

### Connect

```bash
adb devices          # already there? its id is the <ip>:<port> in the first column
```

If the phone is not listed (or `offline`), **ask the user for `<ip>:<port>`**: Settings →
System → Developer options → Wireless debugging → "IP address & Port". **Never scan the LAN
for it**, and `adb mdns services` sees nothing from WSL2 anyway.

```bash
adb disconnect <ip>:<port>   # only if listed as offline
adb connect <ip>:<port>
flutter devices              # Flutter sees it
export DEV=<ip>:<port>
```

**First pairing of this machine**: the user opens "Pair device with pairing code" on the phone
and reads out *its* `<ip>:<pairing port>` and 6-digit code — a different port from the
connect one. Then `adb pair <ip>:<pairing port> <code>`, and `adb connect` as above. Never run
`adb pair` without the code the user gave.

## Builds

| Build | Talks to | Signed with | Use for |
|---|---|---|---|
| `flutter run -d $DEV --debug` | production by default; `--dart-define=API_BASE_URL=http://<LAN IP>:9999` for a local backend (debug allows cleartext) | local debug key (its SHA-1 is a registered Google client) | the loop below, Google sign-in, the integration round |
| `flutter build apk --release` | production only (HTTPS: release has no cleartext) | the upload key with `key.properties`, else the debug key | the R8 smoke of a release (`release-android` § 5) |

Add `--dart-define=GOOGLE_CLIENT_ID=<web client id>` (the NAS `.env`'s
`VITE_GOOGLE_OAUTH_CLIENT_ID`) to any build that should offer Google sign-in.

A debug install, a release install and a Play install carry different keys, so `adb install
-r` from one over another fails `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: `adb -s $DEV uninstall
com.zapzap.app` first — it wipes the app's data, which is the point of a clean test.

Run `flutter run` as a background Bash task so hot reload stays available.

## The screenshot → read → act loop

```bash
adb -s $DEV exec-out screencap -p > /tmp/zz_01_login.png   # 1. capture, named per step
# 2. Read the PNG with the Read tool — the visual check is the point; never skip it
adb -s $DEV shell input tap <x> <y>                         # 3. act, logical coordinates
adb -s $DEV shell input swipe <x1> <y1> <x2> <y2> [<ms>]
adb -s $DEV shell input text 'hello'                        # into the focused field; %s is a space
adb -s $DEV shell input keyevent KEYCODE_BACK               # also hides the keyboard
# 4. repeat
```

- The soft keyboard covers the lower half: `KEYCODE_BACK` before tapping a bottom button.
- **Passwords**: the user types their own on the phone. Never put a real password in an
  `input text` command, a file or a log. Test accounts on the LAN backend are fine.
- Judge each screenshot: primary action obvious, 48 dp touch targets, contrast, the
  status and navigation bars (slate `#0f172a`, light icons), empty, error and loading
  states, fr and en. Report a punch list with the screenshot names.

Animations and transitions: `adb -s $DEV shell screenrecord --time-limit 20 /sdcard/zz.mp4`,
`adb pull` it, `ffmpeg -i zz.mp4 -vf fps=4 /tmp/zz_%03d.png`, read the frames.

## What to check on the phone

1. **Password login against production** (default URL): lands on the parties screen, and the
   connection indicator shows the SSE channel up. Force-stop and reopen: still signed in —
   the token was read back from secure storage.
2. **Google sign-in** on a debug build with `GOOGLE_CLIENT_ID`: lands on the parties screen.
   A configuration error means the signing key's SHA-1 is not registered
   (`.llmwiki/FrontendFlutter.md` § Android).
3. **A round against two bots** — the integration test below, on the LAN backend.
4. **Release APK** (a release): 1 and 2 on it, then
   `adb -s $DEV logcat -d | grep -E 'ClassNotFoundException|NoSuchMethodException'` empty —
   R8 stripped nothing the app needs.

## The integration round on the phone — against a LAN backend, never production

`frontend-flutter/integration_test/play_round_test.dart` **registers a fresh user** every run,
so it never runs against production. Start a backend on a throwaway database on this machine:

```bash
W=$(mktemp -d)
cd zapzap-rust && cargo build --locked
DB_PATH=$W/device.db target/debug/zapzap-backend seed           # the bot accounts
JWT_SECRET=$(openssl rand -hex 32) DB_PATH=$W/device.db PORT=9999 \
  BOT_ACTION_DELAY_MS=0 target/debug/zapzap-backend             # background task
```

(`CARGO_TARGET_DIR` may point elsewhere in a worktree: use the binary it names.)

The phone reaches it on this machine's **LAN address**: WSL2 runs in mirrored networking
(`~/.wslconfig`), so it is the Windows host's — `ip -4 addr` lists it (`192.168.1.x`). Check
from the phone's browser that `http://<LAN IP>:9999/api/health` answers. If it does not, the
Windows firewall blocks it: ask the user to allow inbound TCP 9999 for WSL (PowerShell as
administrator: `New-NetFirewallHyperVRule -Name zapzap-dev-9999 -DisplayName "ZapZap dev
9999" -Direction Inbound -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -Protocol TCP
-LocalPorts 9999`), and to remove it afterwards.

```bash
cd frontend-flutter
flutter drive -d $DEV \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/play_round_test.dart \
  --dart-define=API_BASE_URL=http://<LAN IP>:9999
```

Pass: `All tests passed.` Then stop the backend by its port (`lsof -ti:9999 | xargs kill`)
and remove `$W`.

## Cheatsheet

```bash
adb -s $DEV install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s $DEV uninstall com.zapzap.app
adb -s $DEV shell am start -n com.zapzap.app/.MainActivity
adb -s $DEV shell am force-stop com.zapzap.app
adb -s $DEV shell pm clear com.zapzap.app            # wipe the app's data: a clean start
adb -s $DEV shell cmd locale set-app-locales com.zapzap.app --locales en   # "" resets
adb -s $DEV logcat -c && adb -s $DEV logcat flutter:I '*:E'
adb -s $DEV shell dumpsys battery | grep level
adb -s $DEV shell svc power stayon true              # screen on while testing; false after
```

The debug APK from CI (`app-debug` artifact, `.llmwiki/FrontendFlutter.md` § Android) is
signed by the runner's throwaway key: Google sign-in fails on it; use it for password flows.

## Limits

- Stay inside `com.zapzap.app`: `pm clear` of our package, nothing wider on the phone.
- Restore what you changed: the app locale, `stayon`, the firewall rule.
- Not for unit or widget tests (`flutter test` on the host), and not for CI.
