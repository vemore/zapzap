---
name: release-android
description: Build and publish a ZapZap Android release to Google Play from this machine — release worktree, upload key and key.properties, version bump in frontend-flutter/pubspec.yaml, release notes (fr-FR, en-US), policy gate, device pre-flight, signed App Bundle, artifact verification (scripts/verify_aab.sh — upload key not debug, versionCode, INTERNET, targetSdk 36, 16 KB pages), then a Play track through the Google Play Developer Publishing API (scripts/play_publish.py — status, publish --track internal|closed|production, validate, commit only on the user's go, --promote, --rollout), the store listing alone with no rebuild (play_publish.py listing), the Play API service account, the annotated tag and the GitHub release. No signing secret and no Google key in CI. Use when preparing a release, cutting a version, building or verifying a signed AAB, uploading to a Play track, promoting internal to production, updating the store listing, or setting up Play API access. Triggers: "release Android", "publie sur le Play Store", "appbundle", "AAB", "nouvelle version", "bump version", "internal testing", "upload to Play", "promote to production", "fiche Play", "store listing", "service account", "Play API".
---

# Releasing ZapZap to the Play Store

The executable path, from a clean worktree to a release on a Play track. State facts — the
keys, what is live on which track — are in `.llmwiki/Release.md`; the keystore and the
Android build are `.llmwiki/FrontendFlutter.md` § Android. Ported from countscore's skill of
the same name, which has shipped several releases this way.

**Nothing here runs in CI.** The upload keystore, `key.properties` and the Play
service-account key exist only on this machine; CI only runs the scripts' tests, against a
fake Google service and throwaway keystores (`hooks` job).

## 0. Build in a release worktree

Never build a release in a checkout another session edits — the bundle would ship whatever
is half-done there. Branch off `origin/master`:

```bash
git fetch --prune origin
git worktree add ../zapzap-release-<x.y.z> -b chore/release-<x.y.z> origin/master
scripts/worktree_setup.sh ../zapzap-release-<x.y.z> --no-frontend
ln -s /home/vemore/workspace/zapzap/frontend-flutter/android/key.properties \
      ../zapzap-release-<x.y.z>/frontend-flutter/android/key.properties
cd ../zapzap-release-<x.y.z>
```

`key.properties` is gitignored and lives in the main checkout only; its `storeFile` is
absolute, so the link works as is. Without it a release bundle is refused
(`android/app/build.gradle.kts`). `scripts/cleanup_local.sh --apply` removes the worktree,
link included, once the release pull request is merged.

## 1. Signing — first time only

```bash
scripts/generate_keystore.sh     # -> ~/zapzap-upload-keystore.jks, alias zapzap-upload
cp frontend-flutter/android/key.properties.template frontend-flutter/android/key.properties
# in the main checkout; fill in the two passwords
```

**Back up the keystore and its passwords** (password manager plus an offline copy). Play App
Signing holds the *app signing* key, so a lost *upload* key can be reset through Play
support — but that takes days during which nothing ships. Record the upload key's SHA-256 in
`.llmwiki/Release.md` (`keytool -list -v -keystore ~/zapzap-upload-keystore.jks -alias
zapzap-upload`), and its SHA-1 as a Google sign-in Android client
(`.llmwiki/FrontendFlutter.md` § Android).

## 2. Version bump

`version:` in `frontend-flutter/pubspec.yaml` is `x.y.z+build` (`1.0.0+1` until the first
release). `build` becomes the `versionCode` and must be **higher than every version code on
every track**, not just production: `play_publish.py status` (§7) is the authority. Commit
the bump on `chore/release-<x.y.z>`; the commit hook runs the gates.

## 3. Release notes

One file per notes locale, `fr-FR` and `en-US` (`NOTES_LOCALES` in `scripts/play_publish.py`):
`store_listing/fr-FR/release_notes_v<x.y.z>.txt` and
`store_listing/en-US/release_notes_v<x.y.z>.txt`.

- **At most 500 characters each** — Play's limit; the script refuses longer.
- A missing `fr-FR` file falls back to `en-US` with a note on stderr; a missing `en-US` file
  is a refusal.
- A listing locale outside `NOTES_LOCALES` needs no notes file.
- No claim that contradicts the Data Safety declaration or the privacy policy.

Commit them on the release branch with the bump.

## 4. Policy gate — before building

Each is a rejection, a removal or a blocked update if false. Check against the code, not
against the previous release.

| Check | How |
|---|---|
| **Listing matches the app** | `store_listing/*/full_description.txt` vs what the app does: an account (username, password or Google), parties against people and bots, history. |
| **Data Safety and privacy policy match** | the privacy policy (`privacy_policy.md`, served by the site) and the Data Safety form in the Console say the same thing as the app — a new data flow changes both. |
| **Account deletion** | an app with accounts must let the user delete theirs in the app *and* from a web link given in the Console. |
| **Target API ≥ 36** | every update since 2026-08-31. `verify_aab.sh` checks it. |
| **16 KB page size** | native libraries of an app targeting Android 15+. `verify_aab.sh` checks it. |
| **App registered** | developer verification in the Console; the API cannot read it. |

A failure is not fixed inside the release: stop, write a `wip/todo/` entry, tell the user,
let them decide whether it blocks.

## 5. Pre-flight

**Every release build takes the Google web client id** — without it the app has no Google
sign-in at all (`lib/services/google_sign_in_service.dart`: no `GOOGLE_CLIENT_ID`, no button).
It is the repository `.env`'s `VITE_GOOGLE_OAUTH_CLIENT_ID` (not a secret), read without
printing the file:

```bash
GCID=$(grep '^VITE_GOOGLE_OAUTH_CLIENT_ID=' /home/vemore/workspace/zapzap/.env | cut -d= -f2-)
```

```bash
cd frontend-flutter
flutter clean && flutter pub get && flutter gen-l10n
flutter analyze && flutter test
```

Then the phone — the `flutter-device-test` skill: the integration round against a **LAN**
backend on a debug build, then the **release APK** (R8-shrunk: a missing keep rule only shows
at run time, as `ClassNotFoundException` in logcat) against production:

```bash
flutter build apk --release --dart-define=GOOGLE_CLIENT_ID=$GCID
adb -s $DEV uninstall com.zapzap.app      # a debug or Play install is signed by another key:
adb -s $DEV install build/app/outputs/flutter-apk/app-release.apk   # -r over it fails
```

Pass: password login, Google sign-in (the upload key's SHA-1 must be registered, § 1), the
app restarted still signed in, a turn played, and `adb logcat` free of
`ClassNotFoundException` / `NoSuchMethodException`.

## 6. Build and verify

```bash
cd frontend-flutter && flutter build appbundle --release --dart-define=GOOGLE_CLIENT_ID=$GCID && cd ..
# -> frontend-flutter/build/app/outputs/bundle/release/app-release.aab
scripts/verify_aab.sh
```

One `OK` line per check, non-zero on the first failure:

- the bundle verifies and is signed with the **upload** key — SHA-256 compared with the
  keystore `key.properties` names; the debug key and any other key refused;
- the bundle manifest declares `INTERNET`;
- `versionCode` equals the `pubspec.yaml` build number, read from the merged release
  manifest, refused if older than `pubspec.yaml` or newer than the bundle;
- `targetSdk` ≥ 36;
- every 64-bit `.so` has LOAD segments aligned ≥ 16384.

A stale `build/` fails the freshness check — rebuild rather than work around it.

## 7. Publish through the Play API

`scripts/play_publish.py` drives the Google Play Developer Publishing API (androidpublisher
v3) with the service account below. Every change goes into one **edit**, invisible until
committed. `uv` fetches its dependencies (PEP 723, inline).

```bash
P=scripts/play_publish.py
uv run --script $P status                                  # read-only: releases per track, listings
uv run --script $P publish --track internal                # validate only — nothing is published
uv run --script $P publish --track internal --commit       # ONLY on the user's explicit go
uv run --script $P publish --track production --promote --rollout 0.2 --commit   # internal -> production
#   --track closed (API track "alpha") · --draft · --listing · --graphics
#   --aab <path>, default frontend-flutter/build/app/outputs/bundle/release/app-release.aab
#   --promote: a build Play already holds, moved to this track — no build, no upload
```

1. **`status`** — the version codes on every track. `publish` refuses a `versionCode` not
   above the highest of them, but read it first: a surprise stops the release.
2. **`publish` without `--commit`** — re-runs `verify_aab.sh`, uploads the bundle, sets the
   release `x.y.z (n)` with the fr-FR and en-US notes, the listing and graphics if asked,
   runs `edits.validate` (Google's full check) and deletes the edit. Free to run; report its
   output to the user.
3. **`--commit`** — only after the user's explicit go for *this* track: a commit publishes.
   Internal and closed go out `completed`; production goes out `inProgress` at `--rollout`
   (default `0.2`, strictly between 0 and 1 — widening to 100 % is a later decision, in the
   Console). If Google answers that `changesNotSentForReview` must be set, the script says
   so and stops: nothing was published; send the changes for review from the Console.
4. **`--promote`** — the internal → production step. Play refuses a version code it has
   seen, so promotion references the held build instead of re-uploading it: no build, no
   `verify_aab.sh`. It refuses a code on no track yet, and one already on the target track.

Order: **internal → closed → production at a staged percentage**; watch Crashes & ANRs for
48 h before widening. A personal developer account created after 2023-11-13 needs a closed
test with 12 testers opted in for 14 days before production opens.

### The store listing on its own

Title, descriptions or screenshots change with **no** version bump and no rebuild:

```bash
uv run --script $P listing              # every locale's text, validated, nothing published
uv run --script $P listing --graphics   # also the feature graphic and the phone screenshots
uv run --script $P listing --commit     # ONLY on the user's explicit go
```

> **`listing --commit` has no staged rollout.** A listing has no `userFraction`: it goes live
> for everyone, in every locale, as soon as Play accepts the edit. Say so before asking for
> the go.

The locales are read off the disk: every directory of `store_listing/` holding a
`title.txt`, `assets/` excluded. The layout the script reads:

```
store_listing/
  assets/feature_graphic.png       # shared fallback feature graphic (1024x500)
  <locale>/                        # fr-FR, en-US, ...
    title.txt  short_description.txt  full_description.txt   # <= 30, 80, 4000 characters
    video.txt                      # optional: a YouTube URL
    feature_graphic.png            # optional: overrides assets/
    screenshots/phone/*.png        # required with --graphics, at most 8, PNG only, name order
    release_notes_v<x.y.z>.txt     # fr-FR, en-US only
```

Tests (no network, no credentials, no Flutter build):
`uv run --no-project --with pytest pytest scripts/test_play_publish.py scripts/test_verify_aab.py`

### Play API access — first time only (the user does this)

1. **Google Cloud**: a project (`zapzap-481109` or another) with the **Google Play Android
   Developer API** enabled.
2. **Service account**: IAM → Service accounts → create `zapzap-play-publisher` with **no GCP
   role**; Keys → add a **JSON** key and download it.
3. **On this machine**: move it to `~/.config/zapzap/play-service-account.json`, `chmod 600`,
   and uncomment `playServiceAccount=<that absolute path>` in the main checkout's
   `frontend-flutter/android/key.properties`. **Back it up like the keystore.** It never
   enters the repository: `.gitignore` has `*service-account*.json`, and the commit hook
   refuses any JSON holding `"type": "service_account"`.
4. **Play Console** → Users and permissions → invite the service account's e-mail, **limited
   to ZapZap**, with *View app information*, *Release apps to testing tracks*, *Release to
   production*, *Manage store presence*. Propagation can take up to 24 h; until then
   `status` answers 401/403.

`status` listing the tracks proves the setup.

## 8. What only the Console does

The API does not reach: app creation, the content rating (IARC), the App content
declarations (Data Safety, ads, target audience, account deletion URL), app registration /
developer verification, the closed-test tester list, the category and store tags, countries
and pricing. The user does these, or hands them to Claude in Chrome with a written brief —
compare, report, save a declaration only on the user's go; never send for review, accept
terms, or touch signing, pricing or users.

## 9. After the rollout

- The release pull request is squash-merged like any other (`ship-parallel`). Tag the
  squash commit on `master` — pushing a tag is outward-facing, so ask first — after checking
  it holds what was built (`git diff <built sha> <squash sha> --stat` empty):
  ```bash
  git tag -a <x.y.z+n> <squash sha> -m "<x.y.z+n>" && git push origin <x.y.z+n>
  ```
- The GitHub release for that tag, from the notes already written:
  ```bash
  gh release create <x.y.z+n> --title "<x.y.z+n>" \
    --notes-file store_listing/en-US/release_notes_v<x.y.z>.txt
  ```
  **No attachment — no AAB, no APK.** An APK built here carries the upload key, which is not
  registered for developer verification; attaching one would be a distribution channel
  outside Play. That is a decision for the user, recorded in `Release.md`.
- Update **Versions shipped** in `.llmwiki/Release.md` and its `Updated:` date (a docs pull
  request).
- `scripts/cleanup_local.sh`, then `--apply`: the release worktree and branch go.

## Checklist

- [ ] Built in a release worktree off `origin/master`, `key.properties` linked
- [ ] Version code above every track's; bump and notes committed on `chore/release-<x.y.z>`
- [ ] Release notes fr-FR and en-US, ≤ 500 characters, nothing contradicting Data Safety
- [ ] Policy gate passed, or its failures in `wip/todo/` and cleared by the user
- [ ] `flutter analyze` and `flutter test` clean; integration round on the phone against a
      LAN backend; release APK signed in (password and Google) with a clean logcat
- [ ] `verify_aab.sh` all OK
- [ ] No keystore, `key.properties`, `.env` or service-account key staged
- [ ] `status` read; `publish` without `--commit` validated
- [ ] `--commit` only on the user's explicit go; production at a partial rollout
- [ ] Tag pushed and the GitHub release published (notes only, no asset)
- [ ] `Release.md` Versions shipped updated; worktree removed
- [ ] Keystore and service-account key backups exist
