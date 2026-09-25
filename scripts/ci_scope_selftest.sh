#!/bin/bash

# ZapZap - self-test of scripts/ci_scope.sh. Each case: the changed paths, then
# the expected flags as rust native frontend image hooks flutter node parity e2e (1 = true).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
n=0

check() {  # expected "r n f i h fl no pa e2e", then paths
    local expected="$1"; shift
    local got
    got=$(printf '%s\n' "$@" | "$HERE/ci_scope.sh" | sed 's/.*=//' | sed 's/true/1/;s/false/0/' | tr '\n' ' ' | sed 's/ $//')
    n=$((n + 1))
    if [ "$got" != "$expected" ]; then
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected %s, got %s\n' "$*" "$expected" "$got"
    fi
}

check "0 0 0 0 0 0 0 0 0" "README.md"
check "0 0 0 0 0 0 0 0 0" ".llmwiki/Api.md" "CLAUDE.md"
check "0 0 0 0 0 0 0 0 0" ".claude/skills/ship-parallel/SKILL.md"
check "1 0 0 1 0 0 0 1 1" "zapzap-rust/src/main.rs"
check "1 0 0 1 0 0 0 1 1" "zapzap-rust/Cargo.lock"
check "1 0 0 1 0 0 1 1 1" "zapzap-rust/src/infrastructure/auth/password.rs"
check "1 0 0 1 0 0 1 1 1" "zapzap-rust/tests/fixtures/bcrypt_node_compat.json"
check "1 0 0 0 0 0 0 0 0" "data/thibot_genetic_params.json"
check "0 1 0 0 0 0 0 0 0" "native/src/headless_engine.rs"
check "0 0 1 1 0 0 0 0 0" "frontend/src/App.jsx"
check "0 0 0 1 0 0 0 0 0" "nginx/nginx.conf"
check "0 0 0 1 0 0 1 1 1" "src/api/app.js" "package-lock.json"
check "0 0 0 1 0 0 1 1 1" "package.json"
check "0 0 0 1 0 0 1 1 1" "src/infrastructure/database/sqlite/connection.js"
check "0 0 0 1 0 0 1 1 1" "app.js" "logger.js"
check "0 0 0 0 0 0 1 0 0" "tests/unit/use-cases/auth/LoginUser.test.js"
check "0 0 0 0 0 0 1 0 0" "jest.config.js"
check "0 0 0 1 0 0 0 0 0" "Dockerfile"
check "0 0 0 1 0 0 0 0 0" ".dockerignore" "views/index.ejs" "public/style.css"
check "0 0 0 0 0 0 0 0 0" "playwright.config.js" "eslint.config.mjs"
check "0 0 0 0 1 0 0 0 0" "deploy.sh"
check "0 0 0 0 1 0 0 0 0" "rebuild.sh"
check "0 0 0 0 1 0 0 0 0" "deploy.sh" "rebuild.sh" "scripts/hooks_selftest.sh"
check "1 1 1 1 1 1 1 1 1" "docker-compose.yml"
check "1 1 1 1 1 1 1 1 1" "some-root-script.sh"
check "1 1 1 1 1 1 1 1 1" ".github/workflows/ci.yml"
check "0 0 0 0 1 0 0 0 0" ".claude/hooks/guard-bash.sh"
check "1 1 1 1 1 1 1 1 1" "scripts/ci_scope.sh"
check "0 0 0 0 0 0 0 0 1" "scripts/flutter_e2e.sh"
check "1 1 1 1 1 1 1 1 1" "some-new-dir/file"
check "1 0 1 1 0 0 0 1 1" "zapzap-rust/src/lib.rs" "frontend/package.json"
check "0 0 0 0 1 0 0 0 0" ".claude/settings.json" "scripts/wip.sh"
check "0 0 0 0 0 0 0 0 0" "docs/wip-README.md"
check "0 0 0 0 0 0 0 1 0" "tests/parity/parity.test.js" "tests/parity/divergences.json"
check "0 0 0 0 0 0 1 1 0" "tests/parity/lib/game.js" "tests/unit/api/bootstrap.test.js"
check "0 0 0 1 0 0 0 0 0" "scripts/pwa_image_smoke.sh"
check "0 0 0 1 0 0 0 0 0" "scripts/backend_image_smoke.sh"
check "0 0 0 1 0 1 0 0 1" "frontend-flutter/lib/main.dart"
check "0 0 0 1 0 1 0 0 1" "frontend-flutter/pubspec.yaml" "frontend-flutter/pubspec.lock"
check "0 0 0 1 0 1 0 0 1" "frontend-flutter/android/app/build.gradle.kts" "frontend-flutter/lib/l10n/app_fr.arb"
check "0 0 0 1 0 1 0 0 1" "frontend-flutter/Dockerfile" "frontend-flutter/nginx.conf"
check "0 0 0 0 0 0 0 0 0" "frontend-flutter/README.md"
check "0 0 1 1 0 1 0 0 1" "frontend/src/App.jsx" "frontend-flutter/lib/app.dart"
check "1 0 0 1 0 1 0 1 1" "zapzap-rust/src/main.rs" "frontend-flutter/test/app_test.dart"
# The production backend's image (zapzap-rust/Dockerfile) and the production compose file.
check "1 0 0 1 0 0 0 1 1" "zapzap-rust/Dockerfile"
check "0 0 0 0 0 0 0 0 0" "zapzap-rust/README.md"
# The rollback backend: jest, its image, the parity suite, and the end-to-end run whose
# bots scripts/init-bots.js seeds through src/.
check "0 0 0 1 0 0 1 1 1" "src/api/bootstrap.js"
check "0 0 0 1 0 0 1 1 1" "src/domain/entities/User.js"
check "0 0 0 0 0 0 0 0 0"   # no paths at all

echo "ci_scope: $((n - fail))/$n cases pass"
[ "$fail" -eq 0 ]
