#!/bin/bash

# ZapZap Deployment Script
# Usage: ./deploy.sh
#
# Order matters: pull, *build*, then down/up. The build runs against the new compose
# file while the old containers keep serving, so a build that fails — a network
# timeout on a dependency, ENOSPC, the OOM killer taking dart2js — is a no-op and
# needs no rollback. Downtime is the down/up window only, a few seconds.
# Procedure and why: .claude/skills/deploy/SKILL.md, .llmwiki/Deployment.md

set -e  # Exit on error

echo "======================================"
echo "🃏 ZapZap Deployment Script"
echo "======================================"
echo ""

# The production database must not be tracked: master stopped tracking it (#21), so a
# pull against a clone that still does either stops or — if the file were unmodified —
# deletes every account. Refuse before touching anything.
echo "🔐 Checking the production database is not tracked by git..."
if [ -n "$(git ls-files data/zapzap.db)" ]; then
    cat >&2 <<'EOF'
✗ REFUSING TO DEPLOY: data/zapzap.db is tracked by git in this clone.

  A `git pull` would stop on it, or — were the file unmodified — delete the
  production database. Untrack it once, after a backup, and nothing else first:

      cp -p data/zapzap.db data/zapzap.db.bak-$(date +%F-%H%M)
      git rm --cached data/zapzap.db
      ls -la data/zapzap.db          # `git rm --cached` keeps the file on disk

  Then run ./deploy.sh again. See .claude/skills/deploy/SKILL.md §0.
EOF
    exit 1
fi
echo "✓ Not tracked"
echo ""

# Pull latest code — before the build, so the build is of what we are deploying.
echo "📥 Pulling latest code from git..."
if ! git pull --ff-only; then
    echo "" >&2
    echo "✗ REFUSING TO DEPLOY: the pull did not fast-forward." >&2
    echo "  Nothing was stopped; production is untouched and still serving." >&2
    echo "  Usual causes: local commits or local modifications in this clone" >&2
    echo "  (\`git status --short\`), or a detached HEAD after a rollback" >&2
    echo "  (\`git checkout master\`). Fix it by hand, then run ./deploy.sh again." >&2
    exit 1
fi
echo "✓ Code updated"
echo ""

# Build images — the old containers are still up and still serving while this runs.
echo "🔨 Building Docker images (production is still serving the old ones)..."
if ! docker-compose build; then
    echo "" >&2
    echo "✗ BUILD FAILED — and nothing was stopped." >&2
    echo "  Production is still serving the previous images: this deploy was a" >&2
    echo "  no-op, no rollback is needed. Fix the cause (disk, RAM, network — see" >&2
    echo "  the preflight in .claude/skills/deploy/SKILL.md §1) and run ./deploy.sh" >&2
    echo "  again." >&2
    exit 1
fi
echo "✓ Images built"
echo ""

# Everything is built: the downtime starts here and ends at `up -d`.
#
# --remove-orphans: a compose file that no longer declares a service — a rollback to
# any commit before the Flutter PWA — otherwise leaves the container running, and the
# `down` then fails to remove the network ("Resource is still in use"); docker-compose
# v1, which the NAS runs, only warns about it.
echo "🛑 Stopping containers (downtime starts now)..."
downtime_start=$SECONDS
docker-compose down --remove-orphans
echo "✓ Containers stopped"
echo ""

# Start containers
echo "🚀 Starting containers..."
if ! docker-compose up -d; then
    echo "" >&2
    echo "✗ START FAILED — production is DOWN. Act now:" >&2
    echo "  - \`docker ps -a\`: if zapzap-proxy sits in Created, \`docker start" >&2
    echo "    zapzap-proxy\` restores / and /api/ at once." >&2
    echo "  - Otherwise roll back: .claude/skills/deploy/SKILL.md §4." >&2
    exit 1
fi
echo "✓ Containers started — downtime was $((SECONDS - downtime_start))s"
echo ""

# Wait for health checks
echo "⏳ Waiting for services to be healthy..."
sleep 15

# Check status
echo "📊 Container status:"
docker-compose ps
echo ""

# Health check
echo "🩺 API Health check:"
curl -s -m 10 http://localhost:80/api/health | jq . || echo "Health check endpoint not responding yet"
echo ""

echo "======================================"
echo "✨ Deployment complete!"
echo "======================================"
echo ""
echo "📝 Useful commands:"
echo "  - View logs:        docker-compose logs -f"
echo "  - Backend logs:     docker-compose logs -f backend"
echo "  - Frontend logs:    docker-compose logs -f frontend"
echo "  - Stop:             docker-compose down --remove-orphans"
echo "  - Restart service:  docker-compose restart [service]"
echo ""
