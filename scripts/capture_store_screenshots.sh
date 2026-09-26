#!/bin/bash

# ZapZap - the Play Store phone screenshots, captured headless from the Flutter web build.
#
# For each store locale: a throwaway database seeded with the bots and the demo users
# (`zapzap-backend seed --demo`), the Rust backend on it, the Flutter web build served
# under /app/, and scripts/capture_store_screenshots.js, which plays a few games through
# the API (to fill the history and the statistics, and to reach a board in play and a round
# end) and screenshots the app in a phone viewport with the browser in that locale's
# language. The raw captures (1170x2532) are then composed with their captions by
# scripts/compose_store_screenshots.py into store_listing/<locale>/screenshots/phone/.
#
# Never production: the script registers nothing there, and it refuses an API port that
# something already answers on. Everything it started is stopped on exit, by process id.
#
# Needs: the backend built (`cd zapzap-rust && cargo build --locked`), `flutter` on the
# PATH, Node, Playwright (the root package.json's, or the main checkout's node_modules)
# with its Chromium, uv (the composer), and for the ja, hi and ar captions the Noto fonts
# (`fonts-noto-cjk`, `fonts-noto-core`).
#
# Usage: scripts/capture_store_screenshots.sh [locale...]   (default: every store locale,
#        the store_listing/*/ directories holding a title.txt)
#   STORE_BACKEND_BIN  the backend binary (default: the debug build under
#                      $CARGO_TARGET_DIR, else zapzap-rust/target)
#   STORE_API_PORT     the backend's port (default 9971)
#   STORE_WEB_PORT     the web build's port (default 8871)
#   STORE_WEB_BUILD    an existing `flutter build web --base-href /app/` output built with
#                      --dart-define=API_BASE_URL=http://localhost:$STORE_API_PORT; the
#                      script builds one when unset
#   STORE_RAW_DIR      where the raw captures go (default: a temporary directory)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_PORT="${STORE_API_PORT:-9971}"
WEB_PORT="${STORE_WEB_PORT:-8871}"
BACKEND_BIN="${STORE_BACKEND_BIN:-${CARGO_TARGET_DIR:-$ROOT/zapzap-rust/target}/debug/zapzap-backend}"
LOCALES=("$@")
if [ ${#LOCALES[@]} -eq 0 ]; then
    for dir in "$ROOT"/store_listing/*/; do
        if [ -f "$dir/title.txt" ]; then LOCALES+=("$(basename "$dir")"); fi
    done
fi

die() { echo "error: $*" >&2; exit 2; }

[ -x "$BACKEND_BIN" ] || die "no backend binary at $BACKEND_BIN: cd zapzap-rust && cargo build --locked"
for locale in "${LOCALES[@]}"; do
    [ -f "$ROOT/store_listing/$locale/title.txt" ] || die "$locale is not a store locale (store_listing/$locale/title.txt)"
done
command -v node > /dev/null || die "node not found"
command -v uv > /dev/null || die "uv not found (the composer runs with uv run --script)"
if curl -fsS --max-time 2 -o /dev/null "http://localhost:$API_PORT/api/health" 2>/dev/null; then
    die "something already answers on :$API_PORT; pick another STORE_API_PORT"
fi

# Playwright: this checkout's, else the main checkout's (a worktree has no node_modules).
PLAYWRIGHT_DIR=""
for candidate in "$ROOT/node_modules/playwright" \
    "$(cd "$ROOT" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/../node_modules/playwright"; do
    if [ -f "$candidate/package.json" ]; then
        PLAYWRIGHT_DIR="$(cd "$candidate" && pwd)"
        break
    fi
done
[ -n "$PLAYWRIGHT_DIR" ] || die "no Playwright: npm ci at the repository root"

WORK="$(mktemp -d)"
RAW="${STORE_RAW_DIR:-$WORK/raw}"
pids=()
backend_pid=""

cleanup() {
    status=$?
    [ -z "$backend_pid" ] || kill "$backend_pid" 2>/dev/null || true
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    wait 2>/dev/null || true
    if [ "$status" -ne 0 ] && [ -f "$WORK/backend.log" ]; then
        echo "--- backend log (last 40 lines) ---"
        tail -n 40 "$WORK/backend.log" || true
    fi
    rm -rf "$WORK"
    exit "$status"
}
trap cleanup EXIT

wait_for() {  # label, url, seconds
    local i
    for ((i = 0; i < $3; i++)); do
        curl -fsS --max-time 2 -o /dev/null "$2" 2>/dev/null && return 0
        sleep 1
    done
    echo "$1 did not answer $2 within $3 s" >&2
    return 1
}

WEB="${STORE_WEB_BUILD:-}"
if [ -z "$WEB" ]; then
    WEB="$WORK/web"
    echo "== flutter build web (API_BASE_URL=http://localhost:$API_PORT)"
    (cd "$ROOT/frontend-flutter" && flutter build web --release --base-href /app/ \
        --no-web-resources-cdn --dart-define=API_BASE_URL="http://localhost:$API_PORT" \
        --output "$WEB") > "$WORK/flutter-build.log" 2>&1 ||
        { tail -n 40 "$WORK/flutter-build.log"; die "flutter build web failed"; }
fi
[ -f "$WEB/index.html" ] || die "no index.html in $WEB"

for locale in "${LOCALES[@]}"; do
    db="$WORK/$locale.db"
    echo "== $locale: seeding $db"
    DB_PATH="$db" "$BACKEND_BIN" seed --demo > /dev/null

    echo "== $locale: the Rust backend on :$API_PORT"
    # From zapzap-rust/: its data/ link holds the bot parameters. No pause between the
    # bots' actions: the script plays whole games through the API.
    (cd "$ROOT/zapzap-rust" && exec env JWT_SECRET="$(openssl rand -hex 32)" DB_PATH="$db" \
        PORT="$API_PORT" RUST_LOG=warn BOT_ACTION_DELAY_MS=0 "$BACKEND_BIN") \
        > "$WORK/backend.log" 2>&1 &
    backend_pid=$!
    wait_for backend "http://localhost:$API_PORT/api/health" 60

    mkdir -p "$RAW/$locale"
    NODE_PATH="$(dirname "$PLAYWRIGHT_DIR")" node "$ROOT/scripts/capture_store_screenshots.js" \
        --locale "$locale" --api "http://localhost:$API_PORT" --web-port "$WEB_PORT" \
        --web-dir "$WEB" --out "$RAW/$locale"

    kill "$backend_pid" 2>/dev/null || true
    wait "$backend_pid" 2>/dev/null || true
    backend_pid=""
done

echo "== composing"
args=()
for locale in "${LOCALES[@]}"; do args+=(--locale "$locale"); done
uv run --script "$ROOT/scripts/compose_store_screenshots.py" --raw "$RAW" "${args[@]}"
