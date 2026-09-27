#!/bin/bash
# The right outcome, done by hand: selftest.sh expects check.sh to pass on it.
set -euo pipefail
day=$(date +%F)
sed -i "s/(auth required, no party-membership check; route/(party members only, \`require_party_member\`; route/; s/^> Updated: .*/> Updated: $day/" .llmwiki/Bots.md
sed -i -E "/^\| \[\[Bots\]\] \|/ s/\| [0-9-]+ \|\$/| $day |/" .llmwiki/INDEX.md
git add -A
git commit -qm "docs: trigger-bot is for party members only (require_party_member)" --no-verify
