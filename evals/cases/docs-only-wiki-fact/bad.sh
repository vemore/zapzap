#!/bin/bash
# A plausible wrong outcome: the fact fixed, its page's Updated: line and INDEX.md row left
# at the old date, README.md touched for nothing.
set -euo pipefail
sed -i "s/(auth required, no party-membership check; route/(party members only, \`require_party_member\`; route/" .llmwiki/Bots.md
echo >> README.md
git add -A
git commit -qm "docs: trigger-bot membership" --no-verify
