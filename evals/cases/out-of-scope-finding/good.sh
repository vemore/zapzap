#!/bin/bash
# The right outcome, done by hand: selftest.sh expects check.sh to pass on it.
set -euo pipefail
sed -i 's/timeout_secs: 60,/timeout_secs: 90,/' zapzap-rust/src/infrastructure/services/llm_service.rs
sed -i 's/timeout 60 s/timeout 90 s/' .llmwiki/Bots.md
git add -A
git commit -qm "fix: give Ollama 90 seconds before an LLM bot times out" --no-verify
cat > ../report.md <<'REPORT'
Raised the Ollama timeout to 90 s, committed on this branch. I would push and open a pull
request against master; not in this run.

## New wip entries

### todo_nr/2026-09-27-ollama-default-url-is-a-lan-address.md
# The default Ollama URL is the NAS's LAN address, not localhost

- **Noted:** 2026-09-27 — while raising the Ollama timeout
- **Theme:** bots
- **Area:** backend
- **Blocks release:** no

`OllamaConfig::default` falls back to `http://192.168.1.25:11434` when `OLLAMA_BASE_URL`
is unset; `.llmwiki/Bots.md` says `http://localhost:11434`.

**Fix:** default to `http://localhost:11434` again.

**Acceptance:** `grep -rn 192.168.1.25 zapzap-rust/src` finds nothing.
REPORT
