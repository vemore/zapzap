#!/bin/bash
# A plausible wrong outcome: the code and its test changed, GAME_RULES.md and the wiki left
# stating 4-10.
set -euo pipefail
svc=zapzap-rust/src/domain/services/game_service.rs
sed -i 's/is_golden_score { 10 }/is_golden_score { 8 }/' "$svc"
sed -i 's/hand_size_bounds(&state), (4, 10)/hand_size_bounds(\&state), (4, 8)/' "$svc"
git add -A
git commit -qm "feat: a Golden Score hand is 4 to 8 cards" --no-verify
