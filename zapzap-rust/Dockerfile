# Rust Backend Dockerfile for ZapZap
# Multi-stage build for smaller final image

# Stage 1: Build
# Keep in step with rust-toolchain.toml.
FROM rust:1.92-slim-bookworm AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Optional Cargo features, e.g. `--build-arg CARGO_FEATURES=bedrock` for the AWS Bedrock
# LLM bots (the compose file passes CARGO_FEATURES through). Empty builds without.
ARG CARGO_FEATURES=""

# Copy Cargo files first for dependency caching
COPY Cargo.toml Cargo.lock ./

# Create dummy source to build dependencies
RUN mkdir src && \
    echo "fn main() {}" > src/main.rs && \
    echo "pub fn dummy() {}" > src/lib.rs

# Build dependencies only (cached layer). Everything the dummy crate left is removed —
# its objects, its library and its fingerprints — or cargo, seeing a fingerprint newer
# than the copied sources, would link the dummy library into the real binary.
RUN cargo build --release ${CARGO_FEATURES:+--features "$CARGO_FEATURES"} && \
    rm -rf src \
        target/release/deps/zapzap* \
        target/release/deps/libzapzap* \
        target/release/libzapzap* \
        target/release/zapzap-backend* \
        target/release/.fingerprint/zapzap*

# Copy actual source code
COPY src ./src

# Build the application; touching the sources makes them newer than anything cached
RUN touch src/lib.rs src/main.rs && \
    cargo build --release ${CARGO_FEATURES:+--features "$CARGO_FEATURES"}

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
