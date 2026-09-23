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

# The exact value, and only one of it: `add_header` next to an `expires` silently emits two
# Cache-Control headers, and a substring match would accept both.
check_cache_control() {  # label, path, expected full value
    local got
    got=$(curl -fsS -o /dev/null -D - "$BASE$2" 2>/dev/null | tr -d '\r' \
        | sed -n 's/^[Cc]ache-[Cc]ontrol: //p' | paste -sd'|' -)
    [ "$got" = "$3" ] && ok "$1" \
        || ko "$1" "$2: expected Cache-Control '$3', got '${got:-<none>}'"
}

# A 200 is not enough: the SPA fallback answers 200 text/html for a path it does not have,
# so a deleted asset would pass a status-only check.
check_type() {  # label, path, expected content type prefix
    local code type
    code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE$2")
    type=$(curl -s -o /dev/null -w '%{content_type}' "$BASE$2")
    if [ "$code" = 200 ] && [ "${type#"$3"}" != "$type" ]; then
        ok "$1"
    else
        ko "$1" "$2: expected 200 and content type $3*, got $code $type"
    fi
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
check_header "the redirect keeps the query"         '/app?from=email' location '/app/?from=email'
check_body   "the bundle is built for /app/"        /app/ '<base href="/app/">'
check_body   "the manifest is linked"               /app/ 'rel="manifest"'

# The SPA fallback: go_router, not nginx, decides what a path under /app/ shows.
check_status "a deep link does not 404"             /app/parties 200
check_body   "a deep link serves the app"           /app/parties '<base href="/app/">'
check_status "a nested deep link does not 404"      /app/history/42 200

# The fallback must not swallow a missing file: a path with an extension, and anything under
# assets/, canvaskit/ or icons/, is a file. Without this, deleting a manifest icon or
# main.dart.js would leave every check green and only break Chrome's install prompt.
check_status "an unknown asset 404s"                /app/assets/nope.png 404
check_status "an unknown engine file 404s"          /app/canvaskit/nope.wasm 404
check_status "an unknown icon 404s"                 /app/icons/nope.png 404
check_status "an unknown script 404s"               /app/nope.js 404
check_status "an unknown page 404s"                 /app/nope.html 404

check_body   "the manifest starts at /app/"         /app/manifest.json '"start_url": "/app/"'
check_body   "the manifest is scoped to /app/"      /app/manifest.json '"scope": "/app/"'
check_body   "the manifest has a maskable icon"     /app/manifest.json '"purpose": "maskable"'
check_type   "the manifest is JSON"                 /app/manifest.json application/json
check_type   "the 192 icon is a PNG"                /app/icons/Icon-192.png image/png
check_type   "the 512 icon is a PNG"                /app/icons/Icon-512.png image/png
check_type   "the maskable 192 icon is a PNG"       /app/icons/Icon-maskable-192.png image/png
check_type   "the maskable 512 icon is a PNG"       /app/icons/Icon-maskable-512.png image/png
check_type   "the favicon is a PNG"                 /app/favicon.png image/png
check_type   "the service worker is a script"       /app/flutter_service_worker.js application/javascript
check_type   "the bootstrap is a script"            /app/flutter_bootstrap.js application/javascript
check_type   "the compiled app is a script"         /app/main.dart.js application/javascript

# CanvasKit is served from the bundle, not from www.gstatic.com: the build passes
# --no-web-resources-cdn, so a client that cannot reach Google still runs the app. The
# files being present is not enough — the loader has to be told to use them.
check_type   "the engine is served locally"         /app/canvaskit/canvaskit.js application/javascript
check_type   "the engine wasm is served locally"    /app/canvaskit/canvaskit.wasm application/wasm
check_body   "the loader uses the local engine"     /app/flutter_bootstrap.js '"useLocalCanvasKit":true'

check_cache_control "index.html is never stored"         /app/ 'no-cache, no-store, must-revalidate'
check_cache_control "the service worker is never stored" /app/flutter_service_worker.js 'no-cache, no-store, must-revalidate'
check_cache_control "the bootstrap is never stored"      /app/flutter_bootstrap.js 'no-cache, no-store, must-revalidate'
check_cache_control "main.dart.js is revalidated"        /app/main.dart.js 'no-cache'
check_cache_control "an icon is revalidated"             /app/icons/Icon-192.png 'no-cache'

echo "pwa_image_smoke: $((n - fail))/$n checks pass"
[ "$fail" -eq 0 ]
