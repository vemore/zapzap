#!/bin/bash

# ZapZap - remove the local worktrees and branches that no longer serve anything.
#
# Parallel work leaves debris: a worktree per pull request, the `worktree-<name>`
# branch the Agent tool creates before the agent switches to its real branch, a
# deploy worktree, and a local branch per merged pull request. Pull requests are
# squash-merged, so `git branch -d` never recognises them as merged, and `-D` would
# happily destroy a commit that never reached GitHub. This decides on evidence.
#
# A local branch is deleted when either:
#   - it has no commit of its own (nothing ahead of origin/master), or
#   - GitHub reports a MERGED pull request for it, and its local tip is contained
#     in that pull request's head (GitHub compare: identical or behind) -- so every
#     local commit was part of what merged.
# Anything else is kept, with the reason: no pull request, pull request open or
# closed, local commits beyond the merged head, or GitHub unreachable.
#
# A worktree (never the main checkout) is removed when it has no uncommitted or
# untracked change, and its branch is deletable -- or it is detached on a commit
# already in origin/master.
#
# Still prefer running it once no agent is working: a freshly created branch with no
# commit yet, in a clean worktree, is indistinguishable from an abandoned one. Two
# guards make the common cases visible rather than remembered, and both keep the
# worktree's branch as well as the worktree:
#   - a `.zapzap-setup-in-progress` marker, written by scripts/worktree_setup.sh
#     while it runs and left behind when it fails. Codegen writes only gitignored
#     files, so a worktree in the middle of a five-minute setup reads as clean.
#   - anything under the worktree modified in the last CLEANUP_IDLE_MINUTES (default
#     30) minutes — an agent may simply be working there, with nothing committed yet.
# A git worktree lock is read before both. Claude Code locks an agent's worktree with a
# reason naming its process, `claude agent <name> (pid N start T)`: while that pid is alive
# (and, where /proc can tell, still the process that started at T), the worktree and its
# branch are kept. Once the process is gone the lock is stale: the worktree goes through
# the rules above like any other and is removed with `git worktree remove -f -f`. A lock
# that names no pid was taken by hand, and is always honoured. When a removal fails,
# --apply prints git's error under the FAILED line.
#
# Usage: scripts/cleanup_local.sh            dry run: print what would go, and why
#        scripts/cleanup_local.sh --apply    do it
#        CLEANUP_IDLE_MINUTES=0 …            disable the modification-time guard

set -uo pipefail

apply=0
case "${1:-}" in
    --apply) apply=1 ;;
    "") ;;
    -h|--help) sed -n '3,42p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

MAIN="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
cd "$MAIN" || exit 1
git fetch --prune -q origin 2>/dev/null || echo "warning: fetch failed, origin/master may be stale" >&2
git rev-parse --verify -q origin/master >/dev/null || { echo "no origin/master" >&2; exit 1; }

gh_ok=0
command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && gh_ok=1

SETUP_MARKER=".zapzap-setup-in-progress"
idle="${CLEANUP_IDLE_MINUTES:-30}"
case "$idle" in
    ""|*[!0-9]*) echo "CLEANUP_IDLE_MINUTES must be a whole number of minutes: $idle" >&2; exit 2 ;;
esac

busy() {  # worktree path -> 0 if something under it was touched inside the idle window
    [ "$idle" -eq 0 ] && return 1
    # -print -quit stops at the first hit, so this stays cheap over a .dart_tool/.
    [ -n "$(find "$1" -newermt "-$idle minutes" -print -quit 2>/dev/null)" ]
}

REASON=""
deletable() {  # branch -> 0 if it may go; REASON says why, either way
    local branch="$1" ahead head status
    ahead=$(git rev-list --count "origin/master..$branch" 2>/dev/null || echo 1)
    if [ "$ahead" -eq 0 ]; then
        REASON="no commit of its own"
        return 0
    fi
    if [ "$gh_ok" = 0 ]; then
        REASON="$ahead commit(s) ahead, and gh is unavailable to prove they merged"
        return 1
    fi
    head=$(timeout 20 gh pr list --head "$branch" --state merged --limit 1 \
           --json headRefOid,number --jq '.[0] | "\(.headRefOid) \(.number)"' 2>/dev/null)
    if [ -z "$head" ] || [ "$head" = "null null" ]; then
        local open
        open=$(timeout 20 gh pr list --head "$branch" --state all --limit 1 \
               --json number,state --jq '.[0] | "#\(.number) \(.state)"' 2>/dev/null)
        REASON="$ahead commit(s) ahead, pull request: ${open:-none}"
        return 1
    fi
    status=$(timeout 20 gh api "repos/{owner}/{repo}/compare/${head%% *}...$(git rev-parse "$branch")" \
             --jq .status 2>/dev/null)
    case "$status" in
        identical|behind)
            REASON="pull request #${head##* } merged, local tip included"
            return 0 ;;
        "")
            REASON="pull request #${head##* } merged, but the local tip is not on GitHub"
            return 1 ;;
        *)
            REASON="pull request #${head##* } merged, but the local tip has commits beyond it ($status)"
            return 1 ;;
    esac
}

act() {  # description, command...
    local what="$1" out; shift
    if [ "$apply" = 1 ]; then
        if out=$("$@" 2>&1); then
            echo "  removed  $what"
        else
            echo "  FAILED   $what"
            printf '%s\n' "$out" | sed 's/^/           /'
        fi
    else
        echo "  would remove  $what"
    fi
}

proc_start() {  # pid -> its start time in clock ticks (/proc/<pid>/stat field 22), if known
    local stat
    stat=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
    stat=${stat##*) }   # the command name may itself hold spaces and parentheses
    # shellcheck disable=SC2086
    set -- $stat        # field 3 (state) is now $1, so field 22 is $20
    [ -n "${20:-}" ] && echo "${20}"
}

LOCK="" LOCK_STATE=""
lock_state() {  # lock reason -> LOCK_STATE live | stale | manual, LOCK says why
    local reason="$1" pid start now
    if [[ ! "$reason" =~ \(pid\ ([0-9]+)(\ start\ ([0-9]+))?\) ]]; then
        LOCK_STATE=manual LOCK="locked${reason:+: $reason}"
        return
    fi
    pid="${BASH_REMATCH[1]}" start="${BASH_REMATCH[3]}"
    if ! kill -0 "$pid" 2>/dev/null && ! ps -p "$pid" >/dev/null 2>&1; then
        LOCK_STATE=stale LOCK="stale lock, pid $pid is gone"
    elif [ -n "$start" ] && now=$(proc_start "$pid") && [ "$now" != "$start" ]; then
        LOCK_STATE=stale LOCK="stale lock, pid $pid is now another process"
    else
        LOCK_STATE=live LOCK="locked by a running session (pid $pid)"
    fi
}

removed_worktrees=()
declare -A kept_branch=()
kept_branch[master]=1
current=$(git rev-parse --abbrev-ref HEAD)
kept_branch[$current]=1

echo "Worktrees"
while IFS=$'\t' read -r path ref locked; do
    [ "$path" = "$MAIN" ] && continue
    [ "$ref" = "-" ] && ref=""
    if [ ! -d "$path" ]; then
        continue  # pruned below
    fi
    # The lock comes first: a running session's worktree is kept whatever else is true.
    remove=(git worktree remove)
    note=""
    if [ "$locked" != "-" ]; then
        reason="${locked#locked}"
        lock_state "${reason# }"
        if [ "$LOCK_STATE" != stale ]; then
            echo "  keep     $path${ref:+ ($ref)} — $LOCK"
            [ -n "$ref" ] && kept_branch[$ref]=1
            continue
        fi
        remove=(git worktree remove -f -f)
        note="; $LOCK"
    fi
    # Both guards run before every other rule: a worktree an agent still holds is clean
    # by `git status`, so its branch would be deleted out from under it too.
    if [ -e "$path/$SETUP_MARKER" ]; then
        echo "  keep     $path — setup in progress ($SETUP_MARKER)"
        [ -n "$ref" ] && kept_branch[$ref]=1
        continue
    fi
    if busy "$path"; then
        echo "  keep     $path — modified in the last $idle minutes (an agent may be working)"
        [ -n "$ref" ] && kept_branch[$ref]=1
        continue
    fi
    if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
        echo "  keep     $path — uncommitted or untracked changes"
        [ -n "$ref" ] && kept_branch[$ref]=1
        continue
    fi
    if [ -z "$ref" ]; then
        if git merge-base --is-ancestor "$(git -C "$path" rev-parse HEAD)" origin/master 2>/dev/null; then
            act "$path (detached, on master$note)" "${remove[@]}" "$path"
            removed_worktrees+=("$path")
        else
            echo "  keep     $path — detached on a commit not in origin/master"
        fi
        continue
    fi
    if deletable "$ref"; then
        act "$path ($ref: $REASON$note)" "${remove[@]}" "$path"
        removed_worktrees+=("$path")
    else
        echo "  keep     $path ($ref) — $REASON"
        kept_branch[$ref]=1
    fi
done < <(git worktree list --porcelain | awk '
    # An empty field is printed as "-": read collapses consecutive tabs, shifting columns.
    function out() { if (p != "") print p "\t" (b == "" ? "-" : b) "\t" (l == "" ? "-" : l) }
    /^worktree / { out(); p = substr($0, 10); b = ""; l = "" }
    /^branch /   { b = substr($0, 19) }
    /^locked/    { l = $0 }
    END          { out() }')
[ "$apply" = 1 ] && git worktree prune

echo "Branches"
while read -r branch; do
    if [ -n "${kept_branch[$branch]:-}" ]; then
        [ "$branch" = "$current" ] && [ "$branch" != master ] && deletable "$branch" \
            && echo "  keep     $branch — checked out in the main checkout ($REASON): switch to master first"
        continue
    fi
    if deletable "$branch"; then
        act "$branch — $REASON" git branch -D "$branch"
    else
        echo "  keep     $branch — $REASON"
    fi
done < <(git for-each-ref --format='%(refname:short)' refs/heads)

[ "$apply" = 0 ] && echo && echo "Dry run. Re-run with --apply to remove the lines marked 'would remove'."
exit 0
