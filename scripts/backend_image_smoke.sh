#!/bin/bash

# ZapZap - build the production backend service of the root docker-compose.yml (the Rust
# backend, `bedrock` feature) and prove the container starts and passes its own compose
# health check (busybox `wget` against /api/health) on an empty database. Then the facts
# production relies on: the image runs as uid 1000 (the ownership of data/), carries the
# system CA store (rustls-native-certs, the Bedrock client) and stays small (Alpine, a
# static musl binary: under MAX_IMAGE_BYTES).
#
# What differs from production, through an override file and nothing else: a scratch
# data directory instead of ./data, a throwaway JWT_SECRET, a container name of its own,
# and a project name of its own (so nothing named zapzap-backend is touched). No port is
# published: the health check runs inside the container, as in production.
#
# Usage: scripts/backend_image_smoke.sh        (SMOKE_PROJECT sets the compose project)
# The image it builds is kept (<project>-backend); the container and network are removed.
#
# Layer cache (CI): with SMOKE_CACHE_FROM and/or SMOKE_CACHE_TO set, the image is built by
# `docker buildx bake` from the same compose file — same service, context, Dockerfile and
# build args, nothing restated — with those buildx cache specs (e.g. `type=gha,scope=x`
# and `type=gha,scope=x,mode=max`), on the builder SMOKE_BUILDER names (a cache export
# needs a docker-container builder), loaded into the local engine under the name
# `compose build` gives it. Without them: `docker compose build backend`, as before.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${SMOKE_PROJECT:-zapzap-backend-smoke}"
MAX_IMAGE_BYTES=40000000
SCRATCH="$(mktemp -d)"
DATA="$SCRATCH/data"

# The image runs as uid 1000, whatever uid runs this script: the scratch database must be
# writable by it. An empty file is enough — the backend creates its schema itself.
mkdir -p "$DATA"
: > "$DATA/zapzap.db"
chmod 777 "$DATA"
chmod 666 "$DATA/zapzap.db"

cat > "$SCRATCH/override.yml" <<EOF
services:
  backend:
    container_name: ${PROJECT}-backend
    volumes:
      - $DATA:/app/data
EOF

# --env-file /dev/null: a developer's .env at the root (a real JWT_SECRET, AWS keys that
# would switch Bedrock on) must not reach the smoke container.
compose() {
    JWT_SECRET=smoke-test-only-secret \
        docker compose --env-file /dev/null -p "$PROJECT" \
        -f "$ROOT/docker-compose.yml" -f "$SCRATCH/override.yml" "$@"
}

cleanup() {
    compose down --remove-orphans >/dev/null 2>&1 || true
    rm -rf "$SCRATCH" 2>/dev/null || true
}
trap cleanup EXIT

if [ -n "${SMOKE_CACHE_FROM:-}${SMOKE_CACHE_TO:-}" ]; then
    # bake reads the compose file itself and interpolates all of it: JWT_SECRET is set for
    # the environment block, which the build does not use.
    bake_args=(--load --set "backend.tags=${PROJECT}-backend")
    [ -z "${SMOKE_BUILDER:-}" ] || bake_args+=(--builder "$SMOKE_BUILDER")
    [ -z "${SMOKE_CACHE_FROM:-}" ] || bake_args+=(--set "backend.cache-from=$SMOKE_CACHE_FROM")
    [ -z "${SMOKE_CACHE_TO:-}" ] || bake_args+=(--set "backend.cache-to=$SMOKE_CACHE_TO")
    # From the root: the compose file's build contexts are relative to it.
    (cd "$ROOT" && JWT_SECRET=smoke-test-only-secret \
        docker buildx bake -f docker-compose.yml "${bake_args[@]}" backend)
else
    compose build backend
fi
# --no-build: the image is the one just built, never a rebuild by compose.
compose up -d --no-deps --no-build backend
cid=$(compose ps -q backend)

# The compose health check: interval 30 s, start_period 10 s — the first verdict comes
# after about 30 s.
state=starting
for _ in $(seq 1 60); do
    state=$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo gone)
    case "$state" in healthy|unhealthy|gone) break ;; esac
    sleep 2
done

if [ "$state" != healthy ]; then
    echo "✗ the backend container is $state, not healthy" >&2
    docker inspect -f '{{json .State.Health}}' "$cid" >&2 2>/dev/null || true
    compose logs --tail 50 backend >&2 || true
    exit 1
fi

user=$(docker exec "$cid" id -u)
body=$(docker exec "$cid" wget -qO- http://127.0.0.1:9999/api/health)
echo "✓ backend container healthy (uid $user): $body"
[ "$user" = 1000 ] || { echo "✗ expected the image to run as uid 1000, got $user" >&2; exit 1; }

image=$(docker inspect -f '{{.Image}}' "$cid")

# The image's own user, not the container's: production starts it without --user.
image_user=$(docker run --rm --entrypoint id "$image" -u)
[ "$image_user" = 1000 ] || { echo "✗ the image's user is uid $image_user, not 1000" >&2; exit 1; }

# The system store rustls-native-certs reads (it follows openssl-probe's paths).
if ! docker run --rm --entrypoint test "$image" -s /etc/ssl/certs/ca-certificates.crt; then
    echo "✗ the image has no system CA store (/etc/ssl/certs/ca-certificates.crt)" >&2
    exit 1
fi
echo "✓ image user uid $image_user, system CA store present"

size=$(docker image inspect -f '{{.Size}}' "$image")
echo "✓ image size: $((size / 1000000)) MB ($size bytes)"
if [ "$size" -ge "$MAX_IMAGE_BYTES" ]; then
    echo "✗ the image is $size bytes, the limit is $MAX_IMAGE_BYTES" >&2
    exit 1
fi
