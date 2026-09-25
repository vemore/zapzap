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
parity=false
e2e=false

everything() { rust=true; native=true; frontend=true; image=true; hooks=true; flutter=true; node=true; parity=true; e2e=true; }

while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
        # Documentation. A case glob's `*` crosses `/`, so `*.md` is `**/*.md`.
        *.md|.llmwiki/*|docs/*|LICENSE|image.png) ;;

        # The Rust backend -- what production runs (.llmwiki/Deployment.md) -- and the
        # image built from it; the parity suite runs its release build against the Node
        # backend, and the Flutter end-to-end run plays a round against it.
        # Password hashing and its fixture: jest's RustBcryptCompat.test.js checks Node reads them.
        zapzap-rust/src/infrastructure/auth/*|zapzap-rust/tests/fixtures/bcrypt_node_compat.json) rust=true; node=true; image=true; parity=true; e2e=true ;;
        zapzap-rust/*) rust=true; image=true; parity=true; e2e=true ;;

        # Bot parameters and models: zapzap-rust/data is a symlink to data/.
        data/*) rust=true ;;

        # The DRL training engine. Nothing deployed links it.
        native/*) native=true ;;

        # The React client, and its own image.
        frontend/*) frontend=true; image=true ;;

        # The Flutter client (Android + PWA), the image the PWA is served from
        # (.llmwiki/Deployment.md), and its end-to-end run. `frontend/*` does not match
        # it: the slash.
        frontend-flutter/*) flutter=true; image=true; e2e=true ;;

        # The reverse proxy configuration, baked into no image but mounted by compose.
        nginx/*) image=true ;;

        # The Claude Code hooks and the scripts scripts/hooks_selftest.sh exercises
        # (deploy.sh is driven there; rebuild.sh is its sibling). No image holds them.
        .claude/hooks/*|.claude/settings.json|scripts/hooks_selftest.sh|scripts/cleanup_local.sh|scripts/worktree_setup.sh|scripts/wip.sh|deploy.sh|rebuild.sh)
            hooks=true ;;

        # The Flutter end-to-end run, which the flutter-e2e job (on the e2e flag) runs.
        scripts/flutter_e2e.sh) e2e=true ;;

        # The smoke tests the image job runs: the Flutter PWA image, the production backend.
        scripts/pwa_image_smoke.sh|scripts/backend_image_smoke.sh) image=true ;;

        # The Node backend, production's rollback since the switch to Rust
        # (.llmwiki/Deployment.md): its code and dependencies are tested by jest, baked into
        # the root Dockerfile's image (which a rollback builds), and compared with the Rust
        # backend by the parity suite. Not e2e: the Flutter end-to-end run seeds its bots
        # with `zapzap-backend seed` and runs no Node.
        src/*|app.js|logger.js|package.json|package-lock.json) node=true; image=true; parity=true ;;

        # What the Node image holds but jest does not load, and the image's own recipe.
        views/*|public/*|Dockerfile|.dockerignore) image=true ;;

        # The parity suite (node --test, outside jest): Node against Rust.
        tests/parity/*) parity=true ;;

        # The jest suites and their configuration.
        tests/*|jest.config.js) node=true ;;

        # Configurations no job runs: Playwright (tests/e2e) and the root ESLint.
        playwright.config.js|eslint.config.mjs) ;;

        # Everything else: .github/, .claude/, scripts/, a root config, a path
        # nobody has classified yet.
        *) everything ;;
    esac
done

printf 'rust=%s\nnative=%s\nfrontend=%s\nimage=%s\nhooks=%s\nflutter=%s\nnode=%s\nparity=%s\ne2e=%s\n' "$rust" "$native" "$frontend" "$image" "$hooks" "$flutter" "$node" "$parity" "$e2e"
