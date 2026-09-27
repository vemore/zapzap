#!/bin/bash

# ZapZap - mechanical lint pass for .llmwiki/.
#
# .llmwiki/Documentation.md ("Wiki lint") splits the pass into a mechanical half and a
# judgement half. This script is the mechanical half:
#   - a page over the 400-line budget INDEX.md sets
#   - an INDEX.md row whose summary is over the 25-word budget
#   - a `> **Status: Outdated**` or `> **Status: Contradicted**` block, which should be
#     folded back into the fact it sits under, or settled
#   - a backticked repository path that no longer exists (scripts/lib/dead_paths.sh, shared
#     with scripts/wip.sh `refine`)
#   - a `[[Wiki link]]` naming a page `.llmwiki/<Name>.md` does not have
#   - an INDEX.md row whose date differs from the page's own `> Updated:` line
#
# Judgement is not attempted here: orphaned pages, a page whose Updated: predates the last
# commit to what it cites, the same fact stated on two pages. See .llmwiki/Documentation.md.
#
# This is a report, not a gate: the real wiki fails it (a page over budget, status blocks not
# yet folded back), so only scripts/wiki_lint_selftest.sh runs in CI.
#
# Usage: scripts/wiki_lint.sh [wiki-dir]      (default: .llmwiki)
#        exit 0 = no finding, 1 = at least one finding, 2 = no INDEX.md

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/dead_paths.sh"

WIKI="${1:-$ROOT/.llmwiki}"
WIKI="$(cd "$WIKI" && pwd)"
INDEX="$WIKI/INDEX.md"
BUDGET=400
ROW_WORDS=25

findings=0

finding() {  # page, message
    printf '%s: %s\n' "$1" "$2"
    findings=$((findings + 1))
}

[ -f "$INDEX" ] || { echo "no INDEX.md under $WIKI" >&2; exit 2; }

for page in "$WIKI"/*.md; do
    name="$(basename "$page" .md)"

    # A page over the line budget. INDEX.md is the index, not a page: its budget is per row,
    # checked below.
    if [ "$name" != INDEX ]; then
        lines=$(wc -l < "$page")
        [ "$lines" -gt "$BUDGET" ] && finding "$name.md" "$lines lines, over the $BUDGET budget"
    fi

    # Status blocks, anchored on the convention in INDEX.md: `> **Status: Outdated**
    # (YYYY-MM-DD) — ...`, any leading indent. The convention's own example writes a literal
    # `YYYY-MM-DD`, which never matches, and a prose mention has no leading `> **`.
    while IFS=: read -r lineno rest; do
        [ -n "$lineno" ] || continue
        kind=$(echo "$rest" | grep -oE 'Outdated|Contradicted')
        date=$(echo "$rest" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
        finding "$name.md:$lineno" "Status: $kind block ($date)"
    done < <(grep -noE '^[[:space:]]*> \*\*Status: (Outdated|Contradicted)\*\* \([0-9]{4}-[0-9]{2}-[0-9]{2}\)' "$page")

    # A backticked repository path this page names that no longer exists.
    while read -r p; do
        [ -n "$p" ] || continue
        finding "$name.md" "dead path \`$p\`"
    done < <(dead_repo_paths "$ROOT" "$page")

    # A [[Wiki link]] naming a page .llmwiki/<Name>.md does not have. Skipped when the
    # brackets touch a backtick on either side: the convention text writes `[[Name]]` as a
    # placeholder, not a link.
    while IFS=: read -r lineno linkname; do
        [ -n "$lineno" ] || continue
        [ -f "$WIKI/$linkname.md" ] && continue
        finding "$name.md:$lineno" "dead link [[$linkname]]"
    done < <(perl -ne 'while (/(?<!`)\[\[([A-Za-z0-9_]+)\]\](?!`)/g) { print "$.:$1\n" }' "$page")
done

# INDEX.md rows: the summary's word budget, and the date against the page's `> Updated:`.
while IFS='|' read -r _ link summary date _; do
    linkname=$(echo "$link" | sed -n 's/.*\[\[\([A-Za-z0-9_]*\)\]\].*/\1/p')
    [ -n "$linkname" ] || continue
    words=$(echo "$summary" | wc -w)
    [ "$words" -gt "$ROW_WORDS" ] && finding "INDEX.md" "row for [[$linkname]] is $words words, over the $ROW_WORDS budget"
    date=$(echo "$date" | tr -d '[:space:]')
    page="$WIKI/$linkname.md"
    [ -f "$page" ] || continue  # a dead link, already reported above
    page_date=$(grep -m1 -E '^> Updated: ' "$page" | sed -E 's/^> Updated: *//')
    if [ "$date" != "$page_date" ]; then
        finding "INDEX.md" "row for [[$linkname]] says $date, $linkname.md says ${page_date:-nothing}"
    fi
done < <(grep -E '^\| \[\[' "$INDEX")

echo
echo "$findings finding(s)"
[ "$findings" -eq 0 ]
