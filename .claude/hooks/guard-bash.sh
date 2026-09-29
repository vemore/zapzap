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

# The master rules protect this project's master: the branch of any checkout of it, and
# the master of its remote. A throwaway repository an agent builds under the scratchpad to
# test a script has a master nobody deploys; refusing to touch it only sent the same
# commands into a script file, which the hook does not read. Whatever cannot be told --
# no repository, a remote that does not resolve -- counts as the project.
common_dir() {  # directory -> its absolute git common dir, or nothing
    git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null
}
normalize_url() {  # git@github.com:o/r.git and https://github.com/o/r -> github.com/o/r
    printf '%s\n' "$1" | sed -E 's#^[a-z+]+://##; s#^[^@/]*@##; s#^([^/:]+):#\1/#; s#\.git/?$##; s#/+$##' \
        | tr '[:upper:]' '[:lower:]'
}
remote_key() {  # directory a URL is relative to, URL or path -> what identifies it
    local target="${2#file://}"
    [ "${target#/}" = "$target" ] && [ -d "$1/$target" ] && target="$1/$target"
    if [ -d "$target" ] && common_dir "$target"; then return; fi
    normalize_url "$2"
}
PROJECT_COMMON=$(common_dir "$PROJECT")
PROJECT_KEYS="$PROJECT_COMMON"$'\n'$(git -C "$PROJECT" remote 2>/dev/null | while read -r r; do
    remote_key "$PROJECT" "$(git -C "$PROJECT" remote get-url "$r" 2>/dev/null)"; done)
url_is_project() {  # directory the URL is relative to, URL or path
    printf '%s\n' "$PROJECT_KEYS" | grep -qxF -- "$(remote_key "$1" "$2")"
}
is_project_repo() {  # directory
    local common remote
    [ -z "$PROJECT_COMMON" ] && return 0
    common=$(common_dir "$1")
    [ -z "$common" ] || [ "$common" = "$PROJECT_COMMON" ] && return 0
    for remote in $(git -C "$1" remote 2>/dev/null); do
        url_is_project "$1" "$(git -C "$1" remote get-url "$remote" 2>/dev/null)" && return 0
    done
    return 1
}
is_project_remote() {  # directory the push runs in, remote (a name, a URL or a path)
    local url
    [ -z "$PROJECT_COMMON" ] || [ -z "$2" ] || [ "$2" = "null" ] && return 0
    url=$(git -C "$1" remote get-url "$2" 2>/dev/null) || url="$2"
    [ -z "$url" ] && return 0
    url_is_project "$1" "$url"
}

# --------------------------------------------------------------- outright refusals

# A push to master whose remote is a sandbox, from a directory the parser could tell.
drop=()
while IFS=$'\t' read -r index known cwd remote; do
    [ "$known" = "true" ] || continue
    is_project_remote "$(repo_of "$cwd")" "$remote" || drop+=("$index")
done < <(printf '%s' "$verdict" | jq -r '.blocks | to_entries[]
          | select(.value.rule == "push-main")
          | [.key, (.value.known // false), (.value.cwd // ""), (.value.remote // "")] | @tsv' 2>/dev/null)
if [ ${#drop[@]} -gt 0 ]; then
    verdict=$(printf '%s' "$verdict" | jq --argjson drop "[$(IFS=,; echo "${drop[*]}")]" \
        '.blocks |= [to_entries[] | select(.key as $k | $drop | index($k) | not) | .value]' 2>/dev/null)
fi

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
    push_remote=$(printf '%s' "$verdict" | jq -r '.push.remote // empty' 2>/dev/null)
    [ -z "$push_remote" ] && push_remote=$(git -C "$ROOT" config --get branch.master.pushRemote 2>/dev/null \
        || git -C "$ROOT" config --get remote.pushDefault 2>/dev/null \
        || git -C "$ROOT" config --get branch.master.remote 2>/dev/null \
        || echo origin)
    if [ "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "master" ] \
        && is_project_remote "$ROOT" "$push_remote"; then
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
# Every list is read NUL-separated: `--name-only` alone quotes a non-ASCII path
# ("cl\303\251.jks"), which no rule below would then match.
names() { git "$@" 2>/dev/null | tr '\0' '\n'; }
# A pathspec is relative to the directory the commit runs in, and may be a directory:
# the files it commits are the tracked ones under it that differ from HEAD, taken from
# the working tree.
pathspecs=()
while IFS= read -r p; do [ -n "$p" ] && pathspecs+=("$p"); done \
    < <(printf '%s' "$verdict" | jq -r '.commit.pathspecs[]?' 2>/dev/null)
spec_cwd=$command_cwd
[ -d "$spec_cwd" ] || spec_cwd=$ROOT
spec_files=""
if [ "${#pathspecs[@]}" -gt 0 ]; then
    if git rev-parse --verify -q HEAD >/dev/null; then
        spec_files=$(names -C "$spec_cwd" diff -z --name-only --diff-filter=d HEAD -- "${pathspecs[@]}")
    else
        spec_files=$(names -C "$spec_cwd" ls-files -z --full-name -- "${pathspecs[@]}")
    fi
fi
paths=$(names diff -z --cached --name-only "${base[@]}")
[ "$commit_all" = "true" ] && paths="$paths"$'\n'"$(names diff -z --name-only "${base[@]}")"
if [ "$commit_amend" = "true" ] && git rev-parse --verify -q HEAD >/dev/null; then
    paths="$paths"$'\n'"$(names show -z --name-only --pretty=format: HEAD)"
fi
paths="$paths"$'\n'"$spec_files"$'\n'"$(printf '%s\n' "${pathspecs[@]}")"
paths=$(printf '%s\n' "$paths" | grep -v '^$' | sort -u)

# A deletion (`git rm --cached data/zapzap.db`) is not an addition: only the paths
# this commit adds or modifies can leak a secret. Those the commit takes from the working
# tree -- `-a` and pathspecs -- are read there; a file only staged is read in the index,
# so an unstaged edit of another file never decides this commit.
worktree_files=$spec_files
[ "$commit_all" = "true" ] && worktree_files="$worktree_files"$'\n'"$(names diff -z --name-only --diff-filter=d "${base[@]}")"
worktree_files=$(printf '%s\n' "$worktree_files" | grep -v '^$' | sort -u)
added="$(names diff -z --cached --name-only --diff-filter=d "${base[@]}")"$'\n'"$worktree_files"
# A commit with pathspecs and no -i (git's --only) records those paths alone: a staged
# file outside them stays staged and is not part of it.
commit_include=$(printf '%s' "$verdict" | jq -r '.commit.include // false')
if [ "${#pathspecs[@]}" -gt 0 ] && [ "$commit_include" != "true" ] && [ "$commit_all" != "true" ]; then
    added=$worktree_files
fi
added=$(printf '%s\n' "$added" | grep -v '^$' | sort -u)

refuse() {
    printf '%s\n' "$1" >&2
    exit 2
}

# 1. Secrets and the database ------------------------------------------------
# Names match whatever their case: `upload.JKS` is the same keystore.
secrets=$(printf '%s\n' "$added" | grep -iE '(^|/)\.env$|(^|/)\.env\.|(^|/)client_secret_[^/]*\.json$|\.(db|sqlite|sqlite3)(\.bak-[^/]*)?$|(^|/)key\.properties$|\.(jks|keystore)$|service-account[^/]*\.json$' \
          | grep -viE '(^|/)\.env\.example$')
# A Google credential file is recognised by its content, whatever its name or extension:
# a service-account key, gcloud's application-default credentials (authorized_user, a
# live refresh token) or a workload-identity config (external_account). `"type"` must
# open a line or follow `{` or `,`, as in JSON, so a document quoting it in backticks
# passes. The staged blob is read for every added file, the working file for those the
# commit takes from the working tree.
sa_key='(^|[{,])[[:space:]]*"type"[[:space:]]*:[[:space:]]*"(service_account|authorized_user|external_account|external_account_authorized_user|impersonated_service_account)"'
keys=$( { printf '%s\n' "$added" | grep -v '^$' | tr '\n' '\0' \
              | xargs -0 -r git --literal-pathspecs grep --cached -I -l -z -E "$sa_key" -- 2>/dev/null
          printf '%s\n' "$worktree_files" | grep -v '^$' | tr '\n' '\0' \
              | xargs -0 -r grep -I -l -Z -E "$sa_key" -- 2>/dev/null; } | tr '\0' '\n' | sort -u)
while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\n' "$secrets" | grep -qxF "$f" && continue
    secrets="${secrets:+$secrets$'\n'}$f"
done <<< "$keys"
if [ -n "$secrets" ]; then
    refuse "Refused: this commit would add a secret or a database to the repository.

$secrets

Every .env holds JWT_SECRET and the cloud credentials; client_secret_*.json is the Google
OAuth client; data/zapzap.db holds every account and password hash. A *.jks / *.keystore
is the Android upload key and key.properties its passwords: whoever holds them can sign
an update of the app. A Google service-account key (\"type\": \"service_account\") acts
on the Cloud project and can publish to Play; application-default credentials
(authorized_user, external_account) act as whoever logged in. All are gitignored, so
reaching this point took a \`git add -f\` -- or a credential file under another name. Unstage with
\`git reset <path>\` and commit again. .env.example and
frontend-flutter/android/key.properties.template are the committed templates; the keys
live outside the repository (.llmwiki/FlutterAndroidPwa.md, Android)."
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
    [ "$branch" = "master" ] && is_project_repo "$ROOT" && refuse "Refused: committing directly on master.

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
# The price: clippy can check this tree's tests against a library another tree built
# into the same directory (#79: E0432/E0609 on correct code). So a failed clippy
# touches the crate's src/lib.rs in the tree being committed -- mtime only, never its
# content -- which makes cargo rebuild it from these sources, and runs once more.
run_clippy_gate() {  # name, crate directory under $ROOT, then the command
    local name="$1" crate="$2"; shift 2
    local output
    output=$("$@" 2>&1) && return 0
    touch -c "$ROOT/$crate/src/lib.rs"
    if ! output=$("$@" 2>&1); then
        refuse "Refused: \`$name\` fails, so this commit is not ready.

It failed twice: after the first failure the hook touched $crate/src/lib.rs (in case the
shared target directory held a stale build of it) and ran it again.

$(printf '%s\n' "$output" | tail -40)

Fix it, then commit again. Reproduce with: $name"
    fi
}

MAIN=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")

if printf '%s\n' "$paths" | grep -qE '^zapzap-rust/'; then
    command -v cargo >/dev/null 2>&1 || needs_setup "cargo is not on PATH" "install Rust with rustup (.llmwiki/Backend.md)"
    run_gate "cargo fmt --check (zapzap-rust)" bash -c "cd '$ROOT/zapzap-rust' && cargo fmt --check"
    run_clippy_gate "cargo clippy --locked --all-targets -- -D warnings (zapzap-rust)" zapzap-rust \
        env CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$MAIN/zapzap-rust/target}" bash -c "cd '$ROOT/zapzap-rust' && cargo clippy --locked --all-targets --quiet -- -D warnings"
fi

if printf '%s\n' "$paths" | grep -qE '^native/'; then
    command -v cargo >/dev/null 2>&1 || needs_setup "cargo is not on PATH" "install Rust with rustup (.llmwiki/NativeEngine.md)"
    run_gate "cargo fmt --check (native)" bash -c "cd '$ROOT/native' && cargo fmt --check"
    run_clippy_gate "cargo clippy --all-targets -- -D warnings (native)" native \
        env CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$MAIN/native/target}" bash -c "cd '$ROOT/native' && cargo clippy --all-targets --quiet -- -D warnings"
fi

# The client gate runs only for a file the commit leaves in the tree and that is not a
# `.md`: a README edit or a deletion cannot break the analyzer, so it runs no gate and
# needs no setup.
gate_paths() {  # directory
    printf '%s\n' "$paths" | grep -E "^$1/" | grep -vE '\.md$' \
        | while read -r f; do [ -e "$ROOT/$f" ] && echo "$f"; done
}

# The Flutter client: the formatter and the analyzer only (seconds); tests and builds are
# the `flutter` CI job. An offline pub get (no network, from the pub cache the setup
# filled) follows a pubspec change. The generated lib/l10n/app_localizations*.dart are not committed and go
# stale with every ARB change; neither `flutter analyze` nor a pub get that finds nothing
# to resolve regenerates them, so `flutter gen-l10n` does, before the analyzer runs.
if [ -n "$(gate_paths frontend-flutter)" ]; then
    command -v flutter >/dev/null 2>&1 || needs_setup "flutter is not on PATH" "install Flutter 3.47.2 (.llmwiki/FrontendFlutter.md), then: cd $ROOT/frontend-flutter && flutter pub get"
    [ -d "$ROOT/frontend-flutter/.dart_tool" ] || needs_setup "frontend-flutter/.dart_tool is missing (flutter pub get never ran in this tree)" "cd $ROOT/frontend-flutter && flutter pub get"
    run_gate "flutter pub get --offline (frontend-flutter; if a package is missing from the cache: cd $ROOT/frontend-flutter && flutter pub get)" \
        bash -c "cd '$ROOT/frontend-flutter' && flutter pub get --offline"
    # A pubspec change whose lock pub get rewrites would commit a lock that does not match
    # it; CI's `--enforce-lockfile` would catch it, a push later. Under -a the rewritten
    # lock is staged with the rest, so only a lock left unstaged is refused.
    lock="frontend-flutter/pubspec.lock"
    if [ "$commit_all" != "true" ] && git ls-files --error-unmatch "$lock" >/dev/null 2>&1 \
        && ! git diff --quiet -- "$lock" 2>/dev/null; then
        refuse "Refused: \`flutter pub get\` changed $lock, and the change is not staged.

The lock this commit carries would not match its pubspec.yaml, and CI's
\`flutter pub get --enforce-lockfile\` fails on it. Review the change, then:
    git -C $ROOT add $lock
and commit again."
    fi
    if [ -f "$ROOT/frontend-flutter/l10n.yaml" ]; then
        run_gate "flutter gen-l10n (frontend-flutter)" bash -c "cd '$ROOT/frontend-flutter' && flutter gen-l10n"
    fi
    # The formatter over the whole of lib/ and test/ (and integration_test/ when it
    # exists), not only the staged files: under a second, and drift another commit let
    # through is caught too. The same command is a step of the `flutter` CI job.
    run_gate "dart format --output=none --set-exit-if-changed lib test (frontend-flutter; to fix: cd $ROOT/frontend-flutter && dart format lib test)" \
        bash -c "cd '$ROOT/frontend-flutter' && dart format --output=none --set-exit-if-changed lib test \$([ -d integration_test ] && echo integration_test)"
    run_gate "flutter analyze (frontend-flutter)" bash -c "cd '$ROOT/frontend-flutter' && flutter analyze"
fi

exit 0
