#!/bin/bash
#
# Self-test of the eval checks, no agent and no cost: for each case, the check must judge
#   - the untouched tree as case.env's UNTOUCHED says (run.sh --dry-run),
#   - the hand-made right outcome (good.sh) as a pass,
#   - the hand-made wrong outcome (bad.sh) as a fail.
# A check that passes everything or fails everything is caught here, before it is trusted
# to judge an agent. Run it after editing a check, a fixture or evals/lib.sh.
#
# Usage: evals/selftest.sh [--ref <ref>] [case...]     (default ref: HEAD)

set -uo pipefail
EVALS="$(cd "$(dirname "$0")" && pwd)"
ref=HEAD
args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --ref) ref="${2:?}"; shift ;;
        -h|--help) sed -n '3,11p' "$0"; exit 0 ;;
        *) args+=("$1") ;;
    esac
    shift
done
[ ${#args[@]} -gt 0 ] || mapfile -t args < <("$EVALS/run.sh" --list | awk '{print $1}')

bad=0
for c in "${args[@]}"; do
    for m in dry good bad; do
        case "$m" in
            dry) flags=(--dry-run); want=0 ;;
            good) flags=(--fixture good); want=0 ;;
            bad) flags=(--fixture bad); want=1 ;;
        esac
        "$EVALS/run.sh" "${flags[@]}" --ref "$ref" "$c" > /dev/null 2>&1
        got=$?
        if [ "$got" = "$want" ]; then printf 'ok   %-32s %s\n' "$c" "$m"
        else printf 'FAIL %-32s %s (run.sh exit %s, want %s)\n' "$c" "$m" "$got" "$want"; bad=$((bad + 1)); fi
    done
done
echo
[ "$bad" = 0 ] && { echo "selftest: all checks judge their fixtures right"; exit 0; }
echo "selftest: $bad wrong verdict(s); rerun one with evals/run.sh --fixture good|bad <case> to see it"
exit 1
