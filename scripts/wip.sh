#!/bin/bash

# ZapZap - read the wip/ work tracker.
#
# wip/ is local: gitignored, and held only by the main checkout, so this resolves
# it there even when run from a worktree. There is deliberately no index file: this
# builds the view from the entries themselves.
#
# Usage: scripts/wip.sh [list] [todo|todo_nr|done|all]   entries, grouped by theme
#        scripts/wip.sh themes [todo|todo_nr|all]         themes with their entry count
#        scripts/wip.sh check [todo|todo_nr|done|all]     entries missing a header field
#        scripts/wip.sh refine [todo|todo_nr|all]         signals for a refinement pass
#                                                         (wip-refine skill)
#        scripts/wip.sh init                              create wip/ and its README
#        scripts/wip.sh path                              print the wip/ directory
#
# Default: list todo; check reads all.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The main checkout is the worktree that owns the shared .git directory.
ROOT="$(cd "$(git -C "$HERE" rev-parse --git-common-dir)/.." && pwd)"
WIP="$ROOT/wip"

case "${1:-}" in
    path) echo "$WIP"; exit 0 ;;
    init)
        mkdir -p "$WIP/todo" "$WIP/todo_nr" "$WIP/done" "$WIP/assets"
        [ -e "$WIP/README.md" ] || cp "$HERE/docs/wip-README.md" "$WIP/README.md"
        echo "$WIP ready"; exit 0 ;;
esac

cmd="${1:-list}"
case "$cmd" in list|themes|check|refine) shift || true ;; *) cmd=list ;; esac
default=todo; [ "$cmd" = check ] && default=all
scope="${1:-$default}"
case "$scope" in
    all) dirs=(todo todo_nr done) ;;
    todo|todo_nr|done) dirs=("$scope") ;;
    *) echo "unknown scope: $scope (todo, todo_nr, done, all)" >&2; exit 2 ;;
esac

field() {  # file, field name
    sed -n "s/^- \*\*$2:\*\* *//p" "$1" | head -1
}

rows() {  # prints: folder<TAB>theme<TAB>blocks<TAB>area<TAB>file<TAB>title
    local folder file
    for folder in "${dirs[@]}"; do
        for file in "$WIP/$folder"/*.md; do
            [ -e "$file" ] || continue
            case "$(basename "$file")" in ARCHIVE-*) continue ;; esac
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$folder" \
                "$(field "$file" Theme | cut -d' ' -f1)" \
                "$(field "$file" 'Blocks release')" \
                "$(field "$file" Area)" \
                "${file#"$ROOT"/}" \
                "$(sed -n 's/^# //p' "$file" | head -1)"
        done
    done
}

fields() {  # rows with "-" for an empty field: `read` with a tab IFS merges empty ones
    rows | sed -e 's/\t\t/\t-\t/g' -e 's/\t\t/\t-\t/g' -e 's/\t$/\t-/'
}

case "$cmd" in
    list)
        rows | sort -t$'\t' -k1,1 -k2,2 -k5,5 | awk -F'\t' '
            $1 != folder { if (folder != "") print ""; folder = $1; theme = ""; print "wip/" folder "/" }
            $2 != theme  { theme = $2; print "  [" (theme == "" ? "no theme" : theme) "]" }
            { flag = ($3 ~ /^yes/) ? "!" : " "; printf "   %s %-8s %s\n       %s\n", flag, $4, $6, $5 }'
        echo
        echo "! = blocks the release"
        ;;
    themes)
        rows | awk -F'\t' '{ n[$1 "\t" $2]++ } END { for (k in n) print k "\t" n[k] }' | sort \
            | awk -F'\t' '{ printf "%-8s %-28s %d\n", $1, ($2 == "" ? "(none)" : $2), $3 }'
        ;;
    check)
        out=$(fields | while IFS=$'\t' read -r folder theme blocks area file title; do
            missing=""
            [ "$title" = - ] && missing="$missing title"
            [ "$theme" = - ] && missing="$missing Theme"
            [ "$area" = - ] && missing="$missing Area"
            [ "$folder" != done ] && [ "$blocks" = - ] && missing="$missing Blocks-release"
            [ "$folder" = done ] && ! grep -Eq '^(- )?\*\*Status:\*\* (done|dropped)' "$ROOT/$file" && missing="$missing Status"
            [ -n "$missing" ] && echo "$file: missing$missing"
        done)
        [ -z "$out" ] && exit 0
        echo "$out" >&2
        exit 1
        ;;
    refine)
        # Mechanical signals only; the judgement is the wip-refine skill's.
        [ "$scope" = done ] && { echo "refine reads open entries: todo, todo_nr or all" >&2; exit 2; }
        today=$(date +%s)
        days_since() { echo $(( (today - $(date -d "$1" +%s 2>/dev/null || echo "$today")) / 86400 )); }
        fields | grep -v '^done'$'\t' | sort -t$'\t' -k1,1 -k2,2 -k5,5 \
            | while IFS=$'\t' read -r folder theme blocks area file title; do
            path="$ROOT/$file"
            noted=$(field "$path" Noted | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')
            touched=$(date -r "$path" +%Y-%m-%d 2>/dev/null)   # untracked: the file's mtime
            age=$([ -n "$noted" ] && days_since "$noted" || echo "?")
            idle=$([ -n "$touched" ] && days_since "$touched" || echo "new")
            flags=""
            grep -q '^\*\*Acceptance:\*\*' "$path" || flags="$flags no-acceptance"
            grep -q '^\*\*Fix:\*\*' "$path" || flags="$flags no-fix"
            grep -q '^\*\*Open question:\*\*' "$path" && flags="$flags open-question"
            [ "$idle" != new ] && [ "$idle" -gt 60 ] && flags="$flags stale"
            # Repository paths quoted in backticks that no longer exist.
            dead=$(grep -oE '`(zapzap-rust|native|frontend|src|scripts|tests|data|nginx|\.claude|\.llmwiki|\.github)/[^` :]*`' "$path" \
                | tr -d '`' | sed 's/[.,;)]*$//' | sort -u | while read -r p; do
                    case "$p" in *'*'*|*'<'*|*'{'*) continue ;; esac
                    [ -e "$ROOT/$p" ] || echo "$p"
                done | tr '\n' ' ')
            [ -n "$dead" ] && flags="$flags dead-path:[${dead% }]"
            # Links to entries that are already closed.
            closed=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+' "$path" | sort -u | while read -r slug; do
                    [ "$(basename "$file" .md)" = "$slug" ] && continue
                    [ -e "$WIP/done/$slug.md" ] && echo "$slug"
                done | tr '\n' ' ')
            [ -n "$closed" ] && flags="$flags links-closed:[${closed% }]"
            [[ "$blocks" =~ ^yes ]] && flags="$flags BLOCKS-RELEASE"
            printf '%-7s %-22s age %3sd idle %3sd  %s\n        %s\n' \
                "$folder" "$theme" "$age" "$idle" "$title" "$(basename "$file")${flags:+ →$flags}"
        done
        echo
        rows | grep -v '^done'$'\t' | awk -F'\t' '{ n[$2]++; t++ } END {
            for (k in n) if (n[k] > 4) printf "crowded theme: %s (%d entries) — look for merges\n", k, n[k]
            printf "%d open entries\n", t }'
        [ -d "$WIP/todo" ] && printf "wip/todo/: %d of a WIP limit of 12\n" "$(find "$WIP/todo" -name '*.md' | wc -l)"
        ;;
esac
