#!/bin/bash

# ZapZap - self-test of scripts/ci_scope.sh. Each case: the changed paths, then
# the expected flags as rust native frontend image hooks flutter e2e (1 = true).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
n=0

check() {  # expected "r n f i h fl e2e", then paths
    local expected="$1"; shift
    local got
    got=$(printf '%s\n' "$@" | "$HERE/ci_scope.sh" | sed 's/.*=//' | sed 's/true/1/;s/false/0/' | tr '\n' ' ' | sed 's/ $//')
    n=$((n + 1))
    if [ "$got" != "$expected" ]; then
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected %s, got %s\n' "$*" "$expected" "$got"
    fi
}

check "0 0 0 0 0 0 0" "README.md"
check "0 0 0 0 0 0 0" ".llmwiki/Api.md" "CLAUDE.md"
check "0 0 0 0 0 0 0" ".claude/skills/ship-parallel/SKILL.md"
check "1 0 0 1 0 0 1" "zapzap-rust/src/main.rs"
check "1 0 0 1 0 0 1" "zapzap-rust/Cargo.lock"
check "1 0 0 0 0 0 0" "data/thibot_genetic_params.json"
check "0 1 0 0 0 0 0" "native/src/headless_engine.rs"
check "0 0 1 1 0 0 0" "frontend/src/App.jsx"
check "0 0 0 1 0 0 0" "nginx/nginx.conf"
check "0 0 0 0 1 0 0" "scripts/deploy_nas.sh"
check "0 0 0 0 1 0 0" "rebuild.sh"
check "0 0 0 0 1 0 0" "scripts/deploy_nas.sh" "scripts/deploy_nas_selftest.sh" "scripts/deploy.env.example" "rebuild.sh" "scripts/hooks_selftest.sh" "scripts/generate_keystore.sh"
# The production compose file: parsed by the image job, read by the deploy self-test.
check "0 0 0 1 1 0 0" "docker-compose.prod.yml"
check "0 0 0 1 0 0 0" "nginx/Dockerfile"
check "1 1 1 1 1 1 1" "docker-compose.yml"
check "1 1 1 1 1 1 1" "some-root-script.sh"
check "1 1 1 1 1 1 1" ".github/workflows/ci.yml"
check "0 0 0 0 1 0 0" ".claude/hooks/guard-bash.sh"
check "1 1 1 1 1 1 1" "scripts/ci_scope.sh"
check "0 0 0 0 0 0 1" "scripts/flutter_e2e.sh"
check "1 1 1 1 1 1 1" "some-new-dir/file"
check "1 0 1 1 0 0 1" "zapzap-rust/src/lib.rs" "frontend/package.json"
check "0 0 0 0 1 0 0" ".claude/settings.json" "scripts/wip.sh"
check "0 0 0 0 0 0 0" "docs/wip-README.md"
check "0 0 0 1 0 0 0" "scripts/pwa_image_smoke.sh"
check "0 0 0 1 0 0 0" "scripts/backend_image_smoke.sh"
check "0 0 0 1 0 1 1" "frontend-flutter/lib/main.dart"
check "0 0 0 1 0 1 1" "frontend-flutter/pubspec.yaml" "frontend-flutter/pubspec.lock"
check "0 0 0 1 0 1 1" "frontend-flutter/android/app/build.gradle.kts" "frontend-flutter/lib/l10n/app_fr.arb"
check "0 0 0 1 0 1 1" "frontend-flutter/Dockerfile" "frontend-flutter/nginx.conf"
check "0 0 0 0 0 0 0" "frontend-flutter/README.md"
check "0 0 1 1 0 1 1" "frontend/src/App.jsx" "frontend-flutter/lib/app.dart"
check "1 0 0 1 0 1 1" "zapzap-rust/src/main.rs" "frontend-flutter/test/app_test.dart"
# The production backend's image (zapzap-rust/Dockerfile) and the production compose file.
check "1 0 0 1 0 0 1" "zapzap-rust/Dockerfile"
check "0 0 0 0 0 0 0" "zapzap-rust/README.md"
# The Rust password hashing and its bcrypt fixture: plain Rust backend paths.
check "1 0 0 1 0 0 1" "zapzap-rust/src/infrastructure/auth/password.rs" "zapzap-rust/tests/fixtures/bcrypt_node_compat.json"
# The root package.json holds only Playwright, which no job installs.
check "0 0 0 0 0 0 0" "package.json" "package-lock.json"
# The Node backend is gone: a path under its former directories is unclassified, so everything runs.
check "1 1 1 1 1 1 1" "src/api/app.js"
check "1 1 1 1 1 1 1" "tests/unit/use-cases/auth/LoginUser.test.js"
check "0 0 0 0 0 0 0"   # no paths at all

echo "ci_scope: $((n - fail))/$n cases pass"
[ "$fail" -eq 0 ]
