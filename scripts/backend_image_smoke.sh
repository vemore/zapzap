#!/bin/bash

# ZapZap - build the production backend service of the root docker-compose.yml (the Rust
# backend, `bedrock` feature) and prove the container starts and passes its own compose
# health check (`curl` against /api/health) on an empty database.
#
# What differs from production, through an override file and nothing else: a scratch
# data directory instead of ./data, a throwaway JWT_SECRET, a container name of its own,
# and a project name of its own (so nothing named zapzap-backend is touched). No port is
# published: the health check runs inside the container, as in production.
#
# Usage: scripts/backend_image_smoke.sh        (SMOKE_PROJECT sets the compose project)
# The image it builds is kept (<project>-backend); the container and network are removed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${SMOKE_PROJECT:-zapzap-backend-smoke}"
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

compose build backend
compose up -d --no-deps backend
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
body=$(docker exec "$cid" curl -fsS http://localhost:9999/api/health)
echo "✓ backend container healthy (uid $user): $body"
[ "$user" = 1000 ] || { echo "✗ expected the image to run as uid 1000, got $user" >&2; exit 1; }
