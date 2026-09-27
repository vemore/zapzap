#!/bin/bash

# ZapZap - shared dead-backticked-repository-path finder.
#
# A backticked repository path (`zapzap-rust/src/main.rs`, `scripts/wip.sh`) that no longer
# exists is a stale reference left by a rename or a delete. This is the one piece of logic
# shared between scripts/wip.sh `refine` (wip/ entries) and scripts/wiki_lint.sh
# (.llmwiki/ pages): both grep the same top-level directories out of backticks and stat
# what is left. A path relative to a subdirectory (`src/main.rs`, `lib/main.dart`) is not
# matched: only the repository's own top-level directories are.
#
# Usage: source this file, then call `dead_repo_paths <root> <file>`; it prints the dead
# paths found in <file>, one per line, relative to <root>. Requires bash (the `case`
# glob-skip below), grep -E, sed and git.

dead_repo_paths() {  # root, file -> dead paths (one per line), relative to root
    local root="$1" file="$2"
    grep -oE '`(zapzap-rust|native|frontend|frontend-flutter|scripts|data|nginx|docs|store_listing|\.claude|\.llmwiki|\.github)/[^` :]*`' "$file" \
        | tr -d '`' | sed 's/[.,;)]*$//' | sort -u | while read -r p; do
            case "$p" in *'*'*|*'<'*|*'{'*) continue ;; esac
            [ -e "$root/$p" ] && continue
            # A gitignored path (`data/zapzap.db`, `scripts/deploy.env`) names a local file a
            # fresh checkout lacks by design, not a stale reference. The second form catches a
            # directory named without its slash against a `dir/` pattern.
            git -C "$root" check-ignore -q -- "$p" 2>/dev/null && continue
            git -C "$root" check-ignore -q -- "${p%/}/" 2>/dev/null && continue
            echo "$p"
        done
}
