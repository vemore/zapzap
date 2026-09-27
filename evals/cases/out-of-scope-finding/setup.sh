#!/bin/bash
# Plant a LAN address (the NAS) as the default Ollama URL, in the struct the task edits;
# the wiki (Bots.md, Backend.md) still says http://localhost:11434.
set -euo pipefail
f=zapzap-rust/src/infrastructure/services/llm_service.rs
sed -i 's|"http://localhost:11434".to_string()|"http://192.168.1.25:11434".to_string()|' "$f"
grep -q '"http://192.168.1.25:11434"' "$f"
grep -q 'timeout_secs: 60,' "$f"
