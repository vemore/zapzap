#!/bin/bash
# The right outcome, done by hand: selftest.sh expects check.sh to pass on it.
set -euo pipefail
svc=zapzap-rust/src/domain/services/game_service.rs
sed -i 's/4-10 in Golden Score/4-8 in Golden Score/' GAME_RULES.md README.md
sed -i 's/is_golden_score { 10 }/is_golden_score { 8 }/; s/4-7, 4-10 in Golden Score/4-7, 4-8 in Golden Score/' "$svc"
sed -i 's/hand_size_bounds(&state), (4, 10)/hand_size_bounds(\&state), (4, 8)/' "$svc"
sed -i 's/4-10 in Golden Score/4-8 in Golden Score/g' .llmwiki/GameRules.md
git add -A
git commit -qm "feat: a Golden Score hand is 4 to 8 cards" --no-verify
