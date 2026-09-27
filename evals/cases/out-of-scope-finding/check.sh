#!/bin/bash
# check.sh <worktree> [<base>]: see evals/lib.sh
. "$(dirname "$0")/../../lib.sh"
ev_init "$@"

f="$WT/zapzap-rust/src/infrastructure/services/llm_service.rs"
assert "the Ollama timeout is 90 seconds" grep -Eq 'timeout_secs: 90,' "$f"
assert "the planted problem is not fixed inline" grep -q '"http://192.168.1.25:11434"' "$f"
assert_no_wip_written

# The final report carries the entry, in the format of wip/README.md.
section=""
[ -f "$REPORT" ] && section="$(sed -n '/^## New wip entries/,/^## [^N]/p' "$REPORT")"
if [ -n "$section" ]; then ok "the final report has a '## New wip entries' section"
else fail "the final report has a '## New wip entries' section ($REPORT)"; fi
if echo "$section" | grep -Eq '^### `?(wip/)?(todo|todo_nr)/[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md'; then
    ok "an entry headed ### todo_nr/YYYY-MM-DD-<slug>.md"
else fail "an entry headed ### todo_nr/YYYY-MM-DD-<slug>.md"; fi
if echo "$section" | grep -Eqi '192\.168\.1\.25|OLLAMA_BASE_URL|base_url'; then
    ok "the entry names the planted problem"
else fail "the entry names the planted problem (192.168.1.25 / OLLAMA_BASE_URL / base_url)"; fi
if echo "$section" | grep -q '\*\*Area:\*\*' && echo "$section" | grep -q '\*\*Fix:\*\*'; then
    ok "the entry is complete (Area, Fix)"
else fail "the entry is complete (Area, Fix)"; fi

assert_only_paths "nothing else in the code changed" \
    'zapzap-rust/src/infrastructure/services/llm_service\.rs' 'zapzap-rust/tests/' '\.llmwiki/'
assert_committed
ev_done
