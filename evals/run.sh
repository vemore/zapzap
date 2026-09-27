#!/bin/bash
#
# ZapZap agent evals: replay past tasks with `claude -p` and check the outcome.
#
# Usage: evals/run.sh [options] [case...]        (no case: every case)
#   --list             list the cases and exit
#   --dry-run          no agent: print the claude command, check the untouched tree
#   --fixture good|bad no agent: apply the case's hand-made outcome instead (selftest.sh)
#   --ref <ref>        commit the throwaway worktree starts from (default origin/master);
#                      HEAD to evaluate a branch's own CLAUDE.md, skills, hooks and wiki
#   --model <model>    model for the agent (default: the CLI's)
#   --budget <usd>     spending cap per case (default 3)
#   --timeout <min>    wall-clock cap per case (default 45)
#   --keep             keep the worktrees and branches for inspection
#
# A case is either evals/cases/<name>/ (cross-cutting: prompt.md, check.sh, case.env,
# optional setup.sh, good.sh and bad.sh) or <skill>/<id>, an eval of
# .claude/skills/<skill>/evals/evals.json (skill-creator's format) whose script form is
# .claude/skills/<skill>/evals/<id>/check.sh. Case files are read from this checkout; the
# tree the agent works in is --ref.
#
# Each case gets its own worktree under $TMPDIR on a branch eval/<case>-<stamp>, marked
# noPullRequest, with no upstream. The fixture (setup.sh) is committed as "eval fixture:
# <case>", which is the base the check judges from. The agent runs with a closed tool list
# (--permission-mode dontAsk --allowedTools ...), push, gh, fetch and network tools denied,
# a pushurl that points nowhere and no GitHub credentials; so it can commit and nothing
# more. Its final message is saved as report.md next to the worktree (the check reads
# `## New wip entries` there), and the main checkout's wip/ must come out unchanged. It
# runs on your own Claude login: no API key, no CI. Worktrees and branches are removed at
# the end unless --keep. Logs go to evals/runs/<stamp>/ (gitignored).
#
# Exit status: 0 when every case passes, 1 otherwise, 2 on a usage error.

set -uo pipefail

EVALS="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$EVALS" rev-parse --show-toplevel)"
MAIN="$(dirname "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)")"
SKILLS="$REPO/.claude/skills"

mode=agent fixture="" ref=origin/master model="" budget=3 timeout_min=45 keep=0
cases=()
while [ $# -gt 0 ]; do
    case "$1" in
        --list) mode=list ;;
        --dry-run) mode=dry ;;
        --fixture) mode=fixture; fixture="${2:?--fixture good|bad}"; shift ;;
        --ref) ref="${2:?--ref <ref>}"; shift ;;
        --model) model="${2:?--model <model>}"; shift ;;
        --budget) budget="${2:?--budget <usd>}"; shift ;;
        --timeout) timeout_min="${2:?--timeout <minutes>}"; shift ;;
        --keep) keep=1 ;;
        -h|--help) sed -n '3,33p' "$0"; exit 0 ;;
        -*) echo "run.sh: unknown option $1 (see --help)" >&2; exit 2 ;;
        *) cases+=("$1") ;;
    esac
    shift
done
case "$fixture" in ""|good|bad) ;; *) echo "run.sh: --fixture good|bad" >&2; exit 2 ;; esac

all_cases() {
    local d f
    for d in "$EVALS"/cases/*/; do [ -f "$d/check.sh" ] && basename "$d"; done
    for f in "$SKILLS"/*/evals/evals.json; do
        [ -f "$f" ] || continue
        python3 - "$f" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
skill = p.parent.parent.name
for e in json.loads(p.read_text())["evals"]:
    if (p.parent / str(e["id"]) / "check.sh").is_file():
        print(f"{skill}/{e['id']}")
PY
    done
}

# Resolve a case id into: DIR (its files), PROMPT, SETUP_KIND, UNTOUCHED, SOURCE.
# SETUP_KIND says what scripts/worktree_setup.sh prepares before the agent starts, so the
# commit hook's gates can run: none, rust (cargo only) or all (npm ci, cargo, pub get).
resolve() {
    local id="$1"
    SOURCE="" SETUP_KIND=none UNTOUCHED=fail
    if [ -d "$EVALS/cases/$id" ]; then
        DIR="$EVALS/cases/$id"
        PROMPT="$(cat "$DIR/prompt.md")"
        # shellcheck disable=SC1091
        [ -f "$DIR/case.env" ] && . "$DIR/case.env"
        SETUP_KIND="${SETUP:-none}"
        SOURCE="evals/cases/$id"
    elif [[ "$id" == */* ]] && [ -f "$SKILLS/${id%%/*}/evals/evals.json" ]; then
        DIR="$SKILLS/${id%%/*}/evals/${id#*/}"
        PROMPT="$(python3 - "$SKILLS/${id%%/*}/evals/evals.json" "${id#*/}" <<'PY'
import json, sys
for e in json.load(open(sys.argv[1]))["evals"]:
    if str(e["id"]) == sys.argv[2]:
        print(e["prompt"])
PY
)"
        [ -n "$PROMPT" ] && [ -f "$DIR/check.sh" ] || return 1
        SETUP_KIND=all
        # shellcheck disable=SC1091
        [ -f "$DIR/case.env" ] && . "$DIR/case.env" && SETUP_KIND="${SETUP:-all}"
        SOURCE=".claude/skills/${id%%/*}/evals/evals.json#${id#*/}"
    else
        return 1
    fi
    unset SETUP
}

if [ "$mode" = list ]; then
    while read -r c; do
        resolve "$c" && printf '%-32s %-5s %s\n' "$c" "$SETUP_KIND" "$SOURCE"
    done < <(all_cases)
    exit 0
fi

[ ${#cases[@]} -gt 0 ] || mapfile -t cases < <(all_cases)
for c in "${cases[@]}"; do resolve "$c" || { echo "run.sh: no such case: $c" >&2; exit 2; }; done
git -C "$REPO" rev-parse --verify --quiet "$ref^{commit}" >/dev/null \
    || { echo "run.sh: --ref $ref is not a commit (git fetch --prune origin?)" >&2; exit 2; }
if [ "$mode" = agent ] && ! command -v claude >/dev/null; then
    echo "run.sh: the claude CLI is not on PATH" >&2; exit 2
fi

stamp="$(date +%Y%m%d-%H%M%S)-$$"
# An agent run keeps its logs in evals/runs/ (gitignored); a dry or fixture run, which costs
# nothing to repeat, logs to a temporary directory removed on exit unless --keep.
if [ "$mode" = agent ]; then OUT="$EVALS/runs/$stamp"
else OUT="$(mktemp -d "${TMPDIR:-/tmp}/zapzap-eval-logs.XXXXXX")"; fi
mkdir -p "$OUT"

# The tools an eval agent gets: read, edit, commit, the project's local checks. No push,
# no gh, no network, no branch or worktree changes, no sub-agents.
ALLOWED=(
    Read Edit Write Glob Grep Skill TodoWrite
    "Bash(git status:*)" "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)"
    "Bash(git add:*)" "Bash(git mv:*)" "Bash(git rm:*)" "Bash(git commit:*)"
    "Bash(git rev-parse:*)" "Bash(git ls-files:*)" "Bash(git grep:*)" "Bash(git branch --show-current)"
    "Bash(ls:*)" "Bash(cat:*)" "Bash(head:*)" "Bash(tail:*)" "Bash(wc:*)" "Bash(grep:*)"
    "Bash(find:*)" "Bash(sort:*)" "Bash(jq:*)" "Bash(date:*)"
    "Bash(scripts/wip.sh list:*)" "Bash(scripts/wip.sh themes:*)"
    "Bash(cargo fmt --manifest-path zapzap-rust/Cargo.toml:*)"
    "Bash(cargo clippy --manifest-path zapzap-rust/Cargo.toml:*)"
    "Bash(cargo test --manifest-path zapzap-rust/Cargo.toml:*)"
    "Bash(npm --prefix frontend run:*)" "Bash(dart format frontend-flutter/:*)"
)
DENIED=(
    "Bash(git push:*)" "Bash(gh:*)" "Bash(git remote:*)" "Bash(git config:*)"
    "Bash(git fetch:*)" "Bash(git pull:*)" "Bash(git switch:*)" "Bash(git checkout:*)"
    "Bash(git worktree:*)" "Bash(git reset:*)" "Bash(curl:*)" "Bash(wget:*)" "Bash(ssh:*)"
    "Bash(scp:*)" "Bash(rsync:*)" "Bash(scripts/deploy_nas.sh:*)" WebFetch WebSearch Agent Task
)

WORKTREES=() BRANCHES=()
cleanup() {
    [ "$keep" = 1 ] && { [ ${#WORKTREES[@]} -gt 0 ] && echo "kept: ${WORKTREES[*]}"; return; }
    [ "$mode" = agent ] || rm -rf "$OUT"
    local i
    for i in "${!WORKTREES[@]}"; do
        git -C "$REPO" worktree remove --force "${WORKTREES[$i]}" 2>/dev/null
        rm -rf "$(dirname "${WORKTREES[$i]}")"
        git -C "$REPO" branch -D -q "${BRANCHES[$i]}" 2>/dev/null
    done
    git -C "$REPO" worktree prune
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# The main checkout's wip/, as a list of files with their modification times: an agent in
# a worktree never writes there (CLAUDE.md), whatever its check says.
wip_snapshot() { find "$MAIN/wip" -type f -printf '%P %T@\n' 2>/dev/null | sort; }

run_case() {
    local id="$1" slug="${1//\//-}" tmp wt br base log="$OUT/${1//\//-}"
    resolve "$id"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/zapzap-eval.XXXXXX")"
    wt="$tmp/wt" br="eval/$slug-$stamp"
    # --no-track: made off origin/master, the branch would otherwise track it, and a bare
    # push would have somewhere to go.
    git -C "$REPO" worktree add -q --no-track -b "$br" "$wt" "$ref" || return 1
    WORKTREES+=("$wt") BRANCHES+=("$br")
    git -C "$REPO" config "branch.$br.noPullRequest" true

    if [ -f "$DIR/setup.sh" ]; then
        (cd "$wt" && bash "$DIR/setup.sh") > "$log.setup.log" 2>&1 \
            || { echo "  setup.sh failed: $log.setup.log"; return 1; }
    fi
    git -C "$wt" add -A
    git -C "$wt" -c user.name=zapzap-eval -c user.email=eval@localhost \
        commit -q --no-verify --allow-empty -m "eval fixture: $id"
    base="$(git -C "$wt" rev-parse HEAD)"

    local setup_flags=()
    case "$SETUP_KIND" in
        rust) setup_flags=(--no-frontend --no-flutter) ;;
        all) setup_flags=() ;;
    esac

    local wip_before; wip_before="$(wip_snapshot)"
    case "$mode" in
        dry)
            echo "  would run in $wt:"
            [ "$SETUP_KIND" != none ] && echo "    after scripts/worktree_setup.sh ${setup_flags[*]:+${setup_flags[*]} }$wt"
            echo "    claude -p <evals/preamble.md + $SOURCE/prompt.md> --permission-mode dontAsk" \
                 "--setting-sources project --no-session-persistence --output-format json" \
                 "${model:+--model $model }--max-budget-usd $budget" \
                 "--allowedTools (${#ALLOWED[@]} rules) --disallowedTools (${#DENIED[@]} rules)"
            ;;
        fixture)
            [ -f "$DIR/$fixture.sh" ] || { echo "  no $fixture.sh fixture"; return 1; }
            (cd "$wt" && GIT_AUTHOR_NAME=zapzap-eval GIT_AUTHOR_EMAIL=eval@localhost \
                GIT_COMMITTER_NAME=zapzap-eval GIT_COMMITTER_EMAIL=eval@localhost \
                bash "$DIR/$fixture.sh") > "$log.fixture.log" 2>&1 \
                || { echo "  $fixture.sh failed: $log.fixture.log"; return 1; }
            ;;
        agent)
            if [ "$SETUP_KIND" != none ]; then
                "$REPO/scripts/worktree_setup.sh" "${setup_flags[@]}" "$wt" > "$log.setup.log" 2>&1 \
                    || { echo "  worktree_setup.sh failed: $log.setup.log"; return 1; }
            fi
            local prompt; prompt="$(sed "s|{{BRANCH}}|$br|" "$EVALS/preamble.md")$PROMPT"
            local ghdir="$tmp/gh"; mkdir -p "$ghdir"
            (
                cd "$wt" || exit 1
                env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR="$ghdir" \
                    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.pushurl \
                    GIT_CONFIG_VALUE_0="$tmp/no-push-in-evals" \
                    timeout "$((timeout_min * 60))" claude -p "$prompt" \
                        --permission-mode dontAsk --setting-sources project \
                        --no-session-persistence --output-format json \
                        --max-budget-usd "$budget" ${model:+--model "$model"} \
                        --allowedTools "${ALLOWED[@]}" --disallowedTools "${DENIED[@]}"
            ) > "$log.claude.json" 2> "$log.claude.err" < /dev/null
            echo "  agent exit $? — $(python3 - "$log.claude.json" "$tmp/report.md" <<'PY'
import json, sys
try:
    r = json.load(open(sys.argv[1]))
    open(sys.argv[2], "w").write(r.get("result") or "")
    print(f"{r.get('num_turns', '?')} turns, {r.get('duration_ms', 0) / 1000:.0f} s, "
          f"${r.get('total_cost_usd', 0):.2f}")
except Exception as e:
    print(f"no result ({e.__class__.__name__})")
PY
)"
            [ -f "$tmp/report.md" ] && cp "$tmp/report.md" "$log.report.md"
            ;;
    esac

    git -C "$wt" diff --stat "$base" > "$log.diff.txt" 2>&1
    git -C "$wt" log --format='%h %s' "$base..HEAD" >> "$log.diff.txt" 2>&1

    # The harness's own guarantees, whatever the check says: nothing left the machine, and
    # the main checkout's wip/ is as it was.
    local leaked=""
    git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name "$br@{upstream}" >/dev/null 2>&1 \
        && leaked="the branch has an upstream"
    git -C "$REPO" show-ref --verify --quiet "refs/remotes/origin/$br" && leaked="origin has $br"
    local wip_touched=""
    [ "$(wip_snapshot)" = "$wip_before" ] || wip_touched="$MAIN/wip changed during the run"

    bash "$DIR/check.sh" "$wt" "$base" | tee "$log.check.txt"
    local rc=${PIPESTATUS[0]}
    [ -n "$leaked" ] && { echo "  FAIL nothing pushed: $leaked"; rc=1; }
    [ -n "$wip_touched" ] && { echo "  FAIL main checkout's wip/ untouched: $wip_touched"; rc=1; }
    return "$rc"
}

declare -A RESULT
failed=0
for c in "${cases[@]}"; do
    echo "== $c"
    run_case "$c"; rc=$?
    resolve "$c"
    if [ "$mode" = dry ]; then
        # Untouched, a case is expected to fail its check (nothing done) unless declining is
        # the right outcome (UNTOUCHED=pass). Dry-run passes when the check agrees.
        want=1; [ "$UNTOUCHED" = pass ] && want=0
        if [ "$rc" = "$want" ]; then RESULT[$c]="pass (untouched tree judged ${UNTOUCHED})"
        else RESULT[$c]="FAIL (untouched tree not judged ${UNTOUCHED})"; failed=$((failed + 1)); fi
    elif [ "$rc" = 0 ]; then RESULT[$c]=pass
    else RESULT[$c]=FAIL; failed=$((failed + 1)); fi
done

echo
logs=""
{ [ "$mode" = agent ] || [ "$keep" = 1 ]; } && logs=", logs in ${OUT#"$REPO"/}"
echo "== summary ($mode${fixture:+ $fixture}, ref $ref$logs)"
for c in "${cases[@]}"; do printf '  %-32s %s\n' "$c" "${RESULT[$c]}"; done
[ "$failed" = 0 ]
