#!/bin/bash

# ZapZap - self-test for scripts/wiki_lint.sh.
#
# Builds a throwaway fixture wiki with one instance of each finding and a clean
# counter-example for it, then checks the report names exactly what it should. The dead-path
# check resolves against this repository's real root (like scripts/wip.sh `refine`, whose
# finder it shares): the fixture references a script that exists (scripts/wiki_lint.sh) and
# a path that does not, rather than faking a checkout.
#
# Usage: scripts/wiki_lint_selftest.sh      (exit 0 = every case holds)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/scripts/wiki_lint.sh"

pass=0
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

report() {  # description, present|absent, occurrences
    if { [ "$2" = present ] && [ "$3" = 1 ]; } || { [ "$2" = absent ] && [ "$3" = 0 ]; }; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf '  FAIL  %s (expected %s, matched %s time(s))\n' "$1" "$2" "$3"
    fi
}

wiki="$tmp/wiki"
mkdir -p "$wiki"

cat > "$wiki/INDEX.md" <<'EOF'
# Index

`[[Name]]` resolves to `.llmwiki/<Name>.md` — this `[[Placeholder]]` is not a dead link.

| Page | Summary | Updated |
|---|---|---|
| [[Short]] | a clean page, nothing to report | 2026-01-01 |
| [[Long]] | over the line budget | 2026-01-02 |
| [[Stale]] | its own Updated: disagrees with this row | 2026-01-03 |
| [[HasLink]] | carries one of every other finding | 2026-01-04 |
| [[Wordy]] | one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twentyone twentytwo twentythree twentyfour twentyfive twentysix | 2026-01-05 |
| [[Exact]] | one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twentyone twentytwo twentythree twentyfour twentyfive | 2026-01-06 |
EOF

cat > "$wiki/Short.md" <<'EOF'
# Short

> Updated: 2026-01-01

A page with nothing for the linter to find.
EOF

{
    echo "# Long"
    echo
    echo "> Updated: 2026-01-02"
    echo
    seq 1 410 | sed 's/^/line /'
} > "$wiki/Long.md"

cat > "$wiki/Stale.md" <<'EOF'
# Stale

> Updated: 2026-01-09

INDEX.md's row for this page says 2026-01-03; this line says otherwise.
EOF

cat > "$wiki/HasLink.md" <<'EOF'
# HasLink

> Updated: 2026-01-04

Links to [[Short]] (lives) and to [[Ghost]] (does not — a dead link). A backticked
example like `[[Placeholder]]` is not a link to resolve.

> **Status: Outdated** (2026-01-01) — this block was never folded back.

Mentioning the marker itself, `Status: Outdated`, in prose is not a block and must not
match.

  > **Status: Contradicted** (2026-01-02) — see [[Short]].

References `scripts/wiki_lint.sh`, which exists, and
`zapzap-rust/src/definitely_missing_file_xyz.rs`, which does not, and
`data/zapzap.db`, which a fresh checkout lacks because it is gitignored, like
`data/bot-strategies` (the pattern is `data/bot-strategies/`).
EOF

printf '# Wordy\n\n> Updated: 2026-01-05\n' > "$wiki/Wordy.md"
printf '# Exact\n\n> Updated: 2026-01-06\n' > "$wiki/Exact.md"

out=$("$LINT" "$wiki" 2>&1)
n() { grep -Fc "$1" <<< "$out"; }        # occurrences of a literal string in the report
nre() { grep -Ec "$1" <<< "$out"; }      # occurrences of a regex in the report

echo "== findings that must appear ===================================="
report "the over-budget page"        present "$(n 'Long.md: 414 lines, over the 400 budget')"
report "the stale INDEX.md date"     present "$(n 'INDEX.md: row for [[Stale]] says 2026-01-03, Stale.md says 2026-01-09')"
report "the row over 25 words"       present "$(n 'INDEX.md: row for [[Wordy]] is 26 words, over the 25 budget')"
report "the dead link"               present "$(n 'HasLink.md:5: dead link [[Ghost]]')"
report "the Outdated block"          present "$(n 'HasLink.md:8: Status: Outdated block (2026-01-01)')"
report "the indented Contradicted block" present "$(n 'HasLink.md:13: Status: Contradicted block (2026-01-02)')"
report "the dead backticked path"    present "$(n 'HasLink.md: dead path `zapzap-rust/src/definitely_missing_file_xyz.rs`')"

echo "== findings that must not appear ================================="
report "the clean page"                                   absent "$(n 'Short.md')"
report "a row of exactly 25 words"                        absent "$(n '[[Exact]]')"
report "the backticked [[Placeholder]] example"           absent "$(n 'dead link [[Placeholder]]')"
report "the backticked [[Name]] example"                  absent "$(n 'dead link [[Name]]')"
report "the live link [[Short]]"                          absent "$(n 'dead link [[Short]]')"
report "a gitignored path (data/zapzap.db)"               absent "$(n 'data/zapzap.db')"
report "a gitignored directory named without its slash"   absent "$(n 'data/bot-strategies')"
report "the live backticked path"                         absent "$(n 'dead path `scripts/wiki_lint.sh`')"
report "the prose mention of the marker, not a block"     absent "$(n 'HasLink.md:10')"
report "INDEX.md itself against the page budget"          absent "$(nre '^INDEX\.md: [0-9]+ lines')"
report "the finding count"                                present "$(n '7 finding(s)')"

echo "== exit code and contract ========================================"
"$LINT" "$wiki" > /dev/null 2>&1
code=$?
report "exit 1 with findings present" present "$([ "$code" -eq 1 ] && echo 1 || echo 0)"

clean="$tmp/clean"
mkdir -p "$clean"
cp "$wiki/Short.md" "$clean/Short.md"
cat > "$clean/INDEX.md" <<'EOF'
# Index

| Page | Summary | Updated |
|---|---|---|
| [[Short]] | a clean page, nothing to report | 2026-01-01 |
EOF
"$LINT" "$clean" > /dev/null 2>&1
code=$?
report "exit 0 on a wiki with no finding" present "$([ "$code" -eq 0 ] && echo 1 || echo 0)"

mkdir -p "$tmp/noindex"
"$LINT" "$tmp/noindex" > /dev/null 2>&1
code=$?
report "exit 2 without an INDEX.md" present "$([ "$code" -eq 2 ] && echo 1 || echo 0)"

for f in "$LINT" "$ROOT/scripts/wiki_lint_selftest.sh"; do
    if [ -x "$f" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL  $f is not executable"
    fi
done

if [ "$fail" -gt 0 ]; then
    echo
    echo "== the report on the fixture wiki ================================"
    echo "$out"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
