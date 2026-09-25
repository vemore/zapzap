#!/bin/bash

# ZapZap - the Flutter end-to-end test (frontend-flutter/integration_test/) against a
# freshly started Rust backend.
#
# On a throwaway database in a temporary directory: seeds the bot accounts
# (`zapzap-backend seed`, which creates the file and its schema), starts the Rust
# backend with a generated JWT_SECRET, waits for /api/health, starts a chromedriver, then
# runs `flutter drive` on headless Chrome (a phone-sized page). Everything it started is
# stopped on exit, by process id; the database goes with the directory. The CI job
# `flutter-e2e` runs it; the procedure by hand is in .llmwiki/Testing.md.
#
# Needs: the backend built (`cd zapzap-rust && cargo build --locked`), `flutter pub get`
# in frontend-flutter/, Chrome, and a chromedriver of Chrome's major version. No Node.
#
# Usage: scripts/flutter_e2e.sh
#   E2E_BACKEND_BIN   the backend binary (default: the debug build under
#                     $CARGO_TARGET_DIR, else zapzap-rust/target)
#   E2E_API_PORT      the backend's port (default 9921)
#   E2E_DRIVER_PORT   chromedriver's port (default 4461)
#   E2E_BOT_ACTION_DELAY_MS
#                     the bots' pause between two actions (default 0: the backend's own
#                     default, 1000 ms, stretched a round past the test's limit)
#   CHROMEDRIVER      the chromedriver binary (default: $CHROMEWEBDRIVER/chromedriver on a
#                     GitHub runner, else `chromedriver` on the PATH)
# Exits with flutter drive's status: 0 only on `All tests passed.`

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_PORT="${E2E_API_PORT:-9921}"
DRIVER_PORT="${E2E_DRIVER_PORT:-4461}"
BOT_DELAY="${E2E_BOT_ACTION_DELAY_MS:-0}"
BACKEND_BIN="${E2E_BACKEND_BIN:-${CARGO_TARGET_DIR:-$ROOT/zapzap-rust/target}/debug/zapzap-backend}"
if [ -z "${CHROMEDRIVER:-}" ]; then
    if [ -n "${CHROMEWEBDRIVER:-}" ]; then
        CHROMEDRIVER="$CHROMEWEBDRIVER/chromedriver"
    else
        CHROMEDRIVER="$(command -v chromedriver || true)"
    fi
fi

[ -x "$BACKEND_BIN" ] || { echo "no backend binary at $BACKEND_BIN: cd zapzap-rust && cargo build --locked" >&2; exit 2; }
[ -n "$CHROMEDRIVER" ] && [ -x "$CHROMEDRIVER" ] || { echo "no chromedriver: set CHROMEDRIVER" >&2; exit 2; }

WORK="$(mktemp -d)"
DB="$WORK/e2e.db"
BACKEND_LOG="$WORK/backend.log"
DRIVER_LOG="$WORK/chromedriver.log"
pids=()

cleanup() {
    status=$?
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    wait 2>/dev/null || true
    if [ "$status" -ne 0 ]; then
        echo "--- backend log (last 80 lines) ---"
        tail -n 80 "$BACKEND_LOG" 2>/dev/null || true
    fi
    rm -rf "$WORK"
    exit "$status"
}
trap cleanup EXIT

wait_for() {  # label, url, seconds
    local i
    for ((i = 0; i < $3; i++)); do
        curl -fsS -o /dev/null "$2" 2>/dev/null && { echo "$1 is up ($i s)"; return 0; }
        sleep 1
    done
    echo "$1 did not answer $2 within $3 s" >&2
    return 1
}

echo "== seeding the bot accounts on $DB"
DB_PATH="$DB" "$BACKEND_BIN" seed

echo "== starting the Rust backend on :$API_PORT (bots pause $BOT_DELAY ms)"
# Run from zapzap-rust/: its data/ link holds the bot parameters.
(cd "$ROOT/zapzap-rust" && exec env JWT_SECRET="$(openssl rand -hex 32)" DB_PATH="$DB" \
    PORT="$API_PORT" RUST_LOG="${RUST_LOG:-info}" BOT_ACTION_DELAY_MS="$BOT_DELAY" \
    "$BACKEND_BIN") >"$BACKEND_LOG" 2>&1 &
pids+=($!)
wait_for backend "http://localhost:$API_PORT/api/health" 60

echo "== starting chromedriver on :$DRIVER_PORT ($("$CHROMEDRIVER" --version))"
"$CHROMEDRIVER" --port="$DRIVER_PORT" >"$DRIVER_LOG" 2>&1 &
pids+=($!)
wait_for chromedriver "http://localhost:$DRIVER_PORT/status" 30

echo "== flutter drive"
cd "$ROOT/frontend-flutter"
flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/play_round_test.dart \
    -d web-server --browser-name=chrome --headless \
    --driver-port="$DRIVER_PORT" --browser-dimension=390x844 \
    --dart-define=API_BASE_URL="http://localhost:$API_PORT"
