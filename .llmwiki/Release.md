# Release

> Scope: the Google Play state of the Android app — package, keys and their fingerprints, how
> a release reaches Play (the scripts, the service account), what is live on which track.
> The procedure is the `release-android` skill; testing on the phone is `flutter-device-test`.
> Related: [[FrontendFlutter]] · [[Testing]] · [[Hooks]]
> Updated: 2026-09-25

## Facts

### The app

- Package `com.zapzap.app` (`frontend-flutter/android/app/build.gradle.kts`), label `ZapZap`.
- Version `frontend-flutter/pubspec.yaml` `version: 1.0.0+1`: the part after `+` is the
  `versionCode`, which must rise above every version code on every Play track.
- `targetSdk` is `flutter.targetSdkVersion`, 36 with Flutter 3.47.2 — Play refuses an update
  below 36 since 2026-08-31. `scripts/verify_aab.sh` checks it on every bundle.
- Not in the Play Console yet (2026-09-25): the app, its listing, the service account and
  the closed test are still to create (`wip/todo/2026-09-25-play-console-app-setup.md`).

### Keys

| Certificate | SHA-256 | Signs |
|---|---|---|
| Upload key (`zapzap-upload`, `~/zapzap-upload-keystore.jks`, `scripts/generate_keystore.sh`) | to record after Play Console setup | the bundle uploaded to Play |
| Play app signing key (held by Google) | to record after Play Console setup | every APK Play serves; what Android verifies |

- Read the upload key's with `keytool -list -v -keystore ~/zapzap-upload-keystore.jks -alias
  zapzap-upload`; the app signing key's is in the Console, Test and release → App integrity
  → App signing. Both SHA-1s also go to the Google sign-in Android clients
  ([[FrontendFlutter]] § Android).
- Play App Signing stays on: a lost upload key can then be reset through Play support (days).
- Signing in the build, the keystore's backup and `key.properties`: [[FrontendFlutter]]
  § Android.

### Publishing

- From this machine's terminal only, never CI: no job holds the keystore, `key.properties` or
  a Google key. CI runs the scripts' tests only (the `hooks` job, [[Testing]]).
- `scripts/verify_aab.sh [aab]` — the bundle before it leaves: signed with the upload key
  named by `frontend-flutter/android/key.properties` (debug or any other key refused), the
  bundle manifest declares `INTERNET`, `versionCode` equals the `pubspec.yaml` build number
  (from the merged release manifest, refused if stale), `targetSdk` ≥ 36, every 64-bit `.so`
  aligned for 16 KB pages. Tests: `scripts/test_verify_aab.py`, fake bundles signed by
  throwaway keystores. Checked on a real `flutter build appbundle --release` on 2026-09-25
  (throwaway key): 8 64-bit libraries, all 16 KB-aligned.
- `scripts/play_publish.py` (`uv run --script`, androidpublisher v3, PEP 723 dependencies) —
  `status` (read-only), `publish --track internal|closed|production [--commit] [--promote]
  [--rollout f] [--draft] [--listing] [--graphics] [--aab path]`, `listing [--graphics]
  [--commit]`. Every change goes through one edit, validated by `edits.validate` and deleted
  unless `--commit`. `closed` is the API track `alpha`. Production goes out `inProgress` at
  `userFraction` 0.2 by default, never 1.0. Release notes: `fr-FR` and `en-US`
  (`NOTES_LOCALES`), `store_listing/<locale>/release_notes_v<x.y.z>.txt`, ≤ 500 characters,
  fr-FR falling back to en-US. Listing locales are the `store_listing/*/` directories holding
  a `title.txt`. Tests: `scripts/test_play_publish.py`, a fake Google service.
- Credentials: a service account `zapzap-play-publisher` with no GCP role, invited in the
  Console on this app only; its JSON key at `~/.config/zapzap/play-service-account.json`
  (`chmod 600`), named by `playServiceAccount=` in `frontend-flutter/android/key.properties`
  (commented out in `key.properties.template`). Not created yet. The root `.gitignore` has
  `*service-account*.json`, and the commit hook refuses any JSON holding
  `"type": "service_account"` ([[Hooks]]).

### Versions shipped

None yet.

| Version | Tracks | Date | Tag |
|---|---|---|---|

## Decisions & History

- **2026-09-25: Play publishing ported from countscore** (user decision: the same way as
  countscore, from the developer's machine). countscore's `release-android` skill and its
  `verify_aab.sh`, `play_publish.py` and tests were ported with the package, paths
  (`frontend-flutter/`) and notes locales changed; the scripts live in `scripts/` rather than
  in the skill's directory, like the rest of the repository's tooling. Not ported:
  countscore's database round-trip (ZapZap keeps no local database — its state is on the
  server) and the Console brief script (`stage_handoff.sh`): the skill says what only the
  Console does instead.
- The tests run in the `hooks` job, not a new one: that job is already the home of the
  tooling self-tests, runs on a tooling change only, and adding a step never renames a
  required check.
