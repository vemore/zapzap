#!/bin/bash

# ZapZap - Claude Code hooks self-test
#
# The guards decide from a parsed command line, and the interesting cases are the
# ones that look like a violation and are not (a heredoc documenting `pkill node`,
# `git commit -m "git push --force"`) or the reverse (`git commit -am` with nothing
# staged). This table is the only way to exercise them offline, in seconds.
#
# Usage: scripts/hooks_selftest.sh        (exit 0 = every case behaves)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$ROOT/.claude/hooks"
export CLAUDE_PROJECT_DIR="$ROOT"

pass=0
fail=0

report() {  # description, expected, actual
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf '  FAIL  %s\n        expected %s, got %s\n' "$1" "$2" "$3"
    fi
}

payload() {  # command, [cwd]
    python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2],"hook_event_name":"PreToolUse","tool_name":"Bash"}))' \
        "$1" "${2:-$ROOT}"
}

guard() {  # description, expected exit, command, [cwd]
    local out
    out=$(payload "$3" "${4:-$ROOT}" | "$HOOKS/guard-bash.sh" 2>/dev/null)
    report "$1" "$2" "$?"
}

commit_field() {  # description, expected, field, command
    local got
    got=$(payload "$4" | CLAUDE_PROJECT_DIR="$ROOT" python3 "$HOOKS/parse_command.py" | jq -r "$3")
    report "$1" "$2" "$got"
}

echo "== refusals =================================================="
guard "pkill -9 -f node kills VS Code under WSL"    2 'pkill -9 -f "node"'
guard "killall node"                                2 'killall -9 node'
guard "pkill -f node app.js"                        2 'pkill -f "node app.js"'
guard "pkill of a named process is fine"            0 'pkill -f nodemon'
guard "killing a port is the alternative"           0 'lsof -ti:9999 | xargs kill 2>/dev/null'
guard "the words inside an echo (pkill)"            0 'echo "pkill -9 -f node"'
guard "a heredoc body that documents the command"   0 "$(printf 'cat > /tmp/x <<%sEOF%s\npkill -9 -f node\ngit push --force\nEOF\n' "'" "'")"
guard "an unparseable command fails open"           0 'echo "unbalanced'
guard "a pull request aimed at master"                 0 'gh pr create --base master --head x --title t --body b'
guard "a pull request stacked on another branch"    2 'gh pr create --base feat/other --head x --title t'
guard "the same, written --base=x"                  2 'gh pr create --base=feat/other --title t'
guard "no --base means the repository default"      0 'gh pr create --title t --body b'
guard "reading pull requests is not creating one"   0 'gh pr list --state merged'
guard "a squash merge"                              0 'gh pr merge 12 --squash --delete-branch'
guard "a squash merge, short flags"                 0 'gh pr merge 12 -sd'
guard "--admin bypasses the protection"             2 'gh pr merge 12 --squash --admin'
guard "a merge with no method prompts"              2 'gh pr merge 12'
guard "a rebase merge"                              2 'gh pr merge 12 --rebase'
guard "the words inside an echo (merge)"            0 'echo "gh pr merge 12 --admin"'
guard "pushing a branch"                            0 'git push -u origin feat/x'
guard "a force-push"                                2 'git push --force origin feat/x'
guard "a force-push, bundled short flag"            2 'git push -fu origin feat/x'
guard "a force-with-lease is still a force-push"    2 'git push --force-with-lease origin feat/x'
guard "a +refspec is a force-push"                  2 'git push origin +feat/x'
guard "pushing master by name"                      2 'git push origin master'
guard "pushing HEAD onto master"                      2 'git push origin HEAD:master'
guard "the words inside an echo (push)"             0 'echo "git push --force origin master"'


echo "== commit detection =========================================="
commit_field "plain commit"                    false '.commit.all'   'git commit -m x'
commit_field "commit -am stages tracked files" true  '.commit.all'   'git commit -am wip'
commit_field "--amend rewrites the last one"   true  '.commit.amend' 'git commit --amend --no-edit'
commit_field "git -C still commits"            false '.commit.all'   'git -C frontend commit -m x'
commit_field "commit after add in one line"    false '.commit.all'   'git add -A && git commit -m "x"'
commit_field "a trailing pathspec"    'zapzap-rust/src/lib.rs' '.commit.pathspecs[0]' 'git commit -m x zapzap-rust/src/lib.rs'
commit_field "--dry-run runs no gates"          null '.commit'       'git commit --dry-run'
commit_field "git log is not a commit"          null '.commit'       'git log --grep=commit'
commit_field "git status is not a commit"       null '.commit'       'git status'
commit_field "the word in an echo"              null '.commit'       'echo "git commit"'
commit_field "unparseable assumes a commit"    true  '.commit.all'   'git commit -m "unbalanced'
commit_field "the commit runs where cd left it" /tmp '.commit.cwd'  'cd /tmp && git commit -m x'
commit_field "git -C moves the commit"      "$(dirname "$ROOT")/wt" '.commit.cwd' 'git -C ../wt commit -m x'
commit_field 'a commit after $(...); is still seen' false '.commit.all' 'X=$(date); git commit -m x'


SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

echo "== branch discipline ========================================="
REMOTE="$SANDBOX/remote.git"
WORK="$SANDBOX/work"
git init -q --bare "$REMOTE"
git clone -q "$REMOTE" "$WORK" 2>/dev/null
git -C "$WORK" config user.email t@t
git -C "$WORK" config user.name t
git -C "$WORK" commit -q --allow-empty -m "base"
git -C "$WORK" branch -M master
git -C "$WORK" push -q -u origin master 2>/dev/null

branch_case() {  # description, expected exit
    local out
    out=$(payload "git commit -m x" "$WORK" | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>/dev/null)
    report "$1" "$2" "$?"
}

branch_case "committing on master" 2

git -C "$WORK" switch -qc feat/live origin/master
branch_case "a fresh branch off origin/master" 0

git -C "$WORK" commit -q --allow-empty -m "work"
git -C "$WORK" push -q -u origin feat/live 2>/dev/null
git -C "$REMOTE" branch -D feat/live >/dev/null 2>&1
git -C "$WORK" fetch -q --prune origin 2>/dev/null
branch_case "a branch whose remote was merged and deleted" 2

# A commit that also reached origin/master under a different hash -- what a merged
# branch looks like once the remote has moved on.
git -C "$WORK" switch -qc feat/picked origin/master
echo dup > "$WORK/dup.txt"
git -C "$WORK" add dup.txt
git -C "$WORK" commit -qm "add dup"
git -C "$WORK" switch -q master
git -C "$WORK" cherry-pick feat/picked >/dev/null 2>&1
# Same patch, different hash -- as a rebase-merge leaves it upstream.
git -C "$WORK" commit -q --amend -m "add dup (upstream)"
git -C "$WORK" push -q origin master 2>/dev/null
git -C "$WORK" switch -q feat/picked
branch_case "a branch replaying a commit already upstream" 2

git -C "$WORK" checkout -q --detach origin/master
branch_case "a detached HEAD" 2

# A worktree on its own branch, while the checkout the session was launched from
# sits on master: the commit must be judged on the worktree's branch.
git -C "$WORK" switch -q master
TREE="$SANDBOX/tree"
git -C "$WORK" worktree add -q -b feat/in-tree "$TREE" origin/master 2>/dev/null
out=$(payload "git commit -m x" "$TREE" | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>/dev/null)
report "a commit inside a worktree, launch checkout on master" 0 "$?"
out=$(payload "cd $TREE && git commit -m x" "$WORK" | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>/dev/null)
report "cd into a worktree, then commit" 0 "$?"
out=$(payload "git -C $TREE commit -m x" "$WORK" | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>/dev/null)
report "git -C a worktree commit" 0 "$?"
out=$(payload "git commit -m x" "$WORK" | CLAUDE_PROJECT_DIR="$TREE" "$HOOKS/guard-bash.sh" 2>/dev/null)
report "the launch checkout on master is still refused" 2 "$?"
out=$(payload "git push" "$WORK" | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>/dev/null)
report "a bare push from master" 2 "$?"
out=$(payload "git push" "$TREE" | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>/dev/null)
report "a bare push from a worktree branch" 0 "$?"

# The guard must know which repository a commit or a bare push runs in; when it
# cannot -- a line it fails to parse, a `cd $W` / `git -C $W` it cannot expand --
# it refuses, and says so, rather than judge the launch checkout on master and point
# at a stale-branch recovery (a countscore incident, 2026-09-18).
said() {  # description, expected verdict, command, [payload cwd]
    local err rc got
    err=$(payload "$3" "${4:-$WORK}" | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>&1 >/dev/null)
    rc=$?
    case "$rc:$err" in
        0:*) got=pass ;;
        2:*"could not tell which repository"*) got=unknown ;;
        2:*) got=judged ;;
        *) got="exit $rc" ;;
    esac
    report "$1" "$2" "$got"
}
said "same-line W=<tree>; cd \$W, then commit"      pass    "W=$TREE; cd \$W && git commit -m x"
said "same-line W=<tree>; git -C \$W commit + push (b)" pass \
    "W=$TREE; git -C \$W add .llmwiki/INDEX.md && git -C \$W commit -q --no-edit 2>&1 | tail -5; git -C \$W push -q 2>&1 | tail -2; git -C \$W log --oneline -1"
said "same-line W=<tree>; cd \$W, heredoc, git -C \$W push (a)" pass \
    "$(printf 'W=%s; cd $W && python3 - <<%sPY%s\nprint(1)\nPY\ngit -C $W add x && git -C $W commit -q --no-edit && git -C $W push -q 2>&1 | tail -2' "$TREE" "'" "'")"
said "same-line W=<tree>; git -C \$W commit -F - heredoc" pass \
    "$(printf 'W=%s; git -C $W commit -F - <<%sEOF%s\ndocs: x\nEOF' "$TREE" "'" "'")"
said "export W=\"<tree>\" then git -C \"\${W}\" push" pass   "export W=\"$TREE\"; git -C \"\${W}\" push -q"

# Work tracking: wip/ is local and gitignored; only `git add -f` stages it.
mkdir -p "$TREE/wip/todo" && echo "# entry" > "$TREE/wip/todo/2026-09-22-x.md"
git -C "$TREE" add -f wip
out=$(payload "git commit -m x" "$TREE" | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>/dev/null)
report "a wip/ entry forced into a commit" 2 "$?"
git -C "$TREE" rm -rq --cached wip && rm -rf "$TREE/wip"
echo "- [ ] x" > "$TREE/TODO.md"
git -C "$TREE" add TODO.md
out=$(payload "git commit -m x" "$TREE" | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>/dev/null)
report "a TODO.md brought back" 2 "$?"
git -C "$TREE" rm -q --cached TODO.md && rm "$TREE/TODO.md"

# Secrets and the database.
secret_case() {  # description, expected exit, path
    mkdir -p "$TREE/$(dirname "$3")" && echo x > "$TREE/$3"
    git -C "$TREE" add -f "$3"
    out=$(payload "git commit -m x" "$TREE" | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>/dev/null)
    report "$1" "$2" "$?"
    git -C "$TREE" rm -q --cached "$3" && rm "$TREE/$3"
}
secret_case "a staged .env"                        2 ".env"
secret_case "a staged .env.production"             2 ".env.production"
secret_case "the committed template"               0 ".env.example"
secret_case "the Google OAuth client"              2 "src/infrastructure/auth/client_secret_123.json"
secret_case "the SQLite database"                  2 "data/zapzap.db"
secret_case "a backup of the database"            2 "data/zapzap.db.bak-2026-09-22-1356"
secret_case "an ordinary JSON file"                0 "data/thibot_genetic_params.json"
# Untracking the database is a deletion, not a leak.
echo x > "$TREE/data.db" && git -C "$TREE" add -f data.db
git -C "$TREE" -c user.email=t@t -c user.name=t commit -qm "db" >/dev/null 2>&1
git -C "$TREE" rm -q --cached data.db
out=$(payload "git commit -m x" "$TREE" | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>/dev/null)
report "git rm --cached of a database" 0 "$?"
git -C "$TREE" reset -q --hard HEAD~1 2>/dev/null; rm -f "$TREE/data.db"

# Gates: which paths select them, and a missing setup named with its command. A stub
# cargo/npm/flutter on PATH decides pass or fail, so no real build runs.
TOOLS="$SANDBOX/tools"
mkdir -p "$TOOLS"
stub_tool() {  # name, exit code
    printf '#!/bin/sh\necho "stub %s $*"\nexit %s\n' "$1" "$2" > "$TOOLS/$1"
    chmod +x "$TOOLS/$1"
}
tree_commit() {  # description, expected exit, [text the refusal must contain]
    local err rc
    err=$(payload "git commit -m x" "$TREE" | PATH="$TOOLS:$PATH" CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>&1 >/dev/null)
    rc=$?
    [ -n "${3:-}" ] && [[ "$err" != *"$3"* ]] && rc="$rc without '$3'"
    report "$1" "$2" "$rc"
}
stage() { mkdir -p "$TREE/$(dirname "$1")" && echo x > "$TREE/$1" && git -C "$TREE" add "$1"; }
unstage() { git -C "$TREE" rm -q --cached "$1" && rm -rf "$TREE/${1%%/*}"; }

stub_tool cargo 0
stage "zapzap-rust/src/lib.rs"
tree_commit "a backend change with green cargo gates" 0
stub_tool cargo 1
tree_commit "a backend change with a red cargo gate" 2 "cargo fmt --check (zapzap-rust)"
unstage "zapzap-rust/src/lib.rs"
stage "native/src/lib.rs"
tree_commit "a native change with a red cargo fmt" 2 "cargo fmt --check (native)"
unstage "native/src/lib.rs"
stage "src/api/app.js"
tree_commit "the legacy Node backend runs no gate" 0
unstage "src/api/app.js"
stage "frontend/src/App.jsx"
tree_commit "a frontend change in a tree never set up" 2 "npm ci --prefix"
mkdir -p "$TREE/frontend/node_modules"
stub_tool npm 0
tree_commit "a frontend change whose build passes" 0
stub_tool npm 1
tree_commit "a frontend change whose build fails" 2 "npm run build (frontend)"
git -C "$TREE" rm -q --cached frontend/src/App.jsx && rm -rf "$TREE/frontend"
# The Flutter client. npm and cargo stay red from here on: a frontend-flutter/ change must
# not select the frontend/ gate (`^frontend/` needs the slash) nor a cargo one.
stub_flutter() {  # pub get exit code, analyze exit code
    printf '#!/bin/sh\necho "stub flutter $*"\ncase "$1" in\n    pub) exit %s ;;\n    analyze) echo "error - invalid_assignment - lib/main.dart:9:9"; exit %s ;;\nesac\nexit 0\n' "$1" "$2" > "$TOOLS/flutter"
    chmod +x "$TOOLS/flutter"
}
stub_flutter 0 0
stage "frontend-flutter/lib/main.dart"
tree_commit "a Flutter change in a tree never set up" 2 "cd $TREE/frontend-flutter && flutter pub get"
mkdir -p "$TREE/frontend-flutter/.dart_tool" && touch "$TREE/frontend-flutter/l10n.yaml"
tree_commit "a Flutter change whose analyzer is clean" 0
stub_flutter 0 1
tree_commit "a Flutter change with an analyzer error" 2 "flutter analyze (frontend-flutter)"
stub_flutter 1 0
tree_commit "a Flutter change whose offline pub get fails" 2 "cd $TREE/frontend-flutter && flutter pub get"
unstage "frontend-flutter/lib/main.dart"
stub_tool cargo 1
stage "README.md"
tree_commit "a documentation change runs no gate" 0
unstage "README.md"

echo "== pull request ==============================================="
stop_case() {  # description, expected (silent|block), [stop_hook_active]
    local out got
    out=$(printf '{"hook_event_name":"Stop","stop_hook_active":%s}' "${3:-false}" \
          | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/require-pull-request.sh" 2>/dev/null)
    case "$out" in
        "")       got=silent ;;
        *'"block"'*) got=block ;;
        *)        got="unexpected: $out" ;;
    esac
    report "$1" "$2" "$got"
}

git -C "$WORK" switch -q master
stop_case "nothing to publish from master" silent

# Stacking stays possible, per repository and on purpose.
out=$(payload "gh pr create --base feat/other --title t" "$WORK" \
      | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>/dev/null)
report "stacking is refused by default" 2 "$?"
git -C "$WORK" config zapzap.allowStackedPr true
out=$(payload "gh pr create --base feat/other --title t" "$WORK" \
      | CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>/dev/null)
report "stacking unlocked for this repository" 0 "$?"
git -C "$WORK" config --unset zapzap.allowStackedPr

git -C "$WORK" switch -qc feat/quiet origin/master
stop_case "a branch with no commits of its own" silent

git -C "$WORK" commit -q --allow-empty -m "work in progress"
stop_case "a local-only remote is not a forge" silent

git -C "$WORK" remote set-url origin https://github.com/example/does-not-exist.git

# A stubbed `gh` makes every state testable offline, including in CI. The real one
# only ever answered "open or nothing", which is how a merged pull request came to
# block a turn forever.
STUB="$SANDBOX/stub"
mkdir -p "$STUB"
stub_gh() {  # pr-list line, pr-checks lines
    cat > "$STUB/gh" <<STUBEOF
#!/bin/bash
case "\$1 \$2" in
    "auth status") exit 0 ;;
    "pr list")     printf '%s' '$1'; [ -n '$1' ] && echo ;;
    "pr checks")   printf '%b' '${2:-}' ;;
esac
exit 0
STUBEOF
    chmod +x "$STUB/gh"
}

stopped() {  # description, expected, [stop_hook_active]
    local out got
    out=$(printf '{"hook_event_name":"Stop","stop_hook_active":%s}' "${3:-false}" \
          | PATH="$STUB:$PATH" CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/require-pull-request.sh" 2>/dev/null)
    case "$out" in
        "")          got=silent ;;
        *'"block"'*) got=block ;;
        *)           got="unexpected: $out" ;;
    esac
    report "$1" "$2" "$got"
}

stub_gh ""
stopped "commits with no pull request" block
stopped "already asked, do not loop" silent true

stub_gh "5 MERGED https://example.invalid/5"
stopped "the pull request was merged" silent

stub_gh "5 CLOSED https://example.invalid/5"
stopped "the pull request was closed unmerged" block

stub_gh "5 OPEN https://example.invalid/5" "App\tpass\t2m\thttps://example.invalid/j1\n"
stopped "an open pull request whose checks pass" silent

stub_gh "5 OPEN https://example.invalid/5" "App\tfail\t2m\thttps://example.invalid/j1\n"
stopped "an open pull request with a failing check" block

stub_gh "5 OPEN https://example.invalid/5" "App\tpending\t0\thttps://example.invalid/j1\n"
stopped "checks still running are not a failure" silent

git -C "$WORK" config branch.feat/quiet.noPullRequest true
stub_gh ""
stopped "a branch deliberately not published" silent
git -C "$WORK" config --unset branch.feat/quiet.noPullRequest

# A subagent in a worktree: its payload cwd is the worktree, CLAUDE_PROJECT_DIR is not.
git -C "$TREE" commit -q --allow-empty -m "agent work"
git -C "$WORK" switch -q master
stub_gh ""
out=$(printf '{"hook_event_name":"SubagentStop","stop_hook_active":false,"cwd":"%s"}' "$TREE" \
      | PATH="$STUB:$PATH" CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/require-pull-request.sh" 2>/dev/null)
case "$out" in *'"block"'*) got=block ;; "") got=silent ;; *) got="unexpected: $out" ;; esac
report "a subagent's worktree commits with no pull request" block "$got"

echo "== local cleanup ============================================="
# scripts/cleanup_local.sh deletes branches and worktrees, so every reason to keep one
# is exercised here, with a stubbed gh answering per branch.
CREMOTE="$SANDBOX/cleanup-remote.git"
CWORK="$SANDBOX/cleanup-work"
git init -q --bare "$CREMOTE"
git clone -q "$CREMOTE" "$CWORK" 2>/dev/null
git -C "$CWORK" config user.email t@t
git -C "$CWORK" config user.name t
git -C "$CWORK" commit -q --allow-empty -m base
git -C "$CWORK" branch -M master
# The setup marker is gitignored in the real repository, so a worktree carrying one is
# clean by `git status` -- reproduce that here, or the marker guard is never reached and
# the worktree is kept for the wrong reason.
echo "/.zapzap-setup-in-progress" > "$CWORK/.gitignore"
git -C "$CWORK" add .gitignore
git -C "$CWORK" commit -q -m "ignore the setup marker"
git -C "$CWORK" push -q -u origin master 2>/dev/null

cbranch() {  # name -- a branch with one commit of its own
    git -C "$CWORK" switch -qc "$1" origin/master
    git -C "$CWORK" commit -q --allow-empty -m "$1"
    git -C "$CWORK" switch -q master
}
git -C "$CWORK" branch worktree-agent1 origin/master          # Agent tool's placeholder
cbranch feat/merged
cbranch feat/merged-extra
cbranch feat/open
cbranch feat/nopr
git -C "$CWORK" worktree add -q "$SANDBOX/wt-merged" -b feat/wt-merged origin/master 2>/dev/null
git -C "$SANDBOX/wt-merged" commit -q --allow-empty -m wt
git -C "$CWORK" worktree add -q "$SANDBOX/wt-dirty" -b feat/wt-dirty origin/master 2>/dev/null
git -C "$SANDBOX/wt-dirty" commit -q --allow-empty -m wt
touch "$SANDBOX/wt-dirty/unsaved.txt"
# A worktree scripts/worktree_setup.sh is still building: clean, on a merged branch, and
# saved only by its marker -- the first run below has the modification-time guard off.
git -C "$CWORK" worktree add -q "$SANDBOX/wt-setup" -b feat/wt-setup origin/master 2>/dev/null
git -C "$SANDBOX/wt-setup" commit -q --allow-empty -m wt
echo "pid 1 started now branch feat/wt-setup" > "$SANDBOX/wt-setup/.zapzap-setup-in-progress"

CSTUB="$SANDBOX/cleanup-stub"
mkdir -p "$CSTUB"
cat > "$CSTUB/gh" <<'STUBEOF'
#!/bin/bash
args="$*"
head=""; [[ "$args" =~ --head\ ([^ ]+) ]] && head="${BASH_REMATCH[1]}"
case "$1 $2" in
    "auth status") exit 0 ;;
    "pr list")
        case "$args" in
            *"--state merged"*)
                case "$head" in
                    feat/merged|feat/merged-extra|feat/wt-merged|feat/wt-dirty) echo "cafe 7" ;;
                    feat/wt-setup|feat/wt-recent) echo "cafe 7" ;;
                    feat/wt-live|feat/wt-dead|feat/wt-reused|feat/wt-manual) echo "cafe 7" ;;
                esac ;;
            *) [ "$head" = feat/open ] && echo "#8 OPEN" ;;
        esac ;;
    "api "*)
        case "$args" in
            *"...$(git -C "$CLEANUP_WORK" rev-parse feat/merged-extra)"*) echo diverged ;;
            *compare*) echo behind ;;
        esac ;;
esac
exit 0
STUBEOF
chmod +x "$CSTUB/gh"

# These worktrees are seconds old, so the modification-time guard would keep every one of
# them: the assertions below only mean anything with the window closed.
(cd "$CWORK" && PATH="$CSTUB:$PATH" CLEANUP_WORK="$CWORK" CLEANUP_IDLE_MINUTES=0 \
    "$ROOT/scripts/cleanup_local.sh" --apply >/dev/null 2>&1)
has_branch() { git -C "$CWORK" rev-parse --verify -q "refs/heads/$1" >/dev/null && echo kept || echo removed; }
report "cleanup: Agent placeholder branch with no commit"      removed "$(has_branch worktree-agent1)"
report "cleanup: merged pull request, tip included"            removed "$(has_branch feat/merged)"
report "cleanup: merged, but local commits beyond the head"    kept    "$(has_branch feat/merged-extra)"
report "cleanup: open pull request"                            kept    "$(has_branch feat/open)"
report "cleanup: no pull request at all"                       kept    "$(has_branch feat/nopr)"
report "cleanup: clean worktree on a merged branch"            removed "$([ -d "$SANDBOX/wt-merged" ] && echo kept || echo removed)"
report "cleanup: its branch too"                               removed "$(has_branch feat/wt-merged)"
report "cleanup: worktree with unsaved work"                   kept    "$([ -d "$SANDBOX/wt-dirty" ] && echo kept || echo removed)"
report "cleanup: the branch of that worktree"                  kept    "$(has_branch feat/wt-dirty)"
report "cleanup: master"                                         kept    "$(has_branch master)"

# Second run, at the default window: a worktree an agent is still working in, with nothing
# committed and nothing uncommitted either, is only visible through its modification times.
git -C "$CWORK" worktree add -q "$SANDBOX/wt-recent" -b feat/wt-recent origin/master 2>/dev/null
git -C "$SANDBOX/wt-recent" commit -q --allow-empty -m wt
(cd "$CWORK" && PATH="$CSTUB:$PATH" CLEANUP_WORK="$CWORK" \
    "$ROOT/scripts/cleanup_local.sh" --apply >/dev/null 2>&1)
report "cleanup: worktree in setup (marker)"                   kept    "$([ -d "$SANDBOX/wt-setup" ] && echo kept || echo removed)"
report "cleanup: the branch of a worktree in setup"            kept    "$(has_branch feat/wt-setup)"
report "cleanup: recently modified worktree"                   kept    "$([ -d "$SANDBOX/wt-recent" ] && echo kept || echo removed)"

# Third run: worktree locks, as Claude Code writes them -- `claude agent <name> (pid N
# start T)`, T being field 22 of /proc/<pid>/stat. Every branch here is merged, so only
# the lock decides.
sleep 600 &
live_pid=$!
sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid"
live_start=$(cut -d' ' -f22 "/proc/$live_pid/stat" 2>/dev/null)
clock() {  # name, lock reason -- a clean worktree on a merged branch, locked
    git -C "$CWORK" worktree add -q "$SANDBOX/$1" -b "feat/$1" origin/master 2>/dev/null
    git -C "$SANDBOX/$1" commit -q --allow-empty -m wt
    git -C "$CWORK" worktree lock --reason "$2" "$SANDBOX/$1"
}
clock wt-live   "claude agent wt-live (pid $live_pid${live_start:+ start $live_start})"
clock wt-dead   "claude agent wt-dead (pid $dead_pid start 1)"
clock wt-manual "kept on purpose"
# A live pid that started at another time was recycled: the session that locked it is gone.
[ -n "$live_start" ] && clock wt-reused "claude agent wt-reused (pid $live_pid start 1)"
dry=$(cd "$CWORK" && PATH="$CSTUB:$PATH" CLEANUP_WORK="$CWORK" CLEANUP_IDLE_MINUTES=0 \
    "$ROOT/scripts/cleanup_local.sh" 2>&1)
line() { printf '%s\n' "$dry" | grep -F "$SANDBOX/$1 " | head -1; }
case "$(line wt-live)" in
    *"keep "*"locked by a running session (pid $live_pid)"*) got=kept-named ;; *) got="$(line wt-live)" ;; esac
report "cleanup dry run: locked by a live session, pid named"   kept-named "$got"
case "$(line wt-dead)" in
    *"would remove"*"stale lock, pid $dead_pid is gone"*) got=stale ;; *) got="$(line wt-dead)" ;; esac
report "cleanup dry run: locked by a dead pid, said stale"      stale "$got"
case "$(line wt-manual)" in
    *"keep "*"locked: kept on purpose"*) got=kept ;; *) got="$(line wt-manual)" ;; esac
report "cleanup dry run: a lock naming no pid"                   kept "$got"
(cd "$CWORK" && PATH="$CSTUB:$PATH" CLEANUP_WORK="$CWORK" CLEANUP_IDLE_MINUTES=0 \
    "$ROOT/scripts/cleanup_local.sh" --apply >/dev/null 2>&1)
kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null
report "cleanup: worktree locked by a live session"             kept    "$([ -d "$SANDBOX/wt-live" ] && echo kept || echo removed)"
report "cleanup: the branch of that worktree"                   kept    "$(has_branch feat/wt-live)"
report "cleanup: worktree with a stale lock"                    removed "$([ -d "$SANDBOX/wt-dead" ] && echo kept || echo removed)"
report "cleanup: the branch of that worktree"                   removed "$(has_branch feat/wt-dead)"
report "cleanup: worktree locked by hand"                       kept    "$([ -d "$SANDBOX/wt-manual" ] && echo kept || echo removed)"
if [ -n "$live_start" ]; then
    report "cleanup: lock whose pid was recycled"               removed "$([ -d "$SANDBOX/wt-reused" ] && echo kept || echo removed)"
fi

# A removal git refuses is reported with git's own error, not a bare FAILED: a worktree
# the script cannot delete (its parent directory read-only) stands in for any such refusal.
git -C "$CWORK" worktree add -q "$SANDBOX/ro/wt-fail" -b feat/wt-fail origin/master 2>/dev/null
chmod a-w "$SANDBOX/ro"
out=$(cd "$CWORK" && PATH="$CSTUB:$PATH" CLEANUP_WORK="$CWORK" CLEANUP_IDLE_MINUTES=0 \
    "$ROOT/scripts/cleanup_local.sh" --apply 2>&1)
chmod u+w "$SANDBOX/ro"
if [ "$(id -u)" != 0 ]; then
    case "$out" in
        *"FAILED   $SANDBOX/ro/wt-fail"*$'\n'"           "*[a-z]*) got=explained ;; *) got="$out" ;; esac
    report "cleanup --apply: a failed removal prints git's error" explained "$got"
fi

echo "== wiring ===================================================="
# wip/ lives in the main checkout: found from its root, a subdirectory and a worktree.
WIPREPO="$SANDBOX/wiprepo"
git init -q "$WIPREPO" && mkdir -p "$WIPREPO/scripts" "$WIPREPO/sub/dir"
cp "$ROOT/scripts/wip.sh" "$WIPREPO/scripts/"
git -C "$WIPREPO" add -A && git -C "$WIPREPO" -c user.email=t@t -c user.name=t commit -qm init
git -C "$WIPREPO" worktree add -q "$SANDBOX/wipwt" 2>/dev/null
report "wip.sh path from the main checkout"   "$WIPREPO/wip" "$(cd "$WIPREPO" && scripts/wip.sh path)"
report "wip.sh path from a subdirectory"      "$WIPREPO/wip" "$(cd "$WIPREPO/sub/dir" && ../../scripts/wip.sh path)"
report "wip.sh path from a worktree"          "$WIPREPO/wip" "$(cd "$SANDBOX/wipwt" && scripts/wip.sh path)"

# worktree_setup.sh fetches the Flutter packages when the tree has the client, and a stub
# flutter records how it was called.
mkdir -p "$WIPREPO/frontend-flutter" && touch "$WIPREPO/frontend-flutter/pubspec.yaml"
cp "$ROOT/scripts/worktree_setup.sh" "$WIPREPO/scripts/"
printf '#!/bin/sh\necho "$*" >> "%s/flutter.log"\n' "$SANDBOX" > "$TOOLS/flutter" && chmod +x "$TOOLS/flutter"
(cd "$WIPREPO" && PATH="$TOOLS:$PATH" scripts/worktree_setup.sh --no-frontend --no-rust >/dev/null 2>&1)
report "worktree_setup.sh runs flutter pub get"  "pub get" "$(cat "$SANDBOX/flutter.log" 2>/dev/null)"
rm -f "$SANDBOX/flutter.log"
(cd "$WIPREPO" && PATH="$TOOLS:$PATH" scripts/worktree_setup.sh --no-frontend --no-rust --no-flutter >/dev/null 2>&1)
report "worktree_setup.sh --no-flutter skips it" "none" "$(cat "$SANDBOX/flutter.log" 2>/dev/null || echo none)"

for script in "$HOOKS"/*.sh "$HOOKS"/*.py; do
    [ -x "$script" ] && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "  FAIL  $script is not executable"; }
done
python3 -m json.tool "$ROOT/.claude/settings.json" >/dev/null 2>&1
report "settings.json is valid JSON" 0 "$?"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
