# Backend Dockerfile for ZapZap
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install production dependencies only
RUN npm ci --only=production

# Copy application source
COPY app.js ./
COPY logger.js ./
COPY src/ ./src/
COPY public/ ./public/
COPY views/ ./views/
COPY scripts/ ./scripts/

# Create data and logs directories
RUN mkdir -p /app/data /app/logs

# Set environment variables
ENV NODE_ENV=production
ENV PORT=9999
ENV DB_PATH=/app/data/zapzap.db
ENV LOG_DIR=/app/logs

# Expose port
EXPOSE 9999

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:9999/api/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Start application with entrypoint script (handles migrations)
CMD ["node", "scripts/docker-entrypoint.js"]
