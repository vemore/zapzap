# Rust Backend Dockerfile for ZapZap
# Multi-stage build for smaller final image

# Stage 1: Build
FROM rust:1.83-slim-bookworm AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Cargo files first for dependency caching
COPY Cargo.toml Cargo.lock ./

# Create dummy source to build dependencies
RUN mkdir src && \
    echo "fn main() {}" > src/main.rs && \
    echo "pub fn dummy() {}" > src/lib.rs

# Build dependencies only (cached layer)
RUN cargo build --release && \
    rm -rf src target/release/deps/zapzap*

# Copy actual source code
COPY src ./src

# Build the application
RUN cargo build --release

# Stage 2: Runtime
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 zapzap

# Set working directory
WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/target/release/zapzap-backend /app/zapzap-backend

# Create data directory
RUN mkdir -p /app/data && chown -R zapzap:zapzap /app

# Switch to non-root user
USER zapzap

# Set environment variables
ENV PORT=9999
ENV DATABASE_URL=sqlite:/app/data/zapzap.db
ENV RUST_LOG=info,zapzap_backend=debug

# Expose port
EXPOSE 9999

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:9999/api/health || exit 1

# Run the application
CMD ["/app/zapzap-backend"]
