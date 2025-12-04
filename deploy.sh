#!/bin/bash

# ZapZap Deployment Script
# Usage: ./deploy.sh

set -e  # Exit on error

echo "======================================"
echo "🃏 ZapZap Deployment Script"
echo "======================================"
echo ""

# Pull latest code
echo "📥 Pulling latest code from git..."
git pull
echo "✓ Code updated"
echo ""

# Stop containers
echo "🛑 Stopping containers..."
docker-compose down
echo "✓ Containers stopped"
echo ""

# Build images
echo "🔨 Building Docker images..."
docker-compose build
echo "✓ Images built"
echo ""

# Start containers
echo "🚀 Starting containers..."
docker-compose up -d
echo "✓ Containers started"
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
curl -s http://localhost:80/api/health | jq . || echo "Health check endpoint not responding yet"
echo ""

echo "======================================"
echo "✨ Deployment complete!"
echo "======================================"
echo ""
echo "📝 Useful commands:"
echo "  - View logs:        docker-compose logs -f"
echo "  - Backend logs:     docker-compose logs -f backend"
echo "  - Frontend logs:    docker-compose logs -f frontend"
echo "  - Stop:             docker-compose down"
echo "  - Restart service:  docker-compose restart [service]"
echo ""
