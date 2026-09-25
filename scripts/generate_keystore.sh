#!/usr/bin/env bash
# ZapZap - generate the Android upload keystore (alias zapzap-upload, JKS, RSA 2048).
#
# Run it once. The keystore goes to $HOME, never to the repository, and an existing one is
# never overwritten: a new upload key means asking Play for an upload-key reset.
#
# Usage: scripts/generate_keystore.sh
#        ZAPZAP_KEYSTORE=<path> overrides the location; a path inside a git work tree is
#        refused, so the keystore cannot land next to the code.
#
# Then: copy frontend-flutter/android/key.properties.template to
# frontend-flutter/android/key.properties, fill it in, back up the keystore and the
# passwords, and register its SHA-1 (.llmwiki/FrontendFlutter.md, Android).

set -euo pipefail

KEY_ALIAS=zapzap-upload
KEYSTORE=${ZAPZAP_KEYSTORE:-$HOME/zapzap-upload-keystore.jks}
VALIDITY_DAYS=10000 # ~27 years; Play asks for a validity past 2033

die() {
    printf 'generate_keystore: %s\n' "$1" >&2
    exit 1
}

case $KEYSTORE in
    /*) ;;
    *) die "ZAPZAP_KEYSTORE must be an absolute path: $KEYSTORE" ;;
esac

if [ -e "$KEYSTORE" ]; then
    die "a keystore already exists at $KEYSTORE; it is not overwritten.
A new upload key means an upload-key reset in the Play Console. To make one anyway, back
the existing one up, move it away, and run this again."
fi

dir=$(dirname "$KEYSTORE")
[ -d "$dir" ] || die "no such directory: $dir"
if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "$dir is inside a git work tree ($(git -C "$dir" rev-parse --show-toplevel)).
The keystore never goes into a repository: use the default, \$HOME/zapzap-upload-keystore.jks."
fi

command -v keytool >/dev/null 2>&1 || die "keytool not found: install a JDK (17)."

echo "Creating the upload keystore $KEYSTORE (alias $KEY_ALIAS)."
echo "keytool asks for the store password, then the name and organisation."
echo "Keep the password in a password manager: without it the keystore is useless."
echo

# JKS, as Flutter's deployment guide does; keytool's default would be PKCS12.
keytool -genkeypair -v \
    -keystore "$KEYSTORE" \
    -storetype JKS \
    -keyalg RSA \
    -keysize 2048 \
    -validity "$VALIDITY_DAYS" \
    -alias "$KEY_ALIAS"
chmod 600 "$KEYSTORE"

echo
echo "Created $KEYSTORE (mode 600)."
echo
echo "Next:"
echo "  1. Back up the keystore and its password (password manager + an offline copy)."
echo "  2. cp frontend-flutter/android/key.properties.template frontend-flutter/android/key.properties"
echo "     and fill in storeFile=$KEYSTORE and the passwords."
echo "  3. Register its SHA-1 as an Android OAuth client (package com.zapzap.app) in"
echo "     the Google Cloud project zapzap-481109:"
echo "       keytool -list -v -keystore $KEYSTORE -alias $KEY_ALIAS | grep SHA1"
