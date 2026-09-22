#!/bin/bash

# ZapZap - pull-request reminder (Claude Code Stop hook)
#
# A change that only exists as a local commit is not delivered. This asks, when a
# turn ends (Stop) or a subagent finishes (SubagentStop), whether the commits on this branch have a pull request yet, and
# whether that pull request is green -- the two halves of "finished".
#
# It is deliberately quiet: it says nothing on master, on a branch with nothing to
# publish, or while the checks are still running. It never pushes and never opens
# anything itself; opening a pull request is an outward-facing act and stays a
# deliberate one.
#
# Escape hatch, for a branch that is genuinely not meant to be published yet:
#   git config branch.<branch>.noPullRequest true

set -uo pipefail

payload=$(cat)

# Judge the repository the session (or the subagent) is working in -- a worktree when
# the work happens in one -- and fall back to the launch directory.
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
ROOT=""
[ -n "$cwd" ] && ROOT=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
[ -z "$ROOT" ] && ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

# Already asked once and Claude is still working on it: do not ask again, or the
# turn never ends.
[ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

git rev-parse --git-dir >/dev/null 2>&1 || exit 0
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$branch" ] || [ "$branch" = "HEAD" ] || [ "$branch" = "master" ] && exit 0
[ "$(git config --get --bool "branch.$branch.noPullRequest" 2>/dev/null)" = "true" ] && exit 0

git rev-parse --verify -q origin/master >/dev/null 2>&1 || exit 0
[ "$(git rev-list --count origin/master..HEAD 2>/dev/null || echo 0)" -gt 0 ] || exit 0

case "$(git remote get-url origin 2>/dev/null)" in
    *github.com*) ;;
    *) exit 0 ;;   # nothing to open a pull request against
esac
command -v gh >/dev/null 2>&1 || exit 0
gh auth status >/dev/null 2>&1 || exit 0

block() {
    jq -n --arg r "$1" '{decision:"block", reason:$r}'
    exit 0
}

# Ask for every state, not just open. A merged pull request is the whole point of the
# rule, and asking only for open ones made this hook block forever on a branch whose
# pull request had just been merged -- the commits are still ahead of a local origin/master
# that has not been fetched since.
# `.[0] | ...` on an empty result yields the string "null null", not nothing.
pr=$(timeout 20 gh pr list --head "$branch" --state all --limit 1 --json number,url,state \
     --jq '.[] | "\(.number) \(.state) \(.url)"' 2>/dev/null | head -1)

state=$(printf '%s' "$pr" | cut -d' ' -f2)
case "$state" in
    MERGED)
        exit 0 ;;   # delivered; the branch is just still checked out
    CLOSED)
        block "Pull request $(printf '%s' "$pr" | cut -d' ' -f3) was closed without being merged,
and this branch still carries $(git rev-list --count origin/master..HEAD) commit(s).

Either the work was abandoned -- then say so and switch off this branch -- or it needs a
new pull request. Leaving it here delivers nothing." ;;
esac

if [ -z "$pr" ]; then
    dirty=""
    git diff --quiet 2>/dev/null || dirty="Commit the remaining changes first, then open it. "
    block "This branch has $(git rev-list --count origin/master..HEAD) commit(s) that no pull request covers.

A change that lives only in a local commit is not delivered: it is not reviewed, CI has
never run on it, and nobody else can see it. ${dirty}Push the branch and open the pull
request now, with a body that says what changed and why -- then report its URL and the
state of its checks.

  git push -u origin $branch
  gh pr create --base master --head $branch --title ... --body ...

If this branch is genuinely not meant to be published yet, say so to the user and set
\`git config branch.$branch.noPullRequest true\`."
fi

number=$(printf '%s' "$pr" | cut -d' ' -f1)
url=$(printf '%s' "$pr" | cut -d' ' -f3)
failing=$(timeout 30 gh pr checks "$number" --required 2>/dev/null | awk -F'\t' '$2 == "fail" {print "  " $1 "  " $4}')
[ -z "$failing" ] && failing=$(timeout 30 gh pr checks "$number" 2>/dev/null | awk -F'\t' '$2 == "fail" {print "  " $1 "  " $4}')

if [ -n "$failing" ]; then
    block "Pull request $url has failing checks:

$failing

The change is not finished while its own CI is red -- open the failing job, fix what it
found, and push. If the failure is unrelated to this branch, say so to the user rather
than leaving it unexplained."
fi
exit 0
