#!/bin/bash
# Nothing to plant: the rule as master states it is the starting point. Fail loudly the day
# master changes it, rather than judge an agent against a rule that is gone.
set -euo pipefail
grep -q '4-10 in Golden Score' GAME_RULES.md
grep -q '4-10 in Golden Score' README.md
grep -q 'is_golden_score { 10 }' zapzap-rust/src/domain/services/game_service.rs
grep -q 'hand_size_bounds(&state), (4, 10)' zapzap-rust/src/domain/services/game_service.rs
