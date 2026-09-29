#!/bin/bash

# ZapZap - routing test of the proxy image (nginx/Dockerfile, nginx/nginx.conf).
#
# Runs the real configuration, baked into the image, between two stubs on a Docker network
# of its own: `backend` (port 9999) and `frontend-flutter` (port 80), each an nginx that
# answers "stub-<name> <request URI>". It then checks, request by request:
#   - every URL of the removed React client answers a relative 301 to its page in the PWA
#     (`/` a 302), query string kept (.llmwiki/Deployment.md, "The URLs of the removed React
#     client");
#   - /api/ and /suscribeupdate still reach the backend, /app/ the PWA, and /privacy,
#     /privacy.html and /nginx-health are still served by the proxy itself.
#
# Usage: scripts/proxy_redirects_smoke.sh [image]     (default: zapzap-proxy:ci)
#   Build it first: docker build -t zapzap-proxy:ci nginx
# The stubs run the same image with their own conf, so nothing else is pulled.

set -uo pipefail

IMAGE="${1:-zapzap-proxy:ci}"
TAG="zapzap-proxy-smoke-$$"
NET="$TAG-net"
fail=0
n=0

cleanup() {
    docker rm -f "$TAG" "$TAG-backend" "$TAG-pwa" >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ok() { n=$((n + 1)); printf 'ok   %s\n' "$1"; }
ko() { n=$((n + 1)); fail=$((fail + 1)); printf 'FAIL %s\n       %s\n' "$1" "$2"; }

# One request, never following a redirect: "<status> <Location or ->" on the first line,
# the body after it.
fetch() {  # path
    local headers body code location
    headers=$(mktemp) body=$(mktemp)
    code=$(curl -s --max-time 5 -o "$body" -D "$headers" -w '%{http_code}' "$BASE$1")
    location=$(tr -d '\r' < "$headers" | sed -n 's/^[Ll]ocation: //p' | head -1)
    printf '%s %s\n' "$code" "${location:--}"
    cat "$body"
    rm -f "$headers" "$body"
}

# A redirect to exactly this Location, permanent unless a status is given: relative, so the
# browser keeps the scheme and port it used (the outer proxy's), never http://<host>:80.
check_redirect() {  # path, expected Location, [status, default 301]
    local got status="${3:-301}"
    got=$(fetch "$1" | head -1)
    [ "$got" = "$status $2" ] && ok "$1 → $status $2" || ko "$1 → $status $2" "got: $got"
}

# Served, not redirected: the status, and a substring of the body saying who answered.
check_served() {  # path, expected status, expected body substring
    local out
    out=$(fetch "$1")
    case "$(printf '%s\n' "$out" | head -1)" in
        "$2 -") ;;
        *) ko "$1 → $2 ($3)" "got: $(printf '%s\n' "$out" | head -1)"; return ;;
    esac
    case "$(printf '%s\n' "$out" | tail -n +2)" in
        *"$3"*) ok "$1 → $2 ($3)" ;;
        *) ko "$1 → $2 ($3)" "body: $(printf '%s\n' "$out" | tail -n +2 | head -3)" ;;
    esac
}

# An nginx of the proxy image answering every request with its name and the request URI.
stub() {  # container, network alias, port
    local conf="server { listen $3; location / { default_type text/plain; return 200 \"stub-$2 \$request_uri\"; } }"
    docker run -d --name "$1" --network "$NET" --network-alias "$2" -e STUB_CONF="$conf" \
        --entrypoint sh "$IMAGE" -c \
        'printf "%s\n" "$STUB_CONF" > /etc/nginx/conf.d/default.conf && exec nginx -g "daemon off;"' >/dev/null
}

cleanup
docker network create "$NET" >/dev/null || { echo "proxy_redirects_smoke: cannot create $NET" >&2; exit 1; }
# The backend stub first: nginx resolves its `upstream backend` when it loads the conf.
stub "$TAG-backend" backend 9999 && stub "$TAG-pwa" frontend-flutter 80 \
    || { echo "proxy_redirects_smoke: cannot start the stubs from $IMAGE" >&2; exit 1; }
if ! docker run -d --name "$TAG" --network "$NET" -p 127.0.0.1:0:80 "$IMAGE" >/dev/null; then
    echo "proxy_redirects_smoke: cannot start $IMAGE" >&2
    exit 1
fi

PORT=$(docker port "$TAG" 80/tcp | head -1 | sed 's/.*://')
BASE="http://127.0.0.1:$PORT"
echo "proxy_redirects_smoke: $IMAGE on $BASE"
for _ in $(seq 1 30); do
    curl -fsS -o /dev/null "$BASE/nginx-health" 2>/dev/null && break
    sleep 1
done
for _ in $(seq 1 30); do
    curl -fsS -o /dev/null "$BASE/api/health" 2>/dev/null && curl -fsS -o /dev/null "$BASE/app/" 2>/dev/null && break
    sleep 1
done

echo "== the React client's URLs, redirected to the PWA =============="
# The root is a temporary redirect: it stays free for a later landing page.
check_redirect /                               /app/                   302
check_redirect '/?ref=play'                    '/app/?ref=play'        302
# The routes the PWA names differently (frontend-flutter/lib/router.dart, AppRoutes).
check_redirect /party/abc                      /app/parties/abc
check_redirect '/party/abc?x=1'                '/app/parties/abc?x=1'
check_redirect /party/0b6f5c1e-9a2d-4c1b-8e3f-2a7d9c4e1f00/ /app/parties/0b6f5c1e-9a2d-4c1b-8e3f-2a7d9c4e1f00
check_redirect /create-party                   /app/parties/new
check_redirect '/create-party?x=1'             '/app/parties/new?x=1'
check_redirect /create-party/                  /app/parties/new
check_redirect '/create-party/?x=1'            '/app/parties/new?x=1'
check_redirect /account/delete                 /app/account
check_redirect '/account/delete?from=play'     '/app/account?from=play'
check_redirect /account/delete/                /app/account
check_redirect '/account/delete/?from=play'    '/app/account?from=play'
# Every other React route is the PWA's own, under /app.
for p in /login /register /parties /game/abc /history /history/abc /stats /admin \
         /admin/users /admin/parties /admin/statistics; do
    check_redirect "$p"                        "/app$p"
done
check_redirect '/login?from=%2Fparties'        '/app/login?from=%2Fparties'
check_redirect '/game/abc?x=1&y=2'             '/app/game/abc?x=1&y=2'
# A /party/ path that is not an id falls back to the prefix rule, raw: still a path here.
check_redirect '/party/a%20b'                  '/app/party/a%20b'
# Never an open redirect: `//host` after /app is a path on this host, not another host.
check_redirect //evil.example/x                /app//evil.example/x
# Unchanged: /app still redirects to /app/.
check_redirect /app                            /app/
check_redirect '/app?x=1'                      '/app/?x=1'

echo "== what is not redirected ======================================"
check_served /api/health                       200 'stub-backend /api/health'
check_served '/api/parties?x=1'                200 'stub-backend /api/parties?x=1'
check_served '/suscribeupdate?token=t'         200 'stub-backend /suscribeupdate?token=t'
check_served /app/                             200 'stub-frontend-flutter /app/'
check_served '/app/parties/abc?x=1'            200 'stub-frontend-flutter /app/parties/abc?x=1'
check_served /privacy                          200 'Confidentialité / Privacy'
check_served /privacy.html                     200 'Confidentialité / Privacy'
check_served /nginx-health                     200 'healthy'

echo
echo "$((n - fail)) passed, $fail failed"
[ "$fail" -eq 0 ]
