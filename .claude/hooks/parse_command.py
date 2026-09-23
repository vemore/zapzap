#!/usr/bin/env python3
"""Shared command parser for the ZapZap Claude Code hooks.

Reads a PreToolUse hook payload (JSON) on stdin and prints a JSON verdict on
stdout:

    {"parse_ok": bool,
     "blocks":   [{"rule": str, "message": str}, ...],
     "commit":   null | {"all": bool, "amend": bool, "pathspecs": [str, ...],
                         "cwd": str},
     "push":     null | {"refspecs": [str, ...], "remote": str | null, "cwd": str,
                         "known": bool}}

A `push-main` block also carries the push's `remote`, `cwd` and `known` (whether
that cwd could be told): the caller lifts the refusal when the remote is not this
project's -- a sandbox repository an agent built to test something.

`cwd` is the directory the git command actually runs in -- the hook payload's
cwd, followed through `cd` and `git -C`. The caller resolves the repository from
it, so a commit made inside a git worktree is judged on that worktree's branch
and gated on its files, not on the checkout the session was launched from.

Why a parser and not a grep: splitting a command on "&&" and ";" and then
matching substrings misfires on every quoting case -- `git commit -m "pkill
node"`, `echo "..."`, and above all a heredoc body that documents a
forbidden command. The refusals and the `git commit` detection need the same
tokenizer; duplicated across two scripts, they would drift apart silently.

Failure policy: an unparseable command yields no blocks (fail open -- a guard
that refuses every command it cannot read is worse than the risk it covers) but
parse_ok=false, which the caller treats as "assume a commit" (fail closed -- a
skipped gate is a silent regression, a spurious gate costs seconds).

The one exception is a commit or push whose repository cannot be told: a line
that fails to parse but holds a `cd` or `git -C`, or one whose `cd` / `git -C`
operand is a shell variable not bound to a literal earlier on the same line.
Judging the payload cwd there judges the wrong checkout -- the main one, on
`master` -- and the refusal would point at a stale-branch recovery that does not
apply. It yields an `unknown-repo` block that says so and asks for
`git -C <literal path>`.
"""

import json
import os
import posixpath
import re
import shlex
import sys

PROJECT_DIR = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())

# Shell keywords and command prefixes that may sit in front of the real command.
HEAD_NOISE = {
    "if", "then", "else", "elif", "fi", "do", "done", "while", "until", "for",
    "!", "time", "env", "sudo", "nohup", "command", "exec", "{", "}",
}

OPERATORS = {"&&", "||", ";", ";;", "|", "|&", "&", "(", ")", "\n"}
REDIRECTS = {">", ">>", "<", "<<", "2>", "2>>", "&>", ">&", "<<<"}

# `git` options that sit before the subcommand.
GIT_GLOBAL_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                       "--exec-path", "--super-prefix"}
GIT_GLOBAL_FLAG = {"-p", "-P", "--paginate", "--no-pager", "--bare", "--no-replace-objects",
                   "--literal-pathspecs", "--glob-pathspecs", "--noglob-pathspecs",
                   "--icase-pathspecs", "--no-optional-locks"}

# `git commit` options that consume the next token.
COMMIT_OPT_WITH_ARG = {"-m", "-F", "-C", "-c", "-t", "-S", "-u", "--message", "--file",
                       "--reuse-message", "--reedit-message", "--template", "--author",
                       "--date", "--cleanup", "--fixup", "--squash", "--gpg-sign",
                       "--untracked-files", "--pathspec-from-file", "--trailer"}
COMMIT_SHORT_WITH_ARG = set("mFCctSu")


def strip_heredocs(text):
    """Drop heredoc bodies, keeping every other line.

    Without this, writing a document that quotes `pkill -f node` through a
    heredoc trips the guard against the very file that documents it.
    """
    out = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        starts = re.findall(r"<<-?\s*([\"']?)([A-Za-z_][A-Za-z0-9_]*)\1", line)
        i += 1
        for _quote, delim in starts:
            while i < len(lines):
                candidate = lines[i].strip() if line.count("<<-") else lines[i].rstrip()
                i += 1
                if candidate == delim:
                    break
    return "\n".join(out)


def _lex(text):
    lexer = shlex.shlex(text, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    tokens = []
    for token in lexer:
        tokens.extend(split_punctuation(token))
    return tokens


PUNCTUATION = sorted((OPERATORS | REDIRECTS) - {"\n"}, key=len, reverse=True)


def split_punctuation(token):
    """shlex glues a run of punctuation into one token: the `);` closing
    `W=$(pwd); git commit` would hide the `;`, and the commit with it. Split such a
    run into the operators it is made of, longest first."""
    if token in OPERATORS or token in REDIRECTS or not re.fullmatch(r"[();<>|&]+", token):
        return [token]
    parts = []
    while token:
        for operator in PUNCTUATION:
            if token.startswith(operator):
                parts.append(operator)
                token = token[len(operator):]
                break
        else:
            return parts + [token]
    return parts


def tokenize(text):
    """Return (tokens, ok). Newlines become explicit command separators."""
    tokens = []
    try:
        for line in text.split("\n"):
            tokens.extend(_lex(line))
            tokens.append(";")
        return tokens, True
    except ValueError:
        pass
    # A quoted construct spanning several lines -- the idiomatic
    # `git commit -m "$(cat <<'EOF' ... EOF)"` -- only parses as a whole.
    try:
        return _lex(text), True
    except ValueError:
        return [], False


def segments(tokens):
    """Split a token stream into commands, dropping operators and redirections.

    Heads are left as written: the caller reads `VAR=value` assignments off them
    before `normalize_head` drops them."""
    result, current, skip_next = [], [], False
    for token in tokens:
        if skip_next:
            skip_next = False
            continue
        if token in OPERATORS:
            if current:
                result.append(current)
            current = []
            continue
        if token in REDIRECTS:
            skip_next = True
            continue
        current.append(token)
    if current:
        result.append(current)
    return [s for s in result if s]


def normalize_head(tokens):
    """Drop shell keywords, `sudo`-style prefixes and leading VAR=value pairs."""
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token in HEAD_NOISE or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", token):
            index += 1
            continue
        break
    return tokens[index:]


def base(token):
    return posixpath.basename(token)


def is_option(token):
    return token.startswith("-") and token != "-"


def operands(tokens):
    """Non-option arguments of a segment, honouring the `--` terminator."""
    result, after_dashdash = [], False
    for token in tokens[1:]:
        if after_dashdash:
            result.append(token)
        elif token == "--":
            after_dashdash = True
        elif not is_option(token):
            result.append(token)
    return result


def repo_root(path):
    """The nearest enclosing directory holding `.git` (a directory, or a worktree's
    file), or PROJECT_DIR when there is none. Filesystem only -- no git process per
    segment."""
    current = posixpath.normpath(path)
    while True:
        if os.path.exists(posixpath.join(current, ".git")):
            return current
        parent = posixpath.dirname(current)
        if parent == current:
            return posixpath.normpath(PROJECT_DIR)
        current = parent


def relpath(token, cwd):
    """Path relative to the repository holding cwd, or None when outside it."""
    absolute = posixpath.normpath(posixpath.join(cwd, token))
    root = repo_root(cwd)
    if absolute == root:
        return "."
    if not absolute.startswith(root + "/"):
        return None
    return absolute[len(root) + 1:]


# --------------------------------------------------------------------------- rules

PROTECTED_BRANCH = "master"

KILLERS = {"pkill", "killall"}


def check_node_kill(tokens):
    """`pkill node` / `killall node` also kill the VS Code server under WSL."""
    if not tokens or base(tokens[0]) not in KILLERS:
        return None
    if "-h" in tokens or "--help" in tokens:
        return None
    targets = [t for t in operands(tokens) if not re.fullmatch(r"[0-9]+|[A-Z]+", t)]
    if not any(re.search(r"(^|[^a-z])node([^a-z]|$)", t) for t in targets):
        return None
    return {
        "rule": "node-kill",
        "message": (
            "Refused: `{cmd}` matches every node process on the machine.\n"
            "Under WSL that includes the VS Code server, and killing it drops the editor's "
            "connection. Kill what you started, by port or by name:\n"
            "    lsof -ti:9999 | xargs kill 2>/dev/null   # the backend port\n"
            "    pkill -f nodemon                         # a specific process"
        ).format(cmd=" ".join(tokens)),
    }


def check_stacked_pr(tokens):
    """A pull request whose base is not `master` merges into that base, not into master."""
    if not tokens or base(tokens[0]) != "gh":
        return None
    words = [t for t in tokens[1:] if not is_option(t)]
    if words[:2] != ["pr", "create"]:
        return None
    target = None
    for index, token in enumerate(tokens):
        if token == "--base" and index + 1 < len(tokens):
            target = tokens[index + 1]
        elif token.startswith("--base="):
            target = token.split("=", 1)[1]
    if target is None or target == PROTECTED_BRANCH:
        return None  # no --base means the repository default, which is master
    return {
        "rule": "stacked-pr",
        "message": (
            "Refused: `gh pr create --base {target}` stacks this pull request on another "
            "branch.\n"
            "A stacked pull request merges into its base, not into master. If the base is "
            "merged first -- and it usually is, since it is reviewed first -- the child "
            "merges into a branch whose content already reached master under different "
            "hashes, and its own work silently never arrives (seen in countscore, "
            "2026-09-09).\n"
            "Do one of these instead: wait for the other branch to merge, then start from "
            "master and target master; or put both changes in one pull request.\n"
            "If stacking really is what you want, say so to the user and let them decide, "
            "then unlock it with `git config zapzap.allowStackedPr true`."
        ).format(target=target),
    }


def check_pr_merge(tokens):
    """`gh pr merge` goes through the required checks, and squashes."""
    if not tokens or base(tokens[0]) != "gh":
        return None
    words = [t for t in tokens[1:] if not is_option(t)]
    if words[:2] != ["pr", "merge"]:
        return None
    if "-h" in tokens or "--help" in tokens:
        return None
    if "--admin" in tokens:
        return {
            "rule": "merge-admin",
            "message": (
                "Refused: `gh pr merge --admin` bypasses the branch protection on master.\n"
                "master requires green checks and an up-to-date branch, and the "
                "protection is not enforced for admins -- so --admin would merge a red or "
                "stale pull request. Wait for the checks (`gh pr checks <n> --watch`), "
                "bring the branch up to date (`gh api -X PUT repos/{owner}/{repo}/pulls/<n>/update-branch`), then merge "
                "without --admin. If a merge really must skip the checks, that is the "
                "user's call: say so and let them run it."
            ),
        }
    short = "".join(t[1:] for t in tokens if t.startswith("-") and not t.startswith("--"))
    squash = "--squash" in tokens or "s" in short
    other = {"--merge", "--rebase"} & set(tokens) or set("mr") & set(short)
    if squash and not other:
        return None
    return {
        "rule": "merge-squash",
        "message": (
            "Refused: `gh pr merge` without --squash (or with --merge / --rebase).\n"
            "master requires a linear history, and one squashed commit per pull request is "
            "what keeps a theme revertable in one step. Without a method flag gh asks "
            "interactively, which a hook-driven session cannot answer.\n"
            "Re-run it as: gh pr merge <n> --squash --delete-branch"
        ),
    }


def parse_push(tokens):
    """Return (push info, finding) for a `git push` segment."""
    if not tokens or base(tokens[0]) != "git":
        return None, None
    subcommand, rest = git_subcommand(tokens)
    if subcommand != "push":
        return None, None
    if "-h" in rest or "--help" in rest or "--dry-run" in rest or "-n" in rest:
        return None, None

    force = None
    for token in rest:
        if token in {"--force", "--force-with-lease", "--force-if-includes", "--mirror"} \
                or token.startswith("--force-with-lease="):
            force = token
        elif token.startswith("-") and not token.startswith("--") and "f" in token[1:]:
            force = token
    positional = [t for t in rest if not is_option(t)]
    remote = positional[0] if positional else None
    refspecs = positional[1:]  # the first operand is the remote
    for spec in refspecs:
        if spec.startswith("+"):
            force = spec
    if force:
        return None, {
            "rule": "force-push",
            "message": (
                "Refused: `git push {flag}` rewrites what the remote holds.\n"
                "Pull requests here are updated by merging master into the branch "
                "(`gh api -X PUT repos/{{owner}}/{{repo}}/pulls/<n>/update-branch`, or `git merge origin/master` then a plain "
                "push), never by a rebase and a force-push: a force-push destroys the "
                "review history, and on a branch another agent also pushes to it "
                "destroys their commits."
            ).format(flag=force),
        }

    if "--all" in rest or "--branches" in rest:
        return None, push_to_main("--all", remote)
    for spec in refspecs:
        destination = spec.split(":", 1)[-1]
        if destination in {PROTECTED_BRANCH, "refs/heads/" + PROTECTED_BRANCH}:
            return None, push_to_main(spec, remote)
    return {"refspecs": refspecs, "remote": remote}, None


def push_to_main(spec, remote):
    return {
        "rule": "push-main",
        "remote": remote,
        "message": (
            "Refused: `git push ... {spec}` would update master directly.\n"
            "master only moves through a squash-merged pull request with green checks. "
            "The branch protection does not stop an admin push, so this hook does. Push "
            "your branch and open a pull request against master."
        ).format(spec=spec),
    }


def git_subcommand(tokens):
    """Return (subcommand, tokens after it) for a `git ...` segment."""
    index = 1
    while index < len(tokens):
        token = tokens[index]
        if token in GIT_GLOBAL_WITH_ARG:
            index += 2
            continue
        if token in GIT_GLOBAL_FLAG or "=" in token and token.startswith("--"):
            index += 1
            continue
        if is_option(token):
            index += 1
            continue
        return token, tokens[index + 1:]
    return None, []


def git_cwd(tokens, cwd, variables):
    """The directory a `git` segment runs in, following every `-C <dir>`.

    Returns (cwd, resolved, absolute): resolved is False once a `-C` operand cannot
    be told from the command line; absolute is True when the last `-C` was an
    absolute path, which settles the directory whatever `cd` did before."""
    resolved, absolute = True, False
    index = 1
    while index < len(tokens) - 1:
        token = tokens[index]
        if token == "-C":
            target = resolve_path(tokens[index + 1], variables)
            if target is None:
                resolved, absolute = False, False
            else:
                cwd = posixpath.normpath(posixpath.join(cwd, target))
                absolute = absolute or target.startswith("/")
            index += 2
            continue
        if token in GIT_GLOBAL_WITH_ARG:
            index += 2
            continue
        if is_option(token):
            index += 1
            continue
        break
    return cwd, resolved, absolute


# What the shell would still expand in a path this parser has to follow.
UNEXPANDED = re.compile(r"[$`*?\[]")
ASSIGNMENT = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)
VARIABLE = re.compile(r"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))")


def resolve_path(token, variables):
    """A `cd` or `git -C` operand as the shell would see it, or None when it cannot
    be told from the command line.

    Only `$VAR` / `${VAR}` bound earlier on the same line to a literal, and a
    leading `~`, are expanded. Anything else -- a variable from the environment,
    `$(...)`, a glob -- is unknown, and the caller refuses rather than guess."""
    def substitute(match):
        value = variables.get(match.group(1) or match.group(2))
        return value if value is not None else match.group(0)
    token = VARIABLE.sub(substitute, token)
    if token == "~" or token.startswith("~/"):
        home = os.environ.get("HOME")
        if not home:
            return None
        token = home + token[1:]
    if UNEXPANDED.search(token) or token.startswith("~"):
        return None
    return token


def record_assignments(tokens, variables):
    """Bind `VAR=value` when a segment is nothing but assignments (optionally after
    `export`). A prefix assignment (`VAR=x cmd`) is not visible to the shell's own
    expansion of that command's arguments, so it is not recorded."""
    words = tokens[1:] if tokens and tokens[0] == "export" else tokens
    if not words or not all(ASSIGNMENT.match(t) for t in words):
        return False
    for token in words:
        name, value = ASSIGNMENT.match(token).groups()
        variables[name] = None if UNEXPANDED.search(value) else value
    return True


def unknown_repo(what):
    return {
        "rule": "unknown-repo",
        "message": (
            "Refused: could not tell which repository this `{what}` runs in.\n"
            "The guard judges a commit or a bare push on the branch of the repository it "
            "runs in, and follows `cd` and `git -C` to find it -- but not through a shell "
            "variable it cannot resolve, a command substitution, or a line it cannot parse. "
            "Rather than judge the wrong checkout, it refuses. This says nothing about your "
            "branch: it is not stale.\n"
            "Re-run it with the path written out: `git -C <literal path> {verb}`."
        ).format(what=what, verb=what.split()[-1]),
    }


def parse_commit(tokens):
    """Return commit info for a `git commit` segment, or None."""
    if not tokens or base(tokens[0]) != "git":
        return None
    subcommand, rest = git_subcommand(tokens)
    if subcommand != "commit":
        return None
    if "--dry-run" in rest or "-h" in rest or "--help" in rest:
        return None

    info = {"all": False, "amend": False, "pathspecs": []}
    index, after_dashdash = 0, False
    while index < len(rest):
        token = rest[index]
        if after_dashdash:
            info["pathspecs"].append(token)
            index += 1
            continue
        if token == "--":
            after_dashdash = True
        elif token in {"--all", "--amend"}:
            info[token[2:]] = True
        elif token.startswith("--"):
            if "=" not in token and token in COMMIT_OPT_WITH_ARG:
                index += 1
        elif token.startswith("-") and token != "-":
            letters = token[1:]
            if "a" in letters:
                info["all"] = True
            if letters and letters[-1] in COMMIT_SHORT_WITH_ARG:
                index += 1
        else:
            info["pathspecs"].append(token)
        index += 1
    return info


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        payload = {}
    command = (payload.get("tool_input") or {}).get("command") or ""
    cwd = payload.get("cwd") or PROJECT_DIR

    tokens, ok = tokenize(strip_heredocs(command))
    verdict = {"parse_ok": ok, "blocks": [], "commit": None, "push": None}
    if not ok:
        # Fail closed on the commit question only: a regex is enough to decide
        # whether the gates should run, and running them spuriously is cheap.
        commits = re.search(r"\bgit\b[^\n]*\bcommit\b", command) and "--dry-run" not in command
        pushes = re.search(r"\bgit\b[^\n]*\bpush\b", command)
        # A `cd` or `git -C` the parser could not follow means the payload cwd is
        # probably not where the commit runs: judging it would judge the wrong branch.
        moves = re.search(r"(^|[\s;&|(])cd(\s|$)", command) \
            or re.search(r"\bgit\s[^\n]*\s-C\s", command)
        if moves and (commits or pushes):
            verdict["blocks"].append(unknown_repo("git commit" if commits else "git push"))
        elif commits:
            verdict["commit"] = {"all": True, "amend": True, "pathspecs": [],
                                 "cwd": posixpath.normpath(cwd)}
        print(json.dumps(verdict))
        return

    notional_cwd = posixpath.normpath(cwd)
    cwd_known = True
    variables = {}
    for raw_segment in segments(tokens):
        if record_assignments(raw_segment, variables):
            continue
        tokens_of_segment = normalize_head(raw_segment)
        if not tokens_of_segment:
            continue
        if base(tokens_of_segment[0]) == "cd":
            args = operands(tokens_of_segment)
            if args and args[0] != "-":
                target = resolve_path(args[0], variables)
                if target is None:
                    cwd_known = False
                elif target.startswith("/"):
                    notional_cwd, cwd_known = posixpath.normpath(target), True
                else:
                    notional_cwd = posixpath.normpath(posixpath.join(notional_cwd, target))
            else:
                notional_cwd, cwd_known = posixpath.normpath(cwd), True
            continue
        for finding in (
            check_node_kill(tokens_of_segment),
            check_stacked_pr(tokens_of_segment),
            check_pr_merge(tokens_of_segment),
        ):
            if finding:
                verdict["blocks"].append(finding)
        segment_cwd, segment_known = notional_cwd, cwd_known
        if base(tokens_of_segment[0]) == "git":
            segment_cwd, resolved, absolute = git_cwd(tokens_of_segment, notional_cwd, variables)
            segment_known = resolved and (cwd_known or absolute)
        push, finding = parse_push(tokens_of_segment)
        if finding:
            if finding["rule"] == "push-main":
                finding["cwd"], finding["known"] = segment_cwd, segment_known
                if finding["remote"] is not None:
                    finding["remote"] = resolve_path(finding["remote"], variables)
            verdict["blocks"].append(finding)
        if push:
            push["cwd"], push["known"] = segment_cwd, segment_known
            verdict["push"] = push
            # Only a bare push depends on the branch the repository is on.
            if not segment_known and not push["refspecs"]:
                verdict["blocks"].append(unknown_repo("git push"))
        commit = parse_commit(tokens_of_segment)
        if commit:
            commit["cwd"] = segment_cwd
            verdict["commit"] = commit
            if not segment_known:
                verdict["blocks"].append(unknown_repo("git commit"))
    print(json.dumps(verdict))

if __name__ == "__main__":
    main()
