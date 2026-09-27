#!/bin/bash

# ZapZap - self-test for scripts/wip.sh `refine`.
#
# Builds a throwaway repository holding a copy of wip.sh (it resolves wip/ from the main
# checkout of the repository it sits in) and a fixture wip/ with one entry per section
# spelling, then checks the flags `refine` prints for each, and the per-Area todo/ count the
# WIP limit reads (wip-refine §5). Where wip/ is found from, and the dead-path flag, are
# covered by scripts/hooks_selftest.sh (wiring).
#
# Usage: scripts/wip_selftest.sh      (exit 0 = every case holds)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

report() {  # description, expected, got
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf '  FAIL  %s\n        expected: %s\n        got:      %s\n' "$1" "$2" "$3"
    fi
}

repo="$tmp/repo"
mkdir -p "$repo/scripts/lib" "$repo/wip/todo" "$repo/wip/todo_nr" "$repo/wip/done"
cp "$ROOT/scripts/wip.sh" "$repo/scripts/"
cp "$ROOT/scripts/lib/dead_paths.sh" "$repo/scripts/lib/"
git init -q "$repo"

entry() {  # folder/slug, area, body
    printf -- '# %s\n\n- **Noted:** 2026-09-27\n- **Theme:** t\n- **Area:** %s\n- **Blocks release:** no\n\nEvidence.\n\n%s\n' \
        "${1#*/}" "$2" "$3" > "$repo/wip/$1.md"
}

acc='**Acceptance:** a'
fix='**Fix:** f'
# Fix spellings: none of these is no-fix.
entry todo_nr/fix-plain       tooling "$fix"$'\n\n'"$acc"
entry todo_nr/fix-heading     tooling $'## Fix\n\nf\n\n'"$acc"
entry todo_nr/fix-heading-q   tooling $'## Fix (part a):\n\nf\n\n'"$acc"
entry todo_nr/fix-comma       tooling $'**Fix, minimal:** f\n\n'"$acc"
entry todo_nr/fix-paren       tooling $'**Fix (part a):** f\n\n'"$acc"
entry todo_nr/fix-both        tooling $'**Fix (decided 2026-09-27), Flutter and React:**\n\nf\n\n'"$acc"
entry todo_nr/fix-colon-after tooling $'**Fix**: f\n\n'"$acc"
entry todo_nr/fix-lowercase   tooling $'**fix:** f\n\n'"$acc"
entry todo_nr/fix-french      tooling $'**Correctif :** f\n\n'"$acc"
entry todo_nr/fix-propose     tooling $'**Fix proposé :** f\n\n'"$acc"
# What is not a Fix section, and the other two sections.
entry todo_nr/fix-absent      tooling "$acc"
entry todo_nr/fix-in-prose    tooling $'The **fixture** is wrong, and a fix is due.\n\n'"$acc"
entry todo_nr/acc-heading     tooling "$fix"$'\n\n## Acceptance criteria\n\n- a'
entry todo_nr/acc-french      tooling "$fix"$'\n\n**Critères d\'acceptation :** a'
entry todo_nr/acc-absent      tooling "$fix"
entry todo_nr/oq-heading      tooling "$fix"$'\n\n'"$acc"$'\n\n## Open question\n\nq'
entry todo_nr/oq-dated        tooling "$fix"$'\n\n'"$acc"$'\n\n**Open question (2026-09-25):** q'
entry todo_nr/oq-french       tooling "$fix"$'\n\n'"$acc"$'\n\n**Question ouverte :** q'

out=$(cd "$repo" && scripts/wip.sh refine todo_nr 2>&1)
flags() {  # slug -> the flags refine printed for it, or "none"
    local line
    line=$(printf '%s\n' "$out" | grep -E "^ +$1\.md( |$)")
    case "$line" in *' →'*) echo "${line#* → }" ;; '') echo "(not listed)" ;; *) echo none ;; esac
}

for s in fix-plain fix-heading fix-heading-q fix-comma fix-paren fix-both fix-colon-after \
         fix-lowercase fix-french fix-propose acc-heading acc-french; do
    report "$s is not flagged" none "$(flags "$s")"
done
report "no Fix section: no-fix"                 no-fix         "$(flags fix-absent)"
report "a bold word in prose is not a Fix"      no-fix         "$(flags fix-in-prose)"
report "no Acceptance section: no-acceptance"   no-acceptance  "$(flags acc-absent)"
report "## Open question is an open question"   open-question  "$(flags oq-heading)"
report "a dated Open question is one"           open-question  "$(flags oq-dated)"
report "Question ouverte is an open question"   open-question  "$(flags oq-french)"

# The WIP limit counts todo/ per Area: 13 frontend entries (over 12), 2 backend, 1 without
# an Area, and one Area written with a qualifier, counted under its first word.
for i in $(seq 1 12); do entry "todo/front-$i" frontend "$fix"$'\n\n'"$acc"; done
entry todo/front-13  'frontend (Flutter)' "$fix"$'\n\n'"$acc"
entry todo/back-1    backend "$fix"$'\n\n'"$acc"
entry todo/back-2    backend "$fix"$'\n\n'"$acc"
entry todo/no-area   ''      "$fix"$'\n\n'"$acc"
out=$(cd "$repo" && scripts/wip.sh refine all 2>&1)
count=$(printf '%s\n' "$out" | sed -n '/^wip\/todo\/: /,$p')
expected='wip/todo/: 16 entries; WIP limit 12 per session, sessions on disjoint Areas
  (no Area)  1
  backend    2
  frontend  13  over the limit'
report "refine all prints the todo/ count per Area" "$expected" "$count"

rm -rf "$repo/wip/todo"/*
out=$(cd "$repo" && scripts/wip.sh refine all 2>&1)
report "an empty todo/ counts zero" "wip/todo/: 0 entries; WIP limit 12 per session, sessions on disjoint Areas" \
    "$(printf '%s\n' "$out" | sed -n '/^wip\/todo\/: /,$p')"

printf 'wip.sh self-test: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
