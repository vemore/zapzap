# Rust Backend Dockerfile for ZapZap
# Multi-stage build: a static musl binary, served from a bare Alpine image.

# Stage 1: Build
# Keep in step with rust-toolchain.toml. The Alpine image targets x86_64-unknown-linux-musl,
# which links statically by default: the binary needs no libc, no OpenSSL at run time.
FROM rust:1.92-alpine AS builder

# Crates that compile C: libsqlite3-sys (bundled SQLite) and ring need a C toolchain and the
# musl headers; aws-lc-sys (rustls' crypto under the `bedrock` feature) also needs cmake,
# perl, make, clang and the kernel headers.
RUN apk add --no-cache musl-dev cmake perl make clang linux-headers

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

# Build the application; touching the sources makes them newer than anything cached.
# The binary is stripped (no debug symbols in the image) and must come out static: no
# NEEDED entry, or the Alpine runtime would lack the library it names. readelf writes to a
# file first: /bin/sh has no pipefail, and a failing readelf must fail the build.
RUN touch src/lib.rs src/main.rs && \
    cargo build --release ${CARGO_FEATURES:+--features "$CARGO_FEATURES"} && \
    strip target/release/zapzap-backend && \
    readelf -d target/release/zapzap-backend > /tmp/dynamic-section && \
    ! grep -q NEEDED /tmp/dynamic-section

# Stage 2: Runtime
# ca-certificates only: rustls-native-certs (the Bedrock client) reads the system store,
# /etc/ssl/certs. Health checks use busybox's wget; there is no curl.
FROM alpine:3.22

RUN apk add --no-cache ca-certificates

# Non-root user, uid 1000: the ownership of data/ in production relies on it
RUN adduser -D -u 1000 zapzap

# Set working directory
WORKDIR /app

# Data directory, owned by the runtime user. Before the binary, and never a recursive chown
# of /app: a chown after the COPY would store the 20 MB binary a second time in its layer.
RUN mkdir -p /app/data && chown zapzap:zapzap /app/data

# Copy binary from builder; it stays root-owned, the runtime user cannot rewrite it
COPY --from=builder /app/target/release/zapzap-backend /app/zapzap-backend

# Switch to non-root user
USER zapzap

# Set environment variables
ENV PORT=9999
ENV DATABASE_URL=sqlite:/app/data/zapzap.db
ENV RUST_LOG=info,zapzap_backend=debug

# Expose port
EXPOSE 9999

# Health check. 127.0.0.1, not localhost: the backend listens on IPv4 only, and localhost
# may resolve to ::1 first.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q --spider http://127.0.0.1:9999/api/health || exit 1

# Run the application
CMD ["/app/zapzap-backend"]
