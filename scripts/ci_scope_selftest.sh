#!/bin/bash

# ZapZap - self-test of scripts/ci_scope.sh. Each case: the changed paths, then
# the expected flags as rust native frontend image hooks (1 = true).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
n=0

check() {  # expected "r n f i h", then paths
    local expected="$1"; shift
    local got
    got=$(printf '%s\n' "$@" | "$HERE/ci_scope.sh" | sed 's/.*=//' | sed 's/true/1/;s/false/0/' | tr '\n' ' ' | sed 's/ $//')
    n=$((n + 1))
    if [ "$got" != "$expected" ]; then
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected %s, got %s\n' "$*" "$expected" "$got"
    fi
}

check "0 0 0 0 0" "README.md"
check "0 0 0 0 0" ".llmwiki/Api.md" "CLAUDE.md"
check "0 0 0 0 0" ".claude/skills/ship-parallel/SKILL.md"
check "1 0 0 1 0" "zapzap-rust/src/main.rs"
check "1 0 0 1 0" "zapzap-rust/Cargo.lock"
check "1 0 0 0 0" "data/thibot_genetic_params.json"
check "0 1 0 0 0" "native/src/headless_engine.rs"
check "0 0 1 1 0" "frontend/src/App.jsx"
check "0 0 0 1 0" "nginx/nginx.conf"
check "0 0 0 0 0" "src/api/app.js" "package-lock.json"
check "1 1 1 1 1" ".github/workflows/ci.yml"
check "0 0 0 0 1" ".claude/hooks/guard-bash.sh"
check "1 1 1 1 1" "scripts/ci_scope.sh"
check "1 1 1 1 1" "some-new-dir/file"
check "1 0 1 1 0" "zapzap-rust/src/lib.rs" "frontend/package.json"
check "0 0 0 0 1" ".claude/settings.json" "scripts/wip.sh"
check "0 0 0 0 0" "docs/wip-README.md"
check "0 0 0 0 0"   # no paths at all

echo "ci_scope: $((n - fail))/$n cases pass"
[ "$fail" -eq 0 ]
