#!/bin/bash

# ZapZap - make a git worktree ready to build, test and commit.
#
# A worktree is a fresh checkout: no node_modules, and none of the untracked local
# files that only the main checkout holds. Without this, the frontend gate of the
# commit hook refuses every commit for a reason unrelated to the change.
#
# Usage: scripts/worktree_setup.sh [worktree dir]   (default: the current repository)
#        --no-frontend  skip `npm ci` in frontend/
#        --no-rust      skip the cargo warm-up of zapzap-rust/
#        --deploy       link the main checkout's .env (backend-deploy, frontend-deploy)
#
# No secret reaches a worktree by default: an implementing agent never deploys, so only
# the deploy worktree (--deploy) gets the main checkout's .env, linked, never copied.
#
# Cargo builds go to the main checkout's target directories (CARGO_TARGET_DIR), as the
# commit hook does, so a worktree does not rebuild every dependency.
#
# While it runs, the worktree carries a `.zapzap-setup-in-progress` marker and
# `scripts/cleanup_local.sh` refuses to remove a worktree that has one. A failed setup
# leaves the marker on purpose; rerun this script, or remove it once judged stale.

set -euo pipefail

frontend=1
rust=1
LOCAL_ONLY=()
dir=""
for arg in "$@"; do
    case "$arg" in
        --no-frontend) frontend=0 ;;
        --no-rust) rust=0 ;;
        --deploy) LOCAL_ONLY+=(.env) ;;
        -h|--help) sed -n '3,22p' "$0"; exit 0 ;;
        -*) echo "worktree_setup.sh: unknown option $arg (see --help)" >&2; exit 2 ;;
        *) dir="$arg" ;;
    esac
done

TREE="$(git -C "${dir:-.}" rev-parse --show-toplevel)"
# The main checkout is the worktree that owns the shared .git directory.
MAIN="$(cd "$(git -C "$TREE" rev-parse --git-common-dir)/.." && pwd)"
cd "$TREE"

MARKER="$TREE/.zapzap-setup-in-progress"
echo "pid $$ started $(date -Iseconds) branch $(git rev-parse --abbrev-ref HEAD)" > "$MARKER"

echo "worktree: $TREE"
echo "main checkout: $MAIN"

if [ "$TREE" != "$MAIN" ]; then
    for file in ${LOCAL_ONLY[@]+"${LOCAL_ONLY[@]}"}; do
        if [ ! -e "$MAIN/$file" ]; then
            echo "not linked $file: the main checkout has none" >&2
        elif [ ! -e "$TREE/$file" ]; then
            ln -s "$MAIN/$file" "$TREE/$file"
            echo "linked $file"
        fi
    done
fi

if [ "$frontend" = 1 ]; then
    npm ci --prefix frontend --no-audit --no-fund
fi

if [ "$rust" = 1 ] && command -v cargo >/dev/null 2>&1; then
    (cd zapzap-rust && CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$MAIN/zapzap-rust/target}" cargo clippy --locked --all-targets --quiet)
fi

rm -f "$MARKER"
echo "ready: $TREE ($(git rev-parse --abbrev-ref HEAD))"
