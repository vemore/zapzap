#!/bin/bash

# ZapZap - smoke test of the Flutter PWA image (frontend-flutter/Dockerfile).
#
# Runs the image on a free local port and checks what the deploy of the PWA promises
# (.llmwiki/Deployment.md): /app/ serves the bundle built with `--base-href /app/`, a deep
# link under /app/ falls back to it instead of 404, /app redirects to /app/, the manifest
# is scoped to /app/, the icons are there, and the entry points are never cached.
#
# It does not need the backend, the proxy or a database: the image is self-contained.
#
# Usage: scripts/pwa_image_smoke.sh [image]     (default: zapzap-frontend-flutter:ci)
#   Build it first: docker build -t zapzap-frontend-flutter:ci frontend-flutter

set -uo pipefail

IMAGE="${1:-zapzap-frontend-flutter:ci}"
NAME="zapzap-pwa-smoke-$$"
fail=0
n=0

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

ok() {  # label
    n=$((n + 1))
    printf 'ok   %s\n' "$1"
}

ko() {  # label, detail
    n=$((n + 1))
    fail=$((fail + 1))
    printf 'FAIL %s\n       %s\n' "$1" "$2"
}

check_status() {  # label, path, expected status
    local got
    got=$(curl -s -o /dev/null -w '%{http_code}' "$BASE$2")
    [ "$got" = "$3" ] && ok "$1" || ko "$1" "expected HTTP $3 for $2, got $got"
}

check_body() {  # label, path, expected substring
    local body
    body=$(curl -fsS "$BASE$2" 2>/dev/null)
    case "$body" in
        *"$3"*) ok "$1" ;;
        *) ko "$1" "$2 does not contain: $3" ;;
    esac
}

check_header() {  # label, path, header name, expected substring
    local got
    got=$(curl -fsS -o /dev/null -D - "$BASE$2" 2>/dev/null | tr -d '\r' \
        | grep -i "^$3:" | head -1)
    case "$got" in
        *"$4"*) ok "$1" ;;
        *) ko "$1" "$2: expected $3 containing '$4', got '${got:-<none>}'" ;;
    esac
}

docker rm -f "$NAME" >/dev/null 2>&1
if ! docker run -d --name "$NAME" -p 127.0.0.1:0:80 "$IMAGE" >/dev/null; then
    echo "pwa_image_smoke: cannot start $IMAGE" >&2
    exit 1
fi

PORT=$(docker port "$NAME" 80/tcp | head -1 | sed 's/.*://')
BASE="http://127.0.0.1:$PORT"
echo "pwa_image_smoke: $IMAGE on $BASE"

for _ in $(seq 1 30); do
    curl -fsS -o /dev/null "$BASE/healthz" 2>/dev/null && break
    sleep 1
done

check_status "health check answers"                 /healthz 200
check_status "/app/ is served"                      /app/ 200
check_status "/app redirects"                       /app 301
check_header "/app redirects to /app/"              /app location /app/
check_body   "the bundle is built for /app/"        /app/ '<base href="/app/">'
check_body   "the manifest is linked"               /app/ 'rel="manifest"'

# The SPA fallback: go_router, not nginx, decides what a path under /app/ shows.
check_status "a deep link does not 404"             /app/parties 200
check_body   "a deep link serves the app"           /app/parties '<base href="/app/">'
check_status "a nested deep link does not 404"      /app/history/42 200
check_status "an unknown asset still 404s"          /app/assets/nope.png 404

check_body   "the manifest starts at /app/"         /app/manifest.json '"start_url": "/app/"'
check_body   "the manifest is scoped to /app/"      /app/manifest.json '"scope": "/app/"'
check_body   "the manifest has a maskable icon"     /app/manifest.json '"purpose": "maskable"'
check_status "the 192 icon is there"                /app/icons/Icon-192.png 200
check_status "the 512 icon is there"                /app/icons/Icon-512.png 200
check_status "the maskable 512 icon is there"       /app/icons/Icon-maskable-512.png 200
check_status "the service worker is there"          /app/flutter_service_worker.js 200
check_status "the bootstrap is there"               /app/flutter_bootstrap.js 200
check_status "the compiled app is there"            /app/main.dart.js 200

check_header "index.html is never stored"           /app/ cache-control no-store
check_header "the service worker is never stored"   /app/flutter_service_worker.js cache-control no-store
check_header "the bootstrap is never stored"        /app/flutter_bootstrap.js cache-control no-store
check_header "main.dart.js is revalidated"          /app/main.dart.js cache-control no-cache

echo "pwa_image_smoke: $((n - fail))/$n checks pass"
[ "$fail" -eq 0 ]
