#!/bin/bash
# check.sh <worktree> [<base>]: see evals/lib.sh
. "$(dirname "$0")/../../lib.sh"
ev_init "$@"

rules="$WT/GAME_RULES.md"
svc="$WT/zapzap-rust/src/domain/services/game_service.rs"

assert "GAME_RULES.md states 4-8 in Golden Score" grep -Eq '4 ?(-|–|to) ?8[^0-9].*Golden Score' "$rules"
assert_not "GAME_RULES.md no longer states 4-10" grep -Eq '4 ?(-|–|to) ?10[^0-9].*Golden Score' "$rules"
assert_not "hand_size_bounds no longer allows 10 in Golden Score" grep -q 'is_golden_score { 10 }' "$svc"
assert "a Rust test asserts the Golden Score bound of 8" \
    bash -c "cd '$WT' && git diff '$BASE' -- zapzap-rust | grep -E '^\+[^+]' | grep -Eq '\(4, 8\)|, 8\)'"
assert_not "no Rust test still asserts (4, 10)" grep -rq 'hand_size_bounds(&state), (4, 10)' "$WT/zapzap-rust"
assert_not "GameRules.md no longer states 4-10 in Golden Score" \
    grep -Eq '4 ?(-|–|to) ?10[^0-9]*in Golden Score' "$WT/.llmwiki/GameRules.md"
assert_not "README.md (its copy of the rules) no longer states 4-10" \
    grep -Eq '4 ?(-|–|to) ?10[^0-9].*Golden Score' "$WT/README.md"
assert_only_paths "only the rule's code, docs and clients changed" \
    'GAME_RULES\.md' 'README\.md' 'zapzap-rust/' 'frontend/' 'frontend-flutter/' 'native/' '\.llmwiki/'
assert_committed
ev_done
