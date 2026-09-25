#!/usr/bin/env bash
# ZapZap - verify a signed App Bundle before it goes anywhere near the Play Console.
#
#   scripts/verify_aab.sh [path/to/app-release.aab]
#
# Run from the checkout that built the bundle (the release-android skill). Read-only: it
# never prints a password and never modifies the bundle. Exits non-zero on the first failed
# check. VERIFY_AAB_ROOT overrides the repository root (scripts/test_verify_aab.py).
# Needs jarsigner and keytool (a JDK), unzip and readelf. Ported from countscore.

set -euo pipefail

ROOT="${VERIFY_AAB_ROOT:-$(git rev-parse --show-toplevel)}"
APP="$ROOT/frontend-flutter"
AAB="${1:-$APP/build/app/outputs/bundle/release/app-release.aab}"
PROPS="$APP/android/key.properties"
PUBSPEC="$APP/pubspec.yaml"
MANIFEST="$APP/build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml"
MIN_TARGET_SDK=36

ok()   { printf 'OK    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }

prop() { sed -n "s/^$1=//p" "$PROPS" | tail -n1 | tr -d '\r'; }

# --- artifact ----------------------------------------------------------------
[[ -f "$AAB" ]] || fail "no bundle at $AAB"
ok "bundle $(du -h "$AAB" | cut -f1)  $AAB"

# --- signature ---------------------------------------------------------------
jarsigner -verify "$AAB" >/dev/null 2>&1 || fail "jarsigner -verify rejects the bundle"
certs="$(keytool -printcert -jarfile "$AAB" 2>/dev/null)" || fail "cannot read the signing certificate"
owner="$(sed -n 's/^Owner: //p' <<<"$certs" | head -n1)"
[[ -n "$owner" ]] || fail "the bundle is not signed"
[[ "$owner" != *"Android Debug"* ]] || fail "signed with the DEBUG key ($owner) — frontend-flutter/android/key.properties was not picked up"
aab_sha="$(sed -n 's/^[[:space:]]*SHA256: //p' <<<"$certs" | head -n1)"
[[ -n "$aab_sha" ]] || fail "no SHA-256 fingerprint in the bundle certificate"

[[ -f "$PROPS" ]] || fail "frontend-flutter/android/key.properties missing — cannot compare against the upload key"
store="$(prop storeFile)"; alias="$(prop keyAlias)"
[[ "$store" = /* ]] || store="$APP/android/$store"
[[ -f "$store" ]] || fail "keystore named by key.properties does not exist: $store"
upload_sha="$(keytool -list -v -keystore "$store" -alias "$alias" \
    -storepass:file <(prop storePassword) 2>/dev/null \
  | sed -n 's/^[[:space:]]*SHA256: //p' | head -n1)"
[[ -n "$upload_sha" ]] || fail "cannot read alias '$alias' from the upload keystore"
[[ "$aab_sha" == "$upload_sha" ]] || fail "bundle certificate $aab_sha is not the upload key $upload_sha"
ok "signed with the upload key ($owner)"

# --- manifest ----------------------------------------------------------------
# The bundle's own manifest is protobuf; the permission name is still a plain string in it.
# No `grep -q`: exiting early would SIGPIPE unzip and pipefail would report a false failure.
unzip -p "$AAB" base/manifest/AndroidManifest.xml | grep -a 'android.permission.INTERNET' >/dev/null \
  || fail "the bundle manifest does not declare INTERNET — the app could not reach the API"
ok "bundle declares android.permission.INTERNET"

# versionCode and targetSdk are varints in that protobuf, so read them from the merged manifest
# the same build wrote — and refuse it if it is older than the bundle's inputs.
[[ -f "$MANIFEST" ]] || fail "merged release manifest not found at $MANIFEST"
[[ "$MANIFEST" -nt "$PUBSPEC" && ! "$MANIFEST" -nt "$AAB" ]] \
  || fail "merged manifest is stale relative to pubspec.yaml or the bundle — rebuild"
code="$(grep -o 'android:versionCode="[0-9]*"' "$MANIFEST" | grep -o '[0-9]\+' || true)"
target="$(grep -o 'android:targetSdkVersion="[0-9]*"' "$MANIFEST" | grep -o '[0-9]\+' || true)"
pub_code="$(sed -n 's/^version: *[^+]*+\([0-9]*\).*/\1/p' "$PUBSPEC")"
[[ -n "$code" && -n "$target" ]] || fail "no versionCode or targetSdkVersion in $MANIFEST"
[[ "$code" == "$pub_code" ]] || fail "versionCode $code does not match pubspec.yaml build number $pub_code"
ok "versionCode $code (pubspec.yaml $(sed -n 's/^version: *//p' "$PUBSPEC"))"
(( target >= MIN_TARGET_SDK )) || fail "targetSdk $target < $MIN_TARGET_SDK — Play refuses updates since 2026-08-31"
ok "targetSdk $target"

# --- 16 KB page size ---------------------------------------------------------
# Play requires every 64-bit native library to be loadable on 16 KB-page devices: each LOAD
# segment must be aligned to at least 2**14. 32-bit libraries are exempt.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
unzip -q "$AAB" 'base/lib/arm64-v8a/*' 'base/lib/x86_64/*' -d "$tmp" 2>/dev/null || true
count=0
while IFS= read -r -d '' so; do
  count=$((count + 1))
  while read -r align; do
    (( align >= 16384 )) || fail "$(basename "$(dirname "$so")")/$(basename "$so") has a LOAD segment aligned to $align (< 16384)"
  done < <(readelf -lW "$so" | awk '$1 == "LOAD" { print $NF }')
done < <(find "$tmp" -name '*.so' -print0)
(( count > 0 )) || fail "no 64-bit native libraries found — unexpected for a Flutter bundle"
ok "16 KB page size: $count 64-bit libraries, every LOAD segment aligned >= 16384"

echo "All checks passed."
