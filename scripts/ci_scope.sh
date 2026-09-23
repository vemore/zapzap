#!/bin/bash

# ZapZap - which CI jobs a change needs.
#
# Reads changed paths on stdin, one per line, and writes the job flags on stdout
# as `name=true|false`, in the order .github/workflows/ci.yml declares them. No
# gh, no network, no repository access: the classification is a pure function of
# the path list, which is what lets scripts/ci_scope_selftest.sh pin it.
#
# First match wins, per path, and the last rule is "everything": an unknown path
# -- a new top-level directory, a new root config -- runs the whole pipeline.
# Being wrong must cost a slow run, never an untested merge.
#
# Usage: git diff --name-only origin/master...HEAD | scripts/ci_scope.sh

set -uo pipefail

rust=false
native=false
frontend=false
image=false
hooks=false
flutter=false
node=false

everything() { rust=true; native=true; frontend=true; image=true; hooks=true; flutter=true; node=true; }

while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
        # Documentation. A case glob's `*` crosses `/`, so `*.md` is `**/*.md`.
        *.md|.llmwiki/*|docs/*|LICENSE|image.png) ;;

        # The Rust backend -- the deployed server -- and the image built from it.
        zapzap-rust/*) rust=true; image=true ;;

        # Bot parameters and models: zapzap-rust/data is a symlink to data/.
        data/*) rust=true ;;

        # The DRL training engine. Nothing deployed links it.
        native/*) native=true ;;

        # The React client, and its own image.
        frontend/*) frontend=true; image=true ;;

        # The Flutter client (Android + PWA), and the image the PWA is served from
        # (.llmwiki/Deployment.md). `frontend/*` does not match it: the slash.
        frontend-flutter/*) flutter=true; image=true ;;

        # The reverse proxy configuration, baked into no image but mounted by compose.
        nginx/*) image=true ;;

        # The Claude Code hooks and the scripts scripts/hooks_selftest.sh exercises
        # (deploy.sh is driven there; rebuild.sh is its sibling). No image holds them.
        .claude/hooks/*|.claude/settings.json|scripts/hooks_selftest.sh|scripts/cleanup_local.sh|scripts/worktree_setup.sh|scripts/wip.sh|deploy.sh|rebuild.sh)
            hooks=true ;;

        # The smoke test the image job runs against the Flutter PWA image.
        scripts/pwa_image_smoke.sh) image=true ;;

        # The Node schema, which zapzap-rust/tests/schema_tests.rs reads and compares
        # with the Rust backend's copy: a change to it needs the rust job too.
        src/infrastructure/database/sqlite/DatabaseConnection.js) rust=true; node=true; image=true ;;

        # The Node backend, which production runs (.llmwiki/Deployment.md): its code and
        # dependencies are tested by jest and baked into the root Dockerfile's image.
        src/*|app.js|logger.js|package.json|package-lock.json) node=true; image=true ;;

        # What the Node image holds but jest does not load, and the image's own recipe.
        views/*|public/*|Dockerfile|.dockerignore) image=true ;;

        # The jest suites and their configuration.
        tests/*|jest.config.js) node=true ;;

        # Configurations no job runs: Playwright (tests/e2e) and the root ESLint.
        playwright.config.js|eslint.config.mjs) ;;

        # Everything else: .github/, .claude/, scripts/, a root config, a path
        # nobody has classified yet.
        *) everything ;;
    esac
done

printf 'rust=%s\nnative=%s\nfrontend=%s\nimage=%s\nhooks=%s\nflutter=%s\nnode=%s\n' "$rust" "$native" "$frontend" "$image" "$hooks" "$flutter" "$node"
