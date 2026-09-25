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

# Sandbox repositories: an agent testing a script builds throwaway ones, and their master
# is nobody's. The two master rules lift there -- CLAUDE_PROJECT_DIR is this project here
# -- and nowhere else: a clone of this project, its remote under another URL form, a path
# to its own checkout, or a remote or directory the guard cannot tell stay refused.
SBARE="$SANDBOX/scratch-remote.git"
SCLONE="$SANDBOX/scratch-clone"
git init -q --bare "$SBARE"
git clone -q "$SBARE" "$SCLONE" 2>/dev/null
git -C "$SCLONE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "$SCLONE" branch -M master
git -C "$SCLONE" push -q -u origin master 2>/dev/null
guard "sandbox: push HEAD:refs/heads/master into a bare repo" 0 "git push -q origin HEAD:refs/heads/master" "$SCLONE"
guard "sandbox: the same through cd && git -C"           0 "cd $SCLONE && git -C $SCLONE push -q origin HEAD:master"
guard "sandbox: pushing master to the bare repo by path" 0 "git push $SBARE master" "$SCLONE"
guard "sandbox: a bare push from its master"             0 "git push" "$SCLONE"
guard "sandbox: committing on its master"                0 "git commit -m x" "$SCLONE"
guard "sandbox: cd, then git -C commit on its master"    0 "cd $SCLONE && git -C $SCLONE commit -q -m x"
guard "project: push HEAD:refs/heads/master"             2 "git push origin HEAD:refs/heads/master"
guard "project: a sandbox pushing into its checkout"     2 "git push $ROOT HEAD:master" "$SCLONE"
guard "project: a remote the guard cannot resolve"       2 'git push $R HEAD:master' "$SCLONE"
guard "project: a directory the guard cannot tell"       2 'cd $D && git push origin HEAD:master' "$SCLONE"
if project_url=$(git -C "$ROOT" remote get-url origin 2>/dev/null); then
    PCLONE="$SANDBOX/project-clone"
    git init -q "$PCLONE"
    git -C "$PCLONE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
    git -C "$PCLONE" branch -M master
    git -C "$PCLONE" remote add origin "$project_url"
    git -C "$PCLONE" update-ref refs/remotes/origin/master HEAD
    guard "project: committing on master in another clone" 2 "git commit -m x" "$PCLONE"
    guard "project: a bare push from that clone's master"  2 "git push" "$PCLONE"
    # github.com/owner/repo, whichever form origin is written in
    key=$(printf '%s' "$project_url" | sed -E 's#^[a-z+]+://##; s#^[^@/]*@##; s#^([^/:]+):#\1/#; s#\.git$##')
    guard "project: its remote as an https URL"  2 "git push https://${key}.git HEAD:master" "$SCLONE"
    guard "project: its remote as an ssh URL"    2 "git push git@${key/\//:}.git HEAD:master" "$SCLONE"
fi

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
# cargo/npm/flutter/dart on PATH decides pass or fail, so no real build runs.
TOOLS="$SANDBOX/tools"
mkdir -p "$TOOLS"
stub_tool() {  # name, exit code
    printf '#!/bin/sh\necho "stub %s $*"\nexit %s\n' "$1" "$2" > "$TOOLS/$1"
    chmod +x "$TOOLS/$1"
}
tree_commit() {  # description, expected exit, [text the refusal must contain]
    local err rc
    err=$(payload "${GATE_COMMAND:-git commit -m x}" "$TREE" | PATH="${GATE_PATH:-$TOOLS:$PATH}" CLAUDE_PROJECT_DIR="$WORK" "$HOOKS/guard-bash.sh" 2>&1 >/dev/null)
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
# A cargo that passes fmt and fails clippy: the native gate must run clippy too.
printf '#!/bin/sh\necho "stub cargo $*"\ncase "$*" in *clippy*) exit 1 ;; esac\nexit 0\n' > "$TOOLS/cargo"
tree_commit "a native change with a red cargo clippy" 2 "cargo clippy --all-targets -- -D warnings (native)"
stub_tool cargo 0
tree_commit "a native change with green cargo gates" 0
stub_tool cargo 1
unstage "native/src/lib.rs"
stage "src/api/app.js"
tree_commit "the legacy Node backend runs no gate" 0
unstage "src/api/app.js"
# A README edit or a deletion cannot break lint or build, so neither needs node_modules.
stage "frontend/README.md"
tree_commit "a frontend README-only commit, tree never set up" 0
unstage "frontend/README.md"
stage "frontend/src/old.jsx"
git -C "$TREE" -c user.email=t@t -c user.name=t commit -qm "old.jsx" >/dev/null 2>&1
git -C "$TREE" rm -rq frontend
tree_commit "a frontend deletion-only commit, tree never set up" 0
git -C "$TREE" reset -q --hard HEAD~1 2>/dev/null
stage "frontend/src/App.jsx"
tree_commit "a frontend change in a tree never set up" 2 "npm ci --prefix"
mkdir -p "$TREE/frontend/node_modules"
stub_npm() {  # lint exit code, build exit code
    printf '#!/bin/sh\necho "stub npm $*"\ncase "$2" in\n    lint) exit %s ;;\n    build) exit %s ;;\nesac\nexit 0\n' "$1" "$2" > "$TOOLS/npm"
    chmod +x "$TOOLS/npm"
}
stub_npm 0 0
tree_commit "a frontend change whose lint and build pass" 0
stub_npm 1 0
tree_commit "a frontend change whose lint fails" 2 "npm run lint (frontend)"
stub_npm 0 1
tree_commit "a frontend change whose build fails" 2 "npm run build (frontend)"
stub_tool npm 1
git -C "$TREE" rm -q --cached frontend/src/App.jsx && rm -rf "$TREE/frontend"
# The Flutter client. npm and cargo stay red from here on: a frontend-flutter/ change must
# not select the frontend/ gate (`^frontend/` needs the slash) nor a cargo one.
stub_flutter() {  # pub get exit code, analyze exit code, [gen-l10n exit code], [1: pub get rewrites the lock]
    printf '#!/bin/sh\necho "stub flutter $*"\ncase "$1" in\n    pub) [ "%s" = 1 ] && echo "changed" >> pubspec.lock; exit %s ;;\n    analyze) echo "error - invalid_assignment - lib/main.dart:9:9"; exit %s ;;\n    gen-l10n) exit %s ;;\nesac\nexit 0\n' "${4:-0}" "$1" "$2" "${3:-0}" > "$TOOLS/flutter"
    chmod +x "$TOOLS/flutter"
}
# No flutter anywhere on PATH, the machine's own included: the stub is removed and every
# directory holding one is dropped.
NOFLUTTER_PATH=$(printf '%s' "$PATH" | tr ':' '\n' | while read -r d; do [ -x "$d/flutter" ] || echo "$d"; done | paste -sd:)
# A README edit or a deletion cannot break the analyzer, so neither needs flutter.
stage "frontend-flutter/README.md"
GATE_PATH="$NOFLUTTER_PATH" tree_commit "a Flutter README-only commit, no flutter, tree never set up" 0
unstage "frontend-flutter/README.md"
stage "frontend-flutter/lib/old.dart"
git -C "$TREE" -c user.email=t@t -c user.name=t commit -qm "old.dart" >/dev/null 2>&1
git -C "$TREE" rm -rq frontend-flutter
GATE_PATH="$NOFLUTTER_PATH" tree_commit "a Flutter deletion-only commit, no flutter, tree never set up" 0
git -C "$TREE" reset -q --hard HEAD~1 2>/dev/null
stage "frontend-flutter/lib/main.dart"
GATE_PATH="$NOFLUTTER_PATH" tree_commit "a Flutter code change with no flutter on PATH" 2 "flutter is not on PATH"
stub_flutter 0 0
stub_tool dart 0
tree_commit "a Flutter change in a tree never set up" 2 "cd $TREE/frontend-flutter && flutter pub get"
mkdir -p "$TREE/frontend-flutter/.dart_tool" && touch "$TREE/frontend-flutter/l10n.yaml"
tree_commit "a Flutter change whose analyzer is clean" 0
stub_flutter 0 1
tree_commit "a Flutter change with an analyzer error" 2 "flutter analyze (frontend-flutter)"
stub_tool dart 1
stub_flutter 0 0
tree_commit "a Flutter change with an unformatted Dart file" 2 "dart format --output=none --set-exit-if-changed lib test (frontend-flutter"
stub_tool dart 0
stub_flutter 1 0
tree_commit "a Flutter change whose offline pub get fails" 2 "cd $TREE/frontend-flutter && flutter pub get"
stub_flutter 0 0 1
tree_commit "a Flutter change whose gen-l10n fails" 2 "flutter gen-l10n (frontend-flutter)"
# A pubspec change whose lock pub get rewrites: the lock left unstaged is refused; under -a
# it is staged with the rest.
stage "frontend-flutter/pubspec.yaml"
stage "frontend-flutter/pubspec.lock"
stub_flutter 0 0 0 1
tree_commit "a pubspec change whose lock pub get rewrites" 2 "changed frontend-flutter/pubspec.lock"
git -C "$TREE" add frontend-flutter/pubspec.lock
GATE_COMMAND="git commit -am x" tree_commit "the same under -a, which stages the lock" 0
stub_flutter 0 0
git -C "$TREE" add frontend-flutter/pubspec.lock
tree_commit "a pubspec change whose lock pub get leaves alone" 0
git -C "$TREE" rm -q --cached frontend-flutter/pubspec.yaml frontend-flutter/pubspec.lock
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

echo "== deploy ===================================================="
# deploy.sh is the production path: the order of its steps is what makes a failed deploy
# a no-op instead of an outage, and it can only be asserted offline. A sandbox clone with
# a real origin drives the real script, with docker-compose, curl, jq and sleep stubbed —
# the compose stub logs its arguments, so the *order* of build/down/up is the assertion.
DREMOTE="$SANDBOX/deploy-remote.git"
DPROD="$SANDBOX/deploy-prod"
DTOOLS="$SANDBOX/deploy-tools"
DLOG="$SANDBOX/compose.log"
mkdir -p "$DTOOLS"
git init -q --bare "$DREMOTE"
git init -q "$SANDBOX/deploy-src"
git -C "$SANDBOX/deploy-src" config user.email t@t
git -C "$SANDBOX/deploy-src" config user.name t
mkdir -p "$SANDBOX/deploy-src/data"
cp "$ROOT/deploy.sh" "$SANDBOX/deploy-src/deploy.sh"
chmod +x "$SANDBOX/deploy-src/deploy.sh"
git -C "$SANDBOX/deploy-src" add -A
git -C "$SANDBOX/deploy-src" commit -qm "deploy.sh"
git -C "$SANDBOX/deploy-src" remote add origin "$DREMOTE"
git -C "$SANDBOX/deploy-src" push -q -u origin HEAD:refs/heads/main 2>/dev/null
git clone -q -b main "$DREMOTE" "$DPROD" 2>/dev/null
git -C "$DPROD" config user.email t@t
git -C "$DPROD" config user.name t
printf '#!/bin/sh\nexit 0\n' > "$DTOOLS/sleep"
printf '#!/bin/sh\ncat >/dev/null 2>&1 || true\nexit 0\n' > "$DTOOLS/jq"
chmod +x "$DTOOLS/sleep" "$DTOOLS/jq"
DSTATES="$SANDBOX/deploy-states"     # one file per service, holding its container state
mkdir -p "$DSTATES"
DSERVICES="$SANDBOX/deploy-services" # what `docker-compose config --services` answers
services_stub() { printf '%s\n' "$@" > "$DSERVICES"; }
services_stub backend frontend nginx frontend-flutter
compose_stub() {  # exit code of `build`, of `down`, of `up`, [of `config`] (0 = succeeds)
    cat > "$DTOOLS/docker-compose" <<STUBEOF
#!/bin/sh
echo "\$*" >> "$DLOG"
case "\$1" in
    build) exit $1 ;;
    down)  exit $2 ;;
    up)    exit $3 ;;
    config)                                 # \`config --services\`
        if [ "${4:-0}" != 0 ]; then
            echo 'Missing mandatory value for "environment" option: JWT_SECRET must be set' >&2
            exit ${4:-0}
        fi
        cat "$DSERVICES" ;;
    port)  echo 0.0.0.0:80 ;;               # \`port <proxy> 80\`
    ps)    [ "\$2" = -q ] && echo "cid-\$3" ;;
esac
exit 0
STUBEOF
    chmod +x "$DTOOLS/docker-compose"
}
# `docker inspect -f ... cid-<service>` answers per service, so one container can be
# unhealthy while the others are fine — which is the whole point of the split verdict.
cat > "$DTOOLS/docker" <<STUBEOF
#!/bin/sh
case "\$1" in
    inspect)
        for a in "\$@"; do last=\$a; done
        svc=\${last#cid-}
        if [ -f "$DSTATES/\$svc" ]; then cat "$DSTATES/\$svc"; else echo healthy; fi ;;
esac
exit 0
STUBEOF
chmod +x "$DTOOLS/docker"
health_stub() {  # service, state -- everything not named is healthy
    rm -f "$DSTATES"/*
    [ $# -eq 0 ] || echo "$2" > "$DSTATES/$1"
}
site_stub() {  # exit code of curl: 0 = /api/health answers, 7 = nothing listening
    printf '#!/bin/sh\nexit %s\n' "$1" > "$DTOOLS/curl"
    chmod +x "$DTOOLS/curl"
}
upstream() {  # push one more commit to the sandbox origin
    git -C "$SANDBOX/deploy-src" commit -q --allow-empty -m "$1"
    git -C "$SANDBOX/deploy-src" push -q origin HEAD:refs/heads/main 2>/dev/null
}
run_deploy() {  # -> the deploy's exit code; $dout is its output, $DLOG the compose calls
    : > "$DLOG"
    dout=$(cd "$DPROD" && PATH="$DTOOLS:$PATH" ./deploy.sh 2>&1)
    return $?
}
run_deploy_from_subdir() {  # the same, invoked as `../deploy.sh` from data/
    : > "$DLOG"
    dout=$(cd "$DPROD/data" && PATH="${1:+$1:}$DTOOLS:$PATH" ../deploy.sh 2>&1)
    return $?
}
# Only the three steps that change what is running; the health poll's `config`/`ps`/`port`
# and the failure path's `logs` are noise for an order assertion.
calls() { grep -E '^(build|down|up)( |$)' "$DLOG" | tr '\n' '|' | sed 's/|$//'; }
any_call() { tr '\n' '|' < "$DLOG" | sed 's/|$//'; }

# The happy path: pull, build, and only then down/up. `down` carries --remove-orphans so
# a rollback to a compose file without frontend-flutter cleans up after itself.
compose_stub 0 0 0; health_stub; site_stub 0
upstream "a change to deploy"
run_deploy; rc=$?
report "deploy: exits 0 on the happy path"          0 "$rc"
report "deploy: builds before it stops anything"    "build|down --remove-orphans|up -d" "$(calls)"
case "$dout" in *"downtime was "*) got=printed ;; *) got="no downtime figure" ;; esac
report "deploy: prints the downtime it caused"      printed "$got"

# A failed build must not reach `down`: production keeps serving the old images. The clone
# is at the new commit by then, though, so the message must not call it a clean no-op.
compose_stub 1 0 0
upstream "a change whose build fails"
run_deploy; rc=$?
report "deploy: a failed build exits non-zero"      1 "$rc"
report "deploy: a failed build stops nothing"       "build" "$(calls)"
case "$dout" in *"nothing was stopped"*) got=said ;; *) got="missing from the output" ;; esac
report "deploy: and says so"                        said "$got"
case "$dout" in *"now at the new commit"*) got=said ;; *) got="missing from the output" ;; esac
report "deploy: and that the clone moved anyway"    said "$got"
# The pull happened, so the fix is just to run it again once the cause is fixed.
compose_stub 0 0 0
run_deploy; rc=$?
report "deploy: re-running after a fixed build works" 0 "$rc"

# A failing `down` is the one step that can leave nothing running: it must not end the
# script silently, and it must try to bring the stack back before it gives up.
compose_stub 0 1 0
upstream "a change whose down fails"
run_deploy; rc=$?
report "deploy: a failing down exits non-zero"      1 "$rc"
report "deploy: and tries to start the stack again" "build|down --remove-orphans|up -d" "$(calls)"
case "$dout" in *"may be DOWN"*) got=warned ;; *) got="missing from the output" ;; esac
report "deploy: and says production may be down"    warned "$got"

# `up -d` returning 0 proves nothing: a container that crash-loops satisfies it. An
# *essential* one — what serves /, /api/ and /suscribeupdate — is an outage: fail loudly
# with the container and its logs.
compose_stub 0 0 0; health_stub backend restarting
upstream "a change that builds and then crash-loops"
run_deploy; rc=$?
report "deploy: an unhealthy backend fails the deploy"   1 "$rc"
case "$dout" in *"backend(restarting)"*) got=named ;; *) got="missing from the output" ;; esac
report "deploy: and names the container and its state"   named "$got"
case "$dout" in *"last 30 lines of backend"*) got=shown ;; *) got="missing from the output" ;; esac
report "deploy: and shows its logs"                      shown "$got"
case "$dout" in *"production is DOWN"*) got=said ;; *) got="missing from the output" ;; esac
report "deploy: and calls it an outage"                  said "$got"

# A *non-essential* one is not. `frontend-flutter` is resolved per request by nginx
# (#36), so an unhealthy PWA costs /app/ a 502 and nothing else: the script must warn,
# not cry outage, or the operator rolls back a site that is serving.
health_stub frontend-flutter unhealthy
upstream "a change whose PWA container is broken"
run_deploy; rc=$?
report "deploy: an unhealthy PWA does not read as an outage" 2 "$rc"
case "$dout" in *"production is DOWN"*) got="called it an outage" ;; *) got=no ;; esac
report "deploy: and never says production is down"       no "$got"
case "$dout" in *"WARNING"*"frontend-flutter(unhealthy)"*) got=warned ;; *) got="missing from the output" ;; esac
report "deploy: names it in a warning instead"           warned "$got"
case "$dout" in *"Site answering again"*) got=said ;; *) got="missing from the output" ;; esac
report "deploy: and confirms the site came back"         said "$got"
case "$dout" in *'`/app/`'*502*) got=said ;; *) got="missing from the output" ;; esac
report "deploy: says what it costs (/app/ answers 502)"  said "$got"
case "$dout" in *"Rolling back is OPTIONAL"*) got=said ;; *) got="missing from the output" ;; esac
report "deploy: and that a rollback is optional"         said "$got"
case "$dout" in *"last 30 lines of frontend-flutter"*) got=shown ;; *) got="missing from the output" ;; esac
report "deploy: shows its logs too"                      shown "$got"
case "$dout" in *"DEGRADED"*) got=said ;; *) got="missing from the output" ;; esac
report "deploy: and its final banner is not a success"   said "$got"

# Containers all up, but the site does not answer: still a failed deploy, not a success.
health_stub; site_stub 7
upstream "a change that starts but does not serve"
run_deploy; rc=$?
report "deploy: a silent /api/health fails the deploy"   1 "$rc"
case "$dout" in *"does not answer 200"*) got=said ;; *) got="missing from the output" ;; esac
report "deploy: and says so"                             said "$got"
site_stub 0

# A compose file that does not declare an essential service: the split verdict would
# silently treat a missing `frontend` as optional, so refuse before building anything.
services_stub backend nginx
upstream "a change that drops the frontend service"
run_deploy; rc=$?
report "deploy: refuses a compose file missing an essential service" 1 "$rc"
report "deploy: and builds nothing"                      "" "$(calls)"
case "$dout" in *"expects a service named 'frontend'"*) got=named ;; *) got="missing from the output" ;; esac
report "deploy: naming the service and the three files"  named "$got"
services_stub backend frontend nginx frontend-flutter

# A compose file docker-compose cannot read — since the Rust backend, a .env without
# JWT_SECRET (`${JWT_SECRET:?...}`) — is refused before anything is built or stopped.
compose_stub 0 0 0 1
upstream "a change deployed with no JWT_SECRET in .env"
run_deploy; rc=$?
report "deploy: refuses a compose file it cannot read"   1 "$rc"
report "deploy: and builds nothing then"                 "" "$(calls)"
case "$dout" in *"JWT_SECRET must be set"*"cannot read the compose file"*) got=said ;; *) got="missing from the output" ;; esac
report "deploy: printing compose's reason, then its own" said "$got"

# A tracked production database: refuse before the pull, naming the fix.
compose_stub 0 0 0
mkdir -p "$DPROD/data"
echo x > "$DPROD/data/zapzap.db"
git -C "$DPROD" add -f data/zapzap.db
upstream "a change nobody gets to deploy"
before=$(git -C "$DPROD" rev-parse HEAD)
run_deploy; rc=$?
report "deploy: refuses while data/zapzap.db is tracked" 1 "$rc"
report "deploy: and does not pull"                  "$before" "$(git -C "$DPROD" rev-parse HEAD)"
report "deploy: and runs no docker-compose"         "" "$(any_call)"
case "$dout" in *"git rm --cached data/zapzap.db"*) got=named ;; *) got="missing from the output" ;; esac
report "deploy: names the fix"                      named "$got"

# The same, invoked from a subdirectory: the check is relative to the clone, not to $PWD,
# or it answers "not tracked" about a path that does not exist and pulls anyway.
run_deploy_from_subdir; rc=$?
report "deploy: refuses from a subdirectory too"    1 "$rc"
report "deploy: and still does not pull"            "$before" "$(git -C "$DPROD" rev-parse HEAD)"
report "deploy: and still runs no docker-compose"   "" "$(any_call)"

# git itself unavailable (not on PATH on the NAS, where the skill has to export it): the
# question is unanswered, which is not the same as a clean answer.
DNOGIT="$SANDBOX/deploy-nogit"
mkdir -p "$DNOGIT"
printf '#!/bin/sh\necho "git: command not found" >&2\nexit 127\n' > "$DNOGIT/git"
chmod +x "$DNOGIT/git"
run_deploy_from_subdir "$DNOGIT"; rc=$?
report "deploy: refuses when git cannot answer"     1 "$rc"
report "deploy: and runs no docker-compose then"    "" "$(any_call)"
case "$dout" in *"cannot ask git"*) got=said ;; *) got="missing from the output" ;; esac
report "deploy: and says the check could not run"   said "$got"

git -C "$DPROD" rm -q --cached data/zapzap.db
report "deploy: git rm --cached keeps the file"     kept "$([ -f "$DPROD/data/zapzap.db" ] && echo kept || echo gone)"

# A pull that would not fast-forward — a hand edit on the NAS, or a detached HEAD after a
# rollback — is refused rather than merged blind, and again nothing is stopped. The
# message must carry git's own reason, since the cause is not always a diverged branch.
git -C "$DPROD" commit -q --allow-empty -m "someone edited production by hand"
upstream "and meanwhile master moved"
run_deploy; rc=$?
report "deploy: refuses a pull that is not a fast-forward" 1 "$rc"
report "deploy: and stops nothing"                  "" "$(any_call)"
case "$dout" in *"fatal:"*) got=quoted ;; *) got="git's own reason is missing" ;; esac
report "deploy: and quotes git's own reason"        quoted "$got"

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
# A failed flutter step (no network, a package missing from the cache) must not leave the
# setup marker behind, or cleanup_local.sh keeps the worktree forever.
printf '#!/bin/sh\nexit 1\n' > "$TOOLS/flutter"
err=$(cd "$WIPREPO" && PATH="$TOOLS:$PATH" scripts/worktree_setup.sh --no-frontend --no-rust 2>&1 >/dev/null)
report "worktree_setup.sh: a failed flutter step exits non-zero" 1 "$?"
report "worktree_setup.sh: and clears its setup marker" gone \
    "$([ -e "$WIPREPO/.zapzap-setup-in-progress" ] && echo kept || echo gone)"
case "$err" in *"Rerun: cd $WIPREPO/frontend-flutter && flutter pub get"*) got=named ;; *) got="$err" ;; esac
report "worktree_setup.sh: and names the command to rerun" named "$got"

for script in "$HOOKS"/*.sh "$HOOKS"/*.py; do
    [ -x "$script" ] && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "  FAIL  $script is not executable"; }
done
python3 -m json.tool "$ROOT/.claude/settings.json" >/dev/null 2>&1
report "settings.json is valid JSON" 0 "$?"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
