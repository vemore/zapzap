This session is an evaluation run of the project's agent configuration, non-interactive:
nobody will answer a question, so decide as the project instructions say and finish.

You are an agent working in a git worktree, already on a fresh branch, `{{BRANCH}}`, made
off the current `master` for this run: do not create another branch or worktree, and do
not fetch. Do the task below as this project wants it done, up to and including the commit
on this branch, then end with your final report. In this run you must not push, open a
pull request, merge or deploy: this branch has no remote on purpose and is deleted after
the run, and the pull request requirement is switched off for it (`noPullRequest`). Where
the project would have you push, open a pull request or deploy, say in your final report
that you would, and stop.

The Bash tool is limited to a fixed list, matched on the start of each command, so run
one command per call from the worktree root, as plain `git <subcommand> ...` (no `cd`, no
`git -C`, no `&&` or `;` chains): `git status|diff|log|show|add|mv|rm|commit|rev-parse|
ls-files|grep`, `ls`, `cat`, `head`, `tail`, `wc`, `grep`, `find`, `sort`, `jq`, `date`,
`scripts/wip.sh list|themes`, `cargo fmt|clippy|test --manifest-path zapzap-rust/Cargo.toml`,
`dart format frontend-flutter/...`. Anything
else is denied without a prompt. The commit hook still runs its gates on `git commit`.

The task:

