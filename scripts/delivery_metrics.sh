#!/bin/bash

# ZapZap - delivery outcomes, from git and gh only (DORA-style).
#
# What the process changes are for, measured on what already exists: the commits on master,
# the pull requests and their CI runs, the wip/ entries. No tracking of its own. Printed by
# the ship-parallel §7 report, compared with the baseline in .llmwiki/ParallelDelivery.md
# § Measuring delivery.
#
# Usage: scripts/delivery_metrics.sh [since [until]]
#        since  YYYY-MM-DD, inclusive (default: the date of the last tag on the ref, else
#               30 days ago)
#        until  YYYY-MM-DD, exclusive (default: tomorrow, so today is in)
#        DELIVERY_METRICS_REF   the branch measured (default origin/master, else master)
#
# Prints:
#   fix: share          commits on the ref whose subject starts with fix
#   rework rate         changes followed within 48 h by a fix: touching one of their files
#   deployments         changes whose paths ship-parallel §4 deploys (zapzap-rust/,
#                       frontend-flutter/, nginx/, docker-compose.prod.yml; and frontend/,
#                       the React client removed on 2026-09-29, for the history before) --
#                       derived, not read from the NAS
#   change failure rate deployments followed within 48 h by a fix: touching their files
#   first-run-green     merged pull requests whose first CI run succeeded (gh; a cancelled
#                       first run counts as not green: a push superseded it)
#   size                added-or-modified lines per change, with the exclusion list of the
#                       ship-parallel §3.1 counter (docs, locks, tests, translated ARB
#                       files) and wip/
#   wip/                open entries per folder and their age; entries closed in the window
#                       and their age at close (a lead-time proxy). wip/ is the main
#                       checkout's, found from any worktree.
# "Touching the same files" uses the same exclusion list: the wiki (*.md) and wip/ are
# touched by nearly every change and would make every fix look like rework.

set -uo pipefail

case "${1:-}" in -h|--help) sed -n '3,32p' "$0"; exit 0 ;; esac

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not in a git repository" >&2; exit 2; }
cd "$ROOT" || exit 2
# wip/ is local to the main checkout, the worktree that owns the shared .git directory.
MAIN=$(cd "$(git rev-parse --path-format=absolute --git-common-dir)/.." && pwd)

REF="${DELIVERY_METRICS_REF:-origin/master}"
for candidate in "$REF" master HEAD; do
    if git rev-parse -q --verify "$candidate^{commit}" >/dev/null; then REF=$candidate; break; fi
done

is_date() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && date -d "$1" +%s >/dev/null 2>&1; }

tag=$(git describe --tags --abbrev=0 "$REF" 2>/dev/null || true)
since="${1:-}"
if [ -z "$since" ]; then
    if [ -n "$tag" ]; then since=$(git log -1 --format=%cs "$tag"); else since=$(date -d '30 days ago' +%F); fi
fi
until="${2:-$(date -d tomorrow +%F)}"
is_date "$since" || { echo "since: not a YYYY-MM-DD date: $since" >&2; exit 2; }
is_date "$until" || { echo "until: not a YYYY-MM-DD date: $until" >&2; exit 2; }
since_ts=$(date -d "$since" +%s)
until_ts=$(date -d "$until" +%s)
[ "$until_ts" -gt "$since_ts" ] || { echo "until must be after since" >&2; exit 2; }
days=$(( (until_ts - since_ts) / 86400 ))

# The ship-parallel §3.1 counter's exclusion list, verbatim (keep the two in step; the
# self-test checks it), its translated-ARB clause, and wip/. Handed to awk through the
# environment: `awk -v` would turn each `\.` into `.`.
export EXCLUDE='\.md$|\.lock$|package-lock\.json$|^zapzap-rust\/tests\/|\.test\.jsx?$|^tests\/|^frontend-flutter\/(test|integration_test)\/|_test\.dart$'
export ARB='^frontend-flutter\/lib\/l10n\/app_.*\.arb$'
export ARB_KEEP='\/app_(fr|en)\.arb$'
export WIP='^wip\/'
export BACKEND='^zapzap-rust\/'
export FRONTENDS='^frontend\/|^frontend-flutter\/|^nginx\/|^docker-compose\.prod\.yml$'

pct() { awk -v a="$1" -v b="$2" 'BEGIN { if (b > 0) printf "%d/%d  %.1f %%", a, b, 100 * a / b; else printf "0/0  n/a" }'; }

printf 'Delivery metrics — %s, %s .. %s (until exclusive), %d days\n' "$REF" "$since" "$until" "$days"

# --- Commits: fix: share, rework rate, deployments, change failure rate -------------------
# One pass over the window plus 48 h, so a fix just after the window still counts.
# The awk prints: changes fixes rework deployments backend pwa failed
read -r changes fixes rework deploys backend pwa failed < <(
    git -c core.quotepath=off log "$REF" --no-renames --name-only \
        --since="@$since_ts" --until="@$((until_ts + 172800))" --format='%x1e%H%x09%ct%x09%s' |
    awk -F'\t' -v since="$since_ts" -v until="$until_ts" '
        function excluded(p) {
            return p ~ ENVIRON["EXCLUDE"] || p ~ ENVIRON["WIP"] ||
                   (p ~ ENVIRON["ARB"] && p !~ ENVIRON["ARB_KEEP"])
        }
        /^\036/ { n++; ct[n] = $2; fix[n] = ($3 ~ /^fix(\(|!|:)/); files[n] = ""
               be[n] = 0; web[n] = 0; next }
        NF && n {
            if (excluded($0)) next      # tests, docs, locks: they deploy nothing either
            if ($0 ~ ENVIRON["BACKEND"]) be[n] = 1
            if ($0 ~ ENVIRON["FRONTENDS"]) web[n] = 1
            files[n] = files[n] "\n" $0
        }
        END {
            for (i = 1; i <= n; i++) {
                if (ct[i] < since || ct[i] >= until) continue
                c++; f += fix[i]
                d = be[i] || web[i]; dp += d; b += be[i]; w += web[i]
                if (files[i] == "") continue
                split(substr(files[i], 2), mine, "\n")
                hit = 0
                for (j = 1; j <= n && !hit; j++) {
                    if (j == i || !fix[j] || ct[j] <= ct[i] || ct[j] > ct[i] + 172800) continue
                    for (k in mine) if (index(files[j] "\n", "\n" mine[k] "\n")) { hit = 1; break }
                }
                r += hit; if (d) fl += hit
            }
            printf "%d %d %d %d %d %d %d\n", c, f, r, dp, b, w, fl
        }')

printf '  %-22s %s\n' "changes on master" "$changes"
printf '  %-22s %s\n' "fix: share" "$(pct "$fixes" "$changes")"
printf '  %-22s %s   (followed within 48 h by a fix: on the same files)\n' "rework rate" "$(pct "$rework" "$changes")"
printf '  %-22s %d  %s/week   (backend %d, frontends %d; derived from paths)\n' "deployments" "$deploys" \
    "$(awk -v d="$deploys" -v n="$days" 'BEGIN { printf "%.1f", n ? 7 * d / n : 0 }')" "$backend" "$pwa"
printf '  %-22s %s   (deployments followed within 48 h by a fix: on the same files)\n' \
    "change failure rate" "$(pct "$failed" "$deploys")"

# --- Size: added-or-modified lines per change (the §3.1 counter, per commit) --------------
sizes=$(git -c core.quotepath=off log "$REF" -p --no-renames --format='%x1e%H' \
        --since="@$since_ts" --until="@$until_ts" |
    awk '
        /^\036/ { if (seen) print n + 0; seen = 1; n = 0; keep = 0; next }
        /^diff --git / { p = $4; sub(/^b\//, "", p)
                         keep = p !~ ENVIRON["EXCLUDE"] && p !~ ENVIRON["WIP"] &&
                                (p !~ ENVIRON["ARB"] || p ~ ENVIRON["ARB_KEEP"]); next }
        keep && /^\+/ && !/^\+\+\+/ { n++ }
        END { if (seen) print n + 0 }' | sort -n)
if [ -n "$sizes" ]; then
    echo "$sizes" | awk '
        function rank(p,  i) { i = int(p * NR); if (i < p * NR) i++; return i < 1 ? 1 : i }  # nearest rank
        { v[NR] = $1
          if ($1 == 0) b0++; else if ($1 < 50) b1++; else if ($1 < 200) b2++
          else if ($1 < 500) b3++; else if ($1 < 1500) b4++; else b5++ }
        END {
            p50 = v[rank(0.5)]; p90 = v[rank(0.9)]
            printf "  %-22s p50 %d  p90 %d  max %d   (counted lines per change)\n", "size", p50, p90, v[NR]
            printf "  %-22s 0: %d  1-49: %d  50-199: %d  200-499: %d  500-1499: %d  >=1500: %d\n", \
                "size buckets", b0, b1, b2, b3, b4, b5
        }'
else
    printf '  %-22s n/a (no change in the window)\n' "size"
fi

# --- First-run-green: the first CI run of each merged pull request (gh) -------------------
last_day=$(date -d "$until -1 day" +%F)
if command -v gh >/dev/null 2>&1 &&
    prs=$(gh pr list --state merged --limit 1000 --search "merged:$since..$last_day" \
            --json number,headRefName,mergedAt -q '.[] | [.headRefName, .mergedAt] | @tsv' 2>/dev/null) &&
    runs=$(gh run list --workflow ci.yml --event pull_request --limit 1000 \
            --json headBranch,createdAt,conclusion -q '.[] | [.headBranch, .createdAt, .conclusion] | @tsv' 2>/dev/null); then
    oldest=$(printf '%s\n' "$runs" | cut -f2 | sort | head -1)
    green=$(awk -F'\t' '
        FNR == NR { if ($1 == "") next
                    if (!($1 in first) || $2 < first[$1]) { first[$1] = $2; concl[$1] = $3 }; next }
        $1 != "" { total++; if ($1 in first && first[$1] <= $2) { seen++; if (concl[$1] == "success") g++ } }
        END { printf "%d %d %d\n", g, seen, total }' <(printf '%s\n' "$runs") <(printf '%s\n' "$prs"))
    read -r g seen total <<<"$green"
    printf '  %-22s %s   (of %d merged pull requests with a CI run; %d merged)\n' \
        "first-run-green" "$(pct "$g" "$seen")" "$seen" "$total"
    [ -n "$oldest" ] && [[ "$oldest" > "$since" ]] &&
        printf '  %-22s the oldest CI run gh returned is %s: earlier pull requests are not counted\n' "" "${oldest%%T*}"
else
    printf '  %-22s n/a (gh unavailable or not authenticated)\n' "first-run-green"
fi

releases=$(git tag --merged "$REF" --format='%(creatordate:unix) %(refname:short)' |
    awk -v s="$since_ts" -v u="$until_ts" '$1 >= s && $1 < u { printf "%s%s", sep, $2; sep = ", " }')
printf '  %-22s %s\n' "releases (tags)" "${releases:-none}"

# --- wip/: open entries and their age, entries closed in the window ------------------------
today_ts=$(date -d "$(date +%F)" +%s)
echo "wip/ entries (age from the file name's date, as of today)"
for folder in todo todo_nr; do
    ls "$MAIN/wip/$folder" 2>/dev/null | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}-.*\.md$' |
    while read -r f; do echo $(( (today_ts - $(date -d "${f:0:10}" +%s)) / 86400 )); done | sort -n |
    awk -v folder="$folder" '
        { v[NR] = $1; if ($1 > 30) old++ }
        END {
            if (!NR) { printf "  %-10s 0 open\n", folder; exit }
            printf "  %-10s %d open   median %d d   max %d d   older than 30 d: %d\n", \
                folder, NR, v[int((NR - 1) / 2) + 1], v[NR], old
        }'
done
for f in "$MAIN"/wip/done/[0-9][0-9][0-9][0-9]-*.md; do
    [ -e "$f" ] || continue
    closed=$(grep -m1 -oE '\*\*Status:\*\* *done \([0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}') || continue
    c_ts=$(date -d "$closed" +%s)
    [ "$c_ts" -ge "$since_ts" ] && [ "$c_ts" -lt "$until_ts" ] || continue
    b=$(basename "$f")
    echo $(( (c_ts - $(date -d "${b:0:10}" +%s)) / 86400 ))
done | sort -n | awk '
    { v[NR] = $1 }
    END {
        if (!NR) { printf "  %-10s 0 closed in the window\n", "done"; exit }
        printf "  %-10s %d closed in the window   age at close: median %d d   max %d d\n", \
            "done", NR, v[int((NR - 1) / 2) + 1], v[NR]
    }'
