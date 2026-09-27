#!/bin/bash
# check.sh <worktree> [<base>]: see evals/lib.sh
. "$(dirname "$0")/../../lib.sh"
ev_init "$@"

bots="$WT/.llmwiki/Bots.md"
day=$(work_date)

assert_not "Bots.md no longer says 'no party-membership check'" grep -q 'no party-membership check' "$bots"
assert "the trigger-bot line names require_party_member" \
    bash -c "grep 'trigger-bot' '$bots' | grep -q 'require_party_member'"
assert "Bots.md Updated: is the day of the change ($day)" grep -q "^> Updated: $day" "$bots"
assert "INDEX.md row for Bots is dated $day" grep -Eq "^\| \[\[Bots\]\] \|.*\| $day \|\$" "$WT/.llmwiki/INDEX.md"
assert "README.md untouched" g diff --quiet "$BASE" -- README.md
assert_only_paths "only the wiki changed" '\.llmwiki/'
assert_committed
ev_done
