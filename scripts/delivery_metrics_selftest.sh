#!/bin/bash

# ZapZap - self-test for scripts/delivery_metrics.sh.
#
# Builds a throwaway repository whose history has a known answer -- a fix within 48 h of
# the change it repairs, one after 48 h, a docs-only change, a test file and a translated
# ARB file that the size excludes -- stubs `gh`, and checks each line of the report. Runs in
# the `hooks` job, next to the other script self-tests, in about a second.
#
# Usage: scripts/delivery_metrics_selftest.sh      (exit 0 = every case holds)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METRICS="$ROOT/scripts/delivery_metrics.sh"

pass=0
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

report() {  # description, expected, actual
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf '  FAIL  %s\n        expected [%s], got [%s]\n' "$1" "$2" "$3"
    fi
}

repo="$tmp/repo"
mkdir -p "$repo" && cd "$repo" || exit 1
git init -q -b master
git config user.email selftest@example.invalid
git config user.name selftest
git config commit.gpgsign false

commit() {  # date, subject, file:lines ...
    local when=$1 subject=$2 spec
    shift 2
    for spec in "$@"; do
        mkdir -p "$(dirname "${spec%%:*}")"
        seq "${spec##*:}" | sed "s/^/$RANDOM /" >> "${spec%%:*}"
        git add "${spec%%:*}"
    done
    GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" git commit -q -m "$subject"
}

# Before the window: not counted, but its file exists.
commit '2025-12-20T10:00:00' 'chore: seed' zapzap-rust/src/seed.rs:5
# In the window, 2026-01-01 .. 2026-01-15:
commit '2026-01-02T10:00:00' 'feat: a (#1)' frontend-flutter/lib/a.dart:100 \
    frontend-flutter/test/a_test.dart:40                                          # rework: fixed at +10 h
commit '2026-01-02T20:00:00' 'fix: a (#2)' frontend-flutter/lib/a.dart:3
commit '2026-01-03T10:00:00' 'docs: readme (#3)' README.md:50 .llmwiki/X.md:5     # size 0, not deployed
commit '2026-01-05T10:00:00' 'fix(api): b (#4)' zapzap-rust/src/b.rs:20 zapzap-rust/tests/b.rs:30
commit '2026-01-06T10:00:00' 'feat: c (#5)' frontend/c.jsx:580 \
    frontend-flutter/lib/l10n/app_fr.arb:20 frontend-flutter/lib/l10n/app_de.arb:20  # its fix comes after 72 h
commit '2026-01-09T10:00:00' 'fix: c (#6)' frontend/c.jsx:2
commit '2026-01-14T10:00:00' 'chore: ci (#7)' .github/ci.yml:1600
# After the window: a fix within 48 h of #7, which still makes #7 rework.
commit '2026-01-15T12:00:00' 'fix: ci (#8)' .github/ci.yml:1

mkdir -p wip/todo wip/todo_nr wip/done
touch "wip/todo/$(date -d '4 days ago' +%F)-open.md" "wip/todo/$(date -d '10 days ago' +%F)-older.md"
printf '# x\n\n**Status:** done (2026-01-05) — closed.\n' > wip/done/2026-01-01-closed.md
printf '# y\n\n**Status:** done (2025-12-01) — closed.\n' > wip/done/2025-11-20-before.md

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF'
#!/bin/bash
# gh applies -q itself, so the stub prints what the query would.
case "$1 $2" in
    "pr list")  printf 'feat/a\t2026-01-02T12:00:00Z\nfeat/c\t2026-01-06T12:00:00Z\nchore/nobuild\t2026-01-07T12:00:00Z\n' ;;
    "run list") printf 'feat/a\t2026-01-02T09:00:00Z\tsuccess\nfeat/c\t2026-01-06T09:00:00Z\tfailure\nfeat/c\t2026-01-06T09:30:00Z\tsuccess\n' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"

out=$(PATH="$tmp/bin:$PATH" DELIVERY_METRICS_REF=master "$METRICS" 2026-01-01 2026-01-15 2>&1)
line() { printf '%s\n' "$out" | grep -m1 "^  $1" | sed "s/^  $1 *//"; }
ratio() { line "$1" | sed 's/   (.*//'; }   # the figure, without its explanation

report "changes in the window" "7" "$(line 'changes on master')"
report "fix: share, fix( scope counted" "3/7  42.9 %" "$(line 'fix: share')"
report "rework: within 48 h, same file, fix after the window counts" "2/7  28.6 %" "$(ratio 'rework rate')"
report "deployments from paths" "5  2.5/week   (backend 1, frontends 4; derived from paths)" "$(line 'deployments')"
report "change failure rate" "1/5  20.0 %" "$(ratio 'change failure rate')"
report "size: tests, docs and translated ARB excluded" "p50 20  p90 1600  max 1600   (counted lines per change)" "$(line 'size ')"
report "size buckets" "0: 1  1-49: 3  50-199: 1  200-499: 0  500-1499: 1  >=1500: 1" "$(line 'size buckets')"
report "first-run-green from the earliest run" "1/2  50.0 %   (of 2 merged pull requests with a CI run; 3 merged)" "$(line 'first-run-green')"
report "open wip entries and their age" "2 open   median 4 d   max 10 d   older than 30 d: 0" "$(line 'todo ')"
report "closed wip entries in the window" "1 closed in the window   age at close: median 4 d   max 4 d" "$(line 'done ')"

out=$(PATH="$tmp/bin:$PATH" DELIVERY_METRICS_REF=master "$METRICS" 2026-01-15 2026-01-01 2>&1); status=$?
report "until before since is refused" "2" "$status"

printf '%s\n' "#!/bin/bash" "exit 1" > "$tmp/bin/gh"
out=$(PATH="$tmp/bin:$PATH" DELIVERY_METRICS_REF=master "$METRICS" 2026-01-01 2026-01-15 2>&1)
report "no gh: first-run-green is n/a, the rest still prints" "n/a (gh unavailable or not authenticated)" "$(line 'first-run-green')"

# The exclusion list is the ship-parallel §3.1 counter's, verbatim.
skill_list=$(grep -m1 'keep = (p !~ /' "$ROOT/.claude/skills/ship-parallel/SKILL.md" |
    sed 's/^.*keep = (p !~ \(.*\)) \\$/\1/')
script_list=$(sed -n "s/^export EXCLUDE='\(.*\)'$/\1/p" "$METRICS")
report "exclusion list matches ship-parallel §3.1" "/$script_list/" "$skill_list"
for var in ARB ARB_KEEP; do
    re=$(sed -n "s/^export $var='\(.*\)'$/\1/p" "$METRICS")
    report "the ARB clause $var matches ship-parallel §3.1" "1" \
        "$(grep -m1 -cF "/$re/" "$ROOT/.claude/skills/ship-parallel/SKILL.md")"
done

printf 'delivery_metrics self-test: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
