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

everything() { rust=true; native=true; frontend=true; image=true; hooks=true; flutter=true; }

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

        # The Claude Code hooks and the scripts scripts/hooks_selftest.sh exercises.
        .claude/hooks/*|.claude/settings.json|scripts/hooks_selftest.sh|scripts/cleanup_local.sh|scripts/worktree_setup.sh|scripts/wip.sh)
            hooks=true ;;

        # The smoke test the image job runs against the Flutter PWA image.
        scripts/pwa_image_smoke.sh) image=true ;;

        # The legacy Node backend (src/ and its root files): no job tests it, it is
        # no longer deployed (.llmwiki/Architecture.md).
        src/*|tests/*|views/*|public/*|app.js|logger.js|jest.config.js|playwright.config.js|eslint.config.mjs|package.json|package-lock.json) ;;

        # Everything else: .github/, .claude/, scripts/, a root config, a path
        # nobody has classified yet.
        *) everything ;;
    esac
done

printf 'rust=%s\nnative=%s\nfrontend=%s\nimage=%s\nhooks=%s\nflutter=%s\n' "$rust" "$native" "$frontend" "$image" "$hooks" "$flutter"
