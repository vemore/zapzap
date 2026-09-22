#!/bin/bash

# ZapZap - session opener (Claude Code SessionStart hook)
#
# SessionStart is one of the few events whose plain stdout is injected into the
# conversation, so this says what is only actionable BEFORE work starts: whether
# the tree is set up, whether the branch left over from the previous session is
# safe to commit on, which worktrees are in flight, and the open wip/ entries.

set -uo pipefail

payload=$(cat 2>/dev/null)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
ROOT=""
[ -n "$cwd" ] && ROOT=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
[ -z "$ROOT" ] && ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

[ -d frontend ] && [ ! -d frontend/node_modules ] && \
    echo "frontend/node_modules is missing: run \`scripts/worktree_setup.sh $ROOT\` (or \`npm ci --prefix frontend\`) before a frontend commit."

# A merged pull request whose base was not `master` merged into that base. If the base
# was itself merged first, the child's work never reached master.
delivery_check() {
    case "$(git remote get-url origin 2>/dev/null)" in *github.com*) ;; *) return ;; esac
    command -v gh >/dev/null 2>&1 || return
    gh auth status >/dev/null 2>&1 || return

    local cutoff acked
    cutoff=$(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || return
    acked=" $(git config --get-all zapzap.deliveryAcknowledged 2>/dev/null | tr '\n' ' ') "

    timeout 20 gh pr list --state merged --limit 30 \
        --json number,title,baseRefName,mergeCommit,mergedAt \
        --jq ".[] | select(.baseRefName != \"master\") | select(.mergedAt > \"$cutoff\") | \"\(.number)\t\(.baseRefName)\t\(.mergeCommit.oid)\t\(.title)\"" \
        2>/dev/null |
    while IFS=$'\t' read -r number base sha title; do
        case "$acked" in *" $number "*) continue ;; esac
        case "$(timeout 20 gh api "repos/{owner}/{repo}/compare/master...$sha" --jq .status 2>/dev/null)" in
            identical|behind) continue ;;
        esac
        echo "PR #$number merged into '$base', not into master, and its commits are not on master:"
        echo "  \"$title\" — check whether that work reached master another way. If it did,"
        echo "  record it: git config --add zapzap.deliveryAcknowledged $number"
    done
}

# Parallel work lives in worktrees, one per pull request. A session that resumes the
# orchestration needs to see them before it starts anything new.
worktrees_report() {
    local lines
    lines=$(git worktree list --porcelain 2>/dev/null | awk -v root="$ROOT" '
        /^worktree / { if (p != "" && p != root) print p "\t" b; p = substr($0, 10); b = "(detached)" }
        /^branch /   { b = substr($0, 19) }
        END          { if (p != "" && p != root) print p "\t" b }')
    local gone
    gone=$(git for-each-ref --format='%(upstream:track)' refs/heads 2>/dev/null | grep -c '^\[gone\]$')
    [ -z "$lines" ] && [ "${gone:-0}" -eq 0 ] && return
    if [ -n "$lines" ]; then
        echo "Other worktrees of this repository:"
        printf '%s\n' "$lines" | while IFS=$'\t' read -r path branch; do
            echo "  $branch  ->  $path"
        done
    fi
    [ "${gone:-0}" -gt 0 ] && echo "$gone local branch(es) whose remote branch was deleted."
    echo "Once no agent is working in them: scripts/cleanup_local.sh (dry run), then --apply."
}

# wip/ is local to the main checkout, so a session in a worktree is told where it is.
wip_report() {
    local main wip todo todo_nr
    main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")
    wip="$main/wip"
    [ -d "$wip" ] || return
    todo=$(find "$wip/todo" -name '*.md' 2>/dev/null | wc -l)
    todo_nr=$(find "$wip/todo_nr" -name '*.md' 2>/dev/null | wc -l)
    echo "wip/ (local, $wip): $todo in todo/, $todo_nr in todo_nr/ — scripts/wip.sh list"
}

git rev-parse --git-dir >/dev/null 2>&1 || exit 0
worktrees_report
delivery_check
wip_report
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$branch" ] && exit 0

if git rev-parse --verify -q origin/master >/dev/null 2>&1; then
    counts=$(git rev-list --left-right --count origin/master...HEAD 2>/dev/null)
    behind=$(echo "$counts" | cut -f1)
    ahead=$(echo "$counts" | cut -f2)
    track=$(git for-each-ref --format='%(upstream:track)' "refs/heads/$branch" 2>/dev/null)
    stale=""
    [ "$track" = "[gone]" ] && stale="its remote branch was merged and deleted"
    if [ -z "$stale" ] && [ "${ahead:-0}" -gt 0 ] && [ "${ahead:-0}" -le 50 ]; then
        git cherry origin/master HEAD 2>/dev/null | grep -q '^-' \
            && stale="it replays commits already on origin/master"
    fi
    echo "Branch: $branch (${ahead:-0} ahead, ${behind:-0} behind origin/master)"
    if [ "$branch" = "master" ] || [ -n "$stale" ]; then
        [ -n "$stale" ] && echo "This branch is not safe to commit on -- $stale."
        echo "Start the work in its own worktree, on a fresh branch (the main checkout stays on master):"
        echo "  git fetch --prune origin && git worktree add ../zapzap-<topic> -b <type>/<topic> origin/master"
        echo "  scripts/worktree_setup.sh ../zapzap-<topic>"
    fi
fi
exit 0
