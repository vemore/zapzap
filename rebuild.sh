#!/bin/bash

# ZapZap Quick Rebuild Script (without git pull)
# Usage: ./rebuild.sh [service]
# Examples:
#   ./rebuild.sh          # Rebuild all services
#   ./rebuild.sh frontend # Rebuild only frontend
#   ./rebuild.sh backend  # Rebuild only backend

set -e

SERVICE=${1:-}

echo "======================================"
echo "🔧 ZapZap Quick Rebuild"
echo "======================================"
echo ""

# Build first, stop second, in both branches: a failed build then leaves whatever is
# running alone instead of leaving it stopped (same reason as deploy.sh).
if [ -z "$SERVICE" ]; then
    echo "🔨 Rebuilding all services..."
    docker-compose build
    docker-compose down --remove-orphans
    docker-compose up -d
else
    echo "🔨 Rebuilding $SERVICE..."
    docker-compose build "$SERVICE"
    docker-compose stop "$SERVICE"
    docker-compose up -d "$SERVICE"
fi

echo ""
echo "⏳ Waiting for services..."
sleep 5

echo ""
echo "📊 Status:"
docker-compose ps

echo ""
echo "✨ Rebuild complete!"
