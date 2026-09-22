#!/bin/bash

# ZapZap - Bash command guard (Claude Code PreToolUse hook)
#
# Refuses, before it runs, a command that breaks a rule no review can be relied
# on to catch, and runs the quality gates before a commit.
#
# The rules and the reasoning behind each are in .llmwiki/Hooks.md.
#
# Exit 2 is the ONLY code that blocks a PreToolUse hook: exit 1 is treated as a
# non-blocking error and the command runs anyway. Hence `set -u` without `-e` --
# a grep that matches nothing must not kill the script and silently open the gate.

set -uo pipefail

PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

payload=$(cat)
verdict=$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$PROJECT" python3 "$HOOKS/parse_command.py" 2>/dev/null)
[ -z "$verdict" ] && exit 0   # parser unavailable: fail open, never block on our own bug

# The repository a git command acts on is the one holding the directory it runs in --
# a worktree, when the work happens in one -- not the checkout the session was
# launched from. CLAUDE_PROJECT_DIR is only the fallback.
repo_of() {  # directory
    [ -n "$1" ] && [ "$1" != "null" ] && git -C "$1" rev-parse --show-toplevel 2>/dev/null && return
    printf '%s\n' "$PROJECT"
}
command_cwd=$(printf '%s' "$verdict" | jq -r '.commit.cwd // .push.cwd // empty' 2>/dev/null)
[ -z "$command_cwd" ] && command_cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
ROOT=$(repo_of "$command_cwd")

# --------------------------------------------------------------- outright refusals

# Stacking is refused by default but stays possible, deliberately and per repository.
allow_stacked=$(cd "$ROOT" 2>/dev/null && git config --get --bool zapzap.allowStackedPr 2>/dev/null)
if [ "$allow_stacked" = "true" ]; then
    verdict=$(printf '%s' "$verdict" | jq '.blocks |= map(select(.rule != "stacked-pr"))' 2>/dev/null)
fi

blocked=$(printf '%s' "$verdict" | jq -r '.blocks[]?.message' 2>/dev/null)
if [ -n "$blocked" ]; then
    printf '%s\n' "$blocked" >&2
    exit 2
fi

# A bare `git push` publishes the current branch to its upstream: refuse it on master,
# which the parser cannot see from the command line alone.
if printf '%s' "$verdict" | jq -e '.push != null and (.push.refspecs | length) == 0' >/dev/null 2>&1; then
    if [ "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "master" ]; then
        printf '%s\n' "Refused: \`git push\` from master would update master directly.

master only moves through a squash-merged pull request with green checks, and the branch
protection does not stop an admin push. Work on a branch off origin/master." >&2
        exit 2
    fi
fi

printf '%s' "$verdict" | jq -e '.commit != null' >/dev/null 2>&1 || exit 0

# ------------------------------------------------------------------ commit gates

cd "$ROOT" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

commit_all=$(printf '%s' "$verdict" | jq -r '.commit.all')
commit_amend=$(printf '%s' "$verdict" | jq -r '.commit.amend')

# Which files will this commit contain? `git commit -a` stages tracked changes
# AFTER this hook inspects the index, so --cached alone reports nothing and the
# filter below would wrongly conclude "documentation only, no gates needed".
# A merge commit is judged on what differs from the merged-in branch -- this branch's
# own changes and the resolutions -- not on everything the merge brings in.
base=()
git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && base=(MERGE_HEAD)
paths=$(git diff --cached --name-only "${base[@]}" 2>/dev/null)
[ "$commit_all" = "true" ] && paths="$paths"$'\n'"$(git diff --name-only "${base[@]}" 2>/dev/null)"
if [ "$commit_amend" = "true" ] && git rev-parse --verify -q HEAD >/dev/null; then
    paths="$paths"$'\n'"$(git show --name-only --pretty=format: HEAD 2>/dev/null)"
fi
paths="$paths"$'\n'"$(printf '%s' "$verdict" | jq -r '.commit.pathspecs[]?')"
paths=$(printf '%s\n' "$paths" | grep -v '^$' | sort -u)

# A deletion (`git rm --cached data/zapzap.db`) is not an addition: only the paths
# this commit adds or modifies can leak a secret.
added=$(git diff --cached --name-only --diff-filter=d "${base[@]}" 2>/dev/null)
[ "$commit_all" = "true" ] && added="$added"$'\n'"$(git diff --name-only --diff-filter=d "${base[@]}" 2>/dev/null)"
added="$added"$'\n'"$(printf '%s' "$verdict" | jq -r '.commit.pathspecs[]?' | while read -r f; do [ -e "$f" ] && echo "$f"; done)"
added=$(printf '%s\n' "$added" | grep -v '^$' | sort -u)

refuse() {
    printf '%s\n' "$1" >&2
    exit 2
}

# 1. Secrets and the database ------------------------------------------------
secrets=$(printf '%s\n' "$added" | grep -E '(^|/)\.env$|(^|/)\.env\.|(^|/)client_secret_[^/]*\.json$|\.(db|sqlite|sqlite3)(\.bak-[^/]*)?$' \
          | grep -vE '(^|/)\.env\.example$')
if [ -n "$secrets" ]; then
    refuse "Refused: this commit would add a secret or a database to the repository.

$secrets

Every .env holds JWT_SECRET and the cloud credentials; client_secret_*.json is the Google
OAuth client; data/zapzap.db holds every account and password hash. All are gitignored,
so reaching this point took a \`git add -f\`. Unstage with \`git reset <path>\` and commit
again. .env.example is the committed template."
fi

# 2. Work tracking ----------------------------------------------------------
# wip/ is local on purpose (gitignored); only a `git add -f` gets it staged. TODO.md was
# replaced by it and must not come back.
tracked=$(printf '%s\n' "$added" | grep -E '^wip/|^(TODO|DONE)\.md$')
[ -n "$tracked" ] && refuse "Refused: this commit would add local work tracking to the repository.

$tracked

Work is tracked one file per entry under wip/ in the main checkout, and wip/ is never
committed -- it is gitignored for that reason. TODO.md and DONE.md were replaced by it.
Unstage with \`git reset <path>\`; move any content into a wip/ entry (wip/README.md)."

# 3. Branch ----------------------------------------------------------------
if git rev-parse --verify -q origin/master >/dev/null && git rev-parse --verify -q HEAD >/dev/null; then
    branch=$(git rev-parse --abbrev-ref HEAD)
    recipe="git fetch --prune origin && git worktree add ../zapzap-<topic> -b <type>/<topic> origin/master
then move the work over: \`git cherry -v origin/master <old-branch>\` marks with '+' the
commits that are genuinely new, and those are the ones to cherry-pick."

    [ "$branch" = "HEAD" ] && refuse "Refused: committing on a detached HEAD.

$recipe"
    [ "$branch" = "master" ] && refuse "Refused: committing directly on master.

Work goes on a branch off origin/master, in its own worktree, and reaches master through
a pull request.

$recipe"

    track=$(git for-each-ref --format='%(upstream:track)' "refs/heads/$branch" 2>/dev/null)
    if [ "$track" = "[gone]" ]; then
        refuse "Refused: branch '$branch' tracked a remote branch that no longer exists.

Its pull request was merged and the remote deleted it. Committing here stacks new work
on top of commits that are already upstream under different hashes.

$recipe"
    fi

    ahead=$(git rev-list --count origin/master..HEAD 2>/dev/null || echo 0)
    if [ "${ahead:-0}" -gt 0 ] && [ "${ahead:-0}" -le 50 ]; then
        if git cherry origin/master HEAD 2>/dev/null | grep -q '^-'; then
            refuse "Refused: branch '$branch' replays commits that are already on origin/master.

$(git cherry -v origin/master HEAD | grep '^-' | head -5)

Either the branch was merged upstream and is stale, or a commit was cherry-picked from
master. If it is the latter and you meant it, the check cannot tell them apart -- say so
to the user and let them decide.

$recipe"
        fi
    fi
    # Note: this hook never fetches. What it knows is only as fresh as your last
    # \`git fetch --prune\`, so it errs towards letting a stale branch through.
fi

# 4. Quality gates ---------------------------------------------------------
# Only the fast static checks run here; the test suites run in CI, and
# require-pull-request.sh refuses to finish while those checks are red.
needs_setup() {  # what is missing, setup command
    refuse "Refused: $1, so the gates this commit needs cannot run.

Run this as its own Bash call, then commit again:
    $2
The hook judges the whole command line before any of it runs, so \`install && git commit\`
or \`git add ... && git commit\` in one call never gets past this point."
}

run_gate() {  # name, then the command
    local name="$1"; shift
    local output
    if ! output=$("$@" 2>&1); then
        refuse "Refused: \`$name\` fails, so this commit is not ready.

$(printf '%s\n' "$output" | tail -40)

Fix it, then commit again. Reproduce with: $name"
    fi
}

# Worktrees share the main checkout's cargo target directories, so the first commit in
# a fresh worktree does not rebuild every dependency inside the hook's timeout.
MAIN=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")

if printf '%s\n' "$paths" | grep -qE '^zapzap-rust/'; then
    command -v cargo >/dev/null 2>&1 || needs_setup "cargo is not on PATH" "install Rust with rustup (.llmwiki/Backend.md)"
    run_gate "cargo fmt --check (zapzap-rust)" bash -c "cd '$ROOT/zapzap-rust' && cargo fmt --check"
    run_gate "cargo clippy --locked --all-targets -- -D warnings (zapzap-rust)" \
        env CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$MAIN/zapzap-rust/target}" bash -c "cd '$ROOT/zapzap-rust' && cargo clippy --locked --all-targets --quiet -- -D warnings"
fi

if printf '%s\n' "$paths" | grep -qE '^native/'; then
    command -v cargo >/dev/null 2>&1 || needs_setup "cargo is not on PATH" "install Rust with rustup (.llmwiki/NativeEngine.md)"
    run_gate "cargo fmt --check (native)" bash -c "cd '$ROOT/native' && cargo fmt --check"
fi

if printf '%s\n' "$paths" | grep -qE '^frontend/'; then
    [ -d "$ROOT/frontend/node_modules" ] || needs_setup "frontend/node_modules is missing (this tree was never set up)" "npm ci --prefix $ROOT/frontend"
    run_gate "npm run build (frontend)" bash -c "cd '$ROOT/frontend' && npm run build --silent"
fi

exit 0
