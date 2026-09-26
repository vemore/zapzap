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
e2e=false

everything() { rust=true; native=true; frontend=true; image=true; hooks=true; flutter=true; e2e=true; }

while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
        # The privacy policy, rendered to nginx/privacy.html: the image job checks the
        # committed page is not stale. Before the documentation rule, which `*.md` is.
        privacy_policy.md|scripts/build_privacy_page.py) image=true ;;

        # Documentation. A case glob's `*` crosses `/`, so `*.md` is `**/*.md`.
        *.md|.llmwiki/*|docs/*|LICENSE|image.png) ;;

        # The Rust backend -- what production runs (.llmwiki/Deployment.md) -- and the
        # image built from it; the Flutter end-to-end run plays a round against it.
        zapzap-rust/*) rust=true; image=true; e2e=true ;;

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

        # The reverse proxy: its configuration, baked into the production proxy image
        # (nginx/Dockerfile), which the image job builds and runs `nginx -t` in.
        nginx/*) image=true ;;

        # The production compose file: the image job checks it parses and requires
        # JWT_SECRET, the hooks job's deploy self-test reads its services and images.
        docker-compose.prod.yml) image=true; hooks=true ;;

        # The Claude Code hooks and the scripts the hooks job exercises: hooks_selftest.sh
        # (and generate_keystore.sh, which it runs with a stub keytool), and
        # deploy_nas_selftest.sh for the production deploy (rebuild.sh is its local
        # sibling). No image holds them.
        .claude/hooks/*|.claude/settings.json|scripts/hooks_selftest.sh|scripts/cleanup_local.sh|scripts/worktree_setup.sh|scripts/wip.sh|scripts/deploy_nas.sh|scripts/deploy_nas_selftest.sh|scripts/deploy.env.example|scripts/generate_keystore.sh|rebuild.sh)
            hooks=true ;;

        # The Play release scripts and their tests, which the hooks job runs: they are
        # never run in CI against Google, only on a fake service and throwaway keystores.
        scripts/verify_aab.sh|scripts/play_publish.py|scripts/test_verify_aab.py|scripts/test_play_publish.py)
            hooks=true ;;

        # The Flutter end-to-end run, which the flutter-e2e job (on the e2e flag) runs.
        scripts/flutter_e2e.sh) e2e=true ;;

        # The smoke tests the image job runs: the Flutter PWA image, the production backend.
        scripts/pwa_image_smoke.sh|scripts/backend_image_smoke.sh) image=true ;;

        # The Play Store listing: frontend-flutter/test/store_listing_test.dart checks its
        # texts and images against Play's limits, in the flutter job. Its generators run by
        # hand, not in CI (store_listing/README.md).
        store_listing/*|scripts/generate_store_graphics.py|scripts/capture_store_screenshots.*|scripts/compose_store_screenshots.py)
            flutter=true ;;

        # The root package.json holds only Playwright, the headless browser fallback of
        # .llmwiki/ParallelDelivery.md: no job installs it.
        package.json|package-lock.json) ;;

        # Everything else: .github/, .claude/, scripts/, a root config, a path
        # nobody has classified yet.
        *) everything ;;
    esac
done

printf 'rust=%s\nnative=%s\nfrontend=%s\nimage=%s\nhooks=%s\nflutter=%s\ne2e=%s\n' "$rust" "$native" "$frontend" "$image" "$hooks" "$flutter" "$e2e"
