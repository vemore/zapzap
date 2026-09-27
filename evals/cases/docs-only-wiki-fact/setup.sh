#!/bin/bash
# Plant the stale wording of 2026-09-24 back into Bots.md, and date the page and its
# INDEX.md row 2026-09-20 so a correct fix has to move both dates.
# Run from the root of the throwaway worktree, before the fixture commit.
set -euo pipefail
sed -i 's/(party members only, `require_party_member`; route/(auth required, no party-membership check; route/' .llmwiki/Bots.md
sed -i -E 's/^> Updated: .*/> Updated: 2026-09-20/' .llmwiki/Bots.md
sed -i -E '/^\| \[\[Bots\]\] \|/ s/\| [0-9-]+ \|$/| 2026-09-20 |/' .llmwiki/INDEX.md
grep -q 'no party-membership check' .llmwiki/Bots.md
grep -q '^> Updated: 2026-09-20' .llmwiki/Bots.md
grep -Eq '^\| \[\[Bots\]\] \|.*\| 2026-09-20 \|$' .llmwiki/INDEX.md
