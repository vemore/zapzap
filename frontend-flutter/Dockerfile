# Flutter PWA image for ZapZap (multi-stage build).
#
# Stage 1 builds the web bundle with the same Flutter the CI `flutter` job pins
# (.github/workflows/ci.yml): a newer SDK is a different build, so the version and its
# checksum are pinned here too. Stage 2 is nginx serving the bundle under /app/, which is
# where the production proxy routes it (nginx/nginx.conf, .llmwiki/Deployment.md).

# Stage 1: build the web bundle
FROM debian:bookworm-slim AS builder

# Keep in step with .github/workflows/ci.yml (subosito/flutter-action) and
# .llmwiki/FrontendFlutter.md. The checksum is the one the release index publishes for
# this archive; bump both together.
ARG FLUTTER_VERSION=3.47.2
ARG FLUTTER_SHA256=447878859d01ca9bfdb99a85f245af07ed8a15fedcd9d189c4749e8e92d1f185

# git: the SDK is a git checkout and the flutter tool reads it. xz-utils: the archive.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

# The flutter tool refuses to run as root, and so does pub.
RUN useradd --create-home --uid 1000 builder
USER builder
WORKDIR /home/builder

RUN curl -fsSL -o flutter.tar.xz \
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && echo "${FLUTTER_SHA256}  flutter.tar.xz" | sha256sum -c - \
    && tar -xf flutter.tar.xz \
    && rm flutter.tar.xz
ENV PATH="/home/builder/flutter/bin:${PATH}"
RUN flutter --version

WORKDIR /home/builder/app

# Dependencies first, so a source-only change keeps this layer. --enforce-lockfile: the
# image resolves exactly what CI resolved, or the build fails.
COPY --chown=builder:builder pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile

COPY --chown=builder:builder . .

# lib/l10n/app_localizations*.dart are generated, not committed (l10n.yaml).
RUN flutter gen-l10n \
    && flutter build web --release --base-href /app/

# Stage 2: serve it
FROM nginx:alpine

# Under /app/ inside the image too, so a path matches the public URL and the SPA
# fallback can name /app/index.html.
COPY --from=builder /home/builder/app/build/web /usr/share/nginx/html/app
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
