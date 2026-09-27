#!/usr/bin/env python3
"""ZapZap - tokens and active time per workflow, from the local Claude Code transcripts.

Reads ~/.claude/projects/<encoded repository path>/ (-home-vemore-workspace-zapzap, and the
directories of worktrees opened as projects, which start with that name: the sessions, and
their subagents/), prints aggregates, and writes nothing: transcript content never leaves
the terminal, and only names reach it -- a session id, a branch, a skill, an agent type, a
tool, a file path, a hook. Stdlib only. Read next to scripts/delivery_metrics.sh when a
process change is judged; the baseline lives in .llmwiki/ParallelDelivery.md
§ Measuring delivery.

Usage: scripts/agent_metrics.py [--since YYYY-MM-DD] [--until YYYY-MM-DD]
                                [--by session,branch,skill,agent,tool,file,hook] [--top 10]
                                [--projects-dir DIR ...] [--idle-cap SECONDS] [--no-gh]

Tokens, per assistant message (counted once, whichever file repeats it):
  raw       input + cache write + cache read + output
  weighted  in uncached-input equivalents, by price class: cache read 0.1, cache write
            1.25 (5 min) or 2 (1 h), uncached input 1, output 5
  session, branch, skill, agent: the message's own usage. The skill is the last one
  invoked (Skill tool or /command) since the last human prompt; a subagent inherits the
  skill active when it was spawned.
  tool, file: the fresh input (uncached + cache write) of the call that read a tool result,
  split between the results it read by their size. A cache that expired during a long
  tool call is charged to that tool, which is the point.
  hook: an estimate, the characters it injected / 4.

Active time: the gaps between consecutive records of a transcript, each capped at
--idle-cap (default 900 s); a gap that ends on a human prompt, or on the answer to
AskUserQuestion or ExitPlanMode, is a wait on the user and left out (the total says how
much). A permission prompt inside a tool call cannot be told apart: the cap bounds it.
Tools: tool_use -> tool_result, same cap. Hooks: their durationMs. A hook that
passes silently (guard-bash.sh's PreToolUse gates) leaves no record: its time is inside
the Bash call it guarded -- `Bash git commit` carries the commit gates.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

AXES = ("session", "branch", "skill", "agent", "tool", "file", "hook")

# Relative to uncached input (Anthropic's price classes).
W_INPUT, W_CACHE_READ, W_WRITE_5M, W_WRITE_1H, W_OUTPUT = 1.0, 0.1, 1.25, 2.0, 5.0

# Slash commands that are the CLI's own, not skills.
BUILTIN_COMMANDS = {
    "add-dir", "agents", "bug", "chrome", "clear", "compact", "config", "context", "cost",
    "doctor", "exit", "export", "help", "hooks", "ide", "init", "login", "logout", "mcp",
    "memory", "model", "permissions", "plugin", "reload-plugins", "resume", "rewind",
    "status", "statusline", "terminal-setup", "theme", "usage", "vim", "claim-credit",
    "fast", "effort", "remote-control", "tasks", "todos", "upgrade",
}

# Programs whose subcommand is what tells two Bash calls apart.
SUBCOMMAND_PROGRAMS = {"git": 1, "gh": 2, "flutter": 1, "dart": 1, "uv": 1, "docker": 1,
                       "npm": 1, "npx": 1, "adb": 1, "cargo": 1}
# Wrappers, and how many arguments they take before the program they run.
WRAPPERS = {"timeout": 1, "time": 0, "nice": 0, "env": 0}
LOOPS = {"for", "while", "until", "if"}

# Tools whose result is the user's answer: the time until it arrives is a wait on the user.
WAITS_ON_USER = {"AskUserQuestion", "ExitPlanMode"}


def parse_ts(value: str | None) -> float | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def day_ts(day: str) -> float:
    return datetime.strptime(day, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp()


def encode_project(path: str) -> str:
    """Claude Code's directory name for a project: every non-alphanumeric becomes '-'."""
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def repo_root() -> Path:
    """The main checkout, also from a worktree (the transcripts are keyed by where the
    session started, and sessions start in the main checkout)."""
    here = Path(__file__).resolve().parent
    try:
        common = subprocess.run(
            ["git", "-C", str(here), "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        return Path(common).parent
    except (OSError, subprocess.CalledProcessError):
        return here.parent


def default_projects_dirs(root: Path) -> list[Path]:
    config = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
    projects = config / "projects"
    prefix = encode_project(str(root))
    if not projects.is_dir():
        return []
    # The repository itself, and anything started below it (a worktree opened as a project).
    return sorted(p for p in projects.iterdir()
                  if p.is_dir() and (p.name == prefix or p.name.startswith(prefix + "-")))


def weighted(usage: dict) -> tuple[int, float, int]:
    """(raw tokens, weighted tokens, fresh input tokens) of one message's usage."""
    inp = usage.get("input_tokens") or 0
    read = usage.get("cache_read_input_tokens") or 0
    write = usage.get("cache_creation_input_tokens") or 0
    out = usage.get("output_tokens") or 0
    split = usage.get("cache_creation") or {}
    w1h = split.get("ephemeral_1h_input_tokens") or 0
    w5m = split.get("ephemeral_5m_input_tokens") or 0
    if w1h + w5m != write:  # no breakdown: price it as a 5-minute write
        w5m, w1h = write, 0
    wt = inp * W_INPUT + read * W_CACHE_READ + w5m * W_WRITE_5M + w1h * W_WRITE_1H + out * W_OUTPUT
    return inp + read + write + out, wt, inp + write


def fresh_weighted(usage: dict) -> float:
    inp = usage.get("input_tokens") or 0
    write = usage.get("cache_creation_input_tokens") or 0
    split = usage.get("cache_creation") or {}
    w1h = split.get("ephemeral_1h_input_tokens") or 0
    w5m = split.get("ephemeral_5m_input_tokens") or 0
    if w1h + w5m != write:
        w5m, w1h = write, 0
    return inp * W_INPUT + w5m * W_WRITE_5M + w1h * W_WRITE_1H


def bash_key(command: str) -> str:
    """`Bash <program> [<subcommand>]` -- never the arguments."""
    command = command.strip()
    while True:  # drop leading `cd X &&` and `export X=1 &&` hops
        m = re.match(r"(cd|export|source)\s+[^&;|]*(&&|;)\s*", command)
        if not m:
            break
        command = command[m.end():]
    try:
        words = shlex.split(command.splitlines()[0] if command else "", posix=True)
    except ValueError:
        words = command.split()
    words = [w for w in words if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w)]
    while words and os.path.basename(words[0]) in WRAPPERS:
        skip = WRAPPERS[os.path.basename(words[0])]
        words = [w for w in words[1:] if not w.startswith("-")][skip:]
    prog = os.path.basename(words[0]) if words else "?"
    if prog in LOOPS:
        return "Bash (loop)"
    key = f"Bash {prog or '?'}"
    wanted = SUBCOMMAND_PROGRAMS.get(prog, 0)
    rest = iter(words[1:])
    for w in rest:
        if not wanted:
            break
        if w in ("-C", "-c", "--repo", "-R", "--directory", "-X", "--method"):
            next(rest, None)
            continue
        if w.startswith("-") or "/" in w or "=" in w:
            continue
        key += f" {w}"
        wanted -= 1
    return key[:48]


def tool_key(name: str, tool_input: dict) -> str:
    if name == "Bash":
        return bash_key(str(tool_input.get("command", "")))
    if name == "Skill":
        return f"Skill {tool_input.get('skill', '?')}"
    if name == "Agent":
        return f"Agent {tool_input.get('subagent_type') or 'general-purpose'}"
    return name


def hook_key(event: str | None, command: str | None) -> str:
    cmd = (command or "").strip()
    if cmd and "/" not in cmd.split()[0] and " " in cmd:
        return f'{event or "?"} "{cmd}"'[:48]  # a statusMessage: the settings.json text
    base = os.path.basename(cmd.split()[0]) if cmd else "?"
    return f"{event or '?'} {base}"[:48]


@dataclass
class Totals:
    raw: float = 0.0
    weighted: float = 0.0
    seconds: float = 0.0
    count: int = 0


@dataclass
class Metrics:
    root: Path
    since: float | None
    until: float | None
    idle_cap: float
    axes: dict = field(default_factory=lambda: {a: defaultdict(Totals) for a in AXES})
    seen_messages: set = field(default_factory=set)
    seen_uuids: set = field(default_factory=set)
    spawn_skill: dict = field(default_factory=dict)  # Agent tool_use id -> skill active then
    known_skills: set = field(default_factory=set)
    sessions: set = field(default_factory=set)
    files: int = 0
    bytes: int = 0
    bad_lines: int = 0
    user_wait: float = 0.0  # gaps left out because they ended on the user
    # price class -> [tokens, weighted tokens], over every model call in the window
    classes: dict = field(default_factory=lambda: {
        c: [0, 0.0] for c in ("cache read", "cache write", "uncached input", "output")})

    def add_classes(self, usage: dict) -> None:
        inp = usage.get("input_tokens") or 0
        read = usage.get("cache_read_input_tokens") or 0
        write = usage.get("cache_creation_input_tokens") or 0
        out = usage.get("output_tokens") or 0
        for name, tokens, wt in (("cache read", read, read * W_CACHE_READ),
                                 ("cache write", write, fresh_weighted(usage) - inp * W_INPUT),
                                 ("uncached input", inp, inp * W_INPUT),
                                 ("output", out, out * W_OUTPUT)):
            self.classes[name][0] += tokens
            self.classes[name][1] += wt

    def in_window(self, ts: float | None) -> bool:
        if ts is None:
            return False
        return (self.since is None or ts >= self.since) and (self.until is None or ts < self.until)

    def add(self, axis: str, key: str, raw=0.0, wt=0.0, seconds=0.0, count=0) -> None:
        t = self.axes[axis][key]
        t.raw += raw
        t.weighted += wt
        t.seconds += seconds
        t.count += count

    def file_key(self, path: str) -> str:
        path = path.replace("\\", "/")
        m = re.search(r"/\.claude/worktrees/[^/]+/(.*)$", path)
        if m:
            return m.group(1)
        root = str(self.root).rstrip("/") + "/"
        if path.startswith(root):
            return path[len(root):]
        # A sibling worktree, ../zapzap-<topic>/...
        m = re.match(re.escape(str(self.root.parent)) + r"/" + re.escape(self.root.name) + r"-[^/]+/(.*)$", path)
        if m:
            return m.group(1)
        # Scratch files and plans are named after the conversation: the name is content.
        if path.startswith(("/tmp/", "/var/tmp/")):
            return "(temporary file)"
        home = str(Path.home())
        if path.startswith(home + "/.claude/"):
            return "~/.claude/" + path[len(home) + 9:].split("/")[0] + "/…"
        return "~" + path[len(home):] if path.startswith(home) else path


def is_human_prompt(rec: dict) -> bool:
    if rec.get("type") != "user" or rec.get("isMeta") or "toolUseResult" in rec:
        return False
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, str):
        return not content.lstrip().startswith(("<task-notification>", "<local-command-stdout>"))
    if isinstance(content, list):
        kinds = {b.get("type") for b in content if isinstance(b, dict)}
        return "tool_result" not in kinds and bool(kinds & {"text", "image"})
    return False


def slash_command(rec: dict) -> str | None:
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, str):
        m = re.search(r"<command-name>/?([^<\s]+)</command-name>", content)
        if m:
            return m.group(1)
    return None


def result_size(block: dict) -> int:
    content = block.get("content")
    if isinstance(content, str):
        return len(content)
    if isinstance(content, list):
        n = 0
        for part in content:
            if isinstance(part, dict):
                n += len(part.get("text") or "") or len(json.dumps(part.get("source", ""))) // 4
        return n
    return 0


def process_file(m: Metrics, path: Path, session: str, agent: str, skill: str | None) -> None:
    m.files += 1
    last_ts: float | None = None
    last_branch = "(none)"
    open_tools: dict[str, tuple[str, float | None, str | None]] = {}  # id -> tool key, ts, file key
    pending: list[tuple[str, str | None, int]] = []  # results read since the last call
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m.bytes += len(line)
            try:
                rec = json.loads(line)
            except ValueError:
                m.bad_lines += 1  # a transcript still being written ends mid-line
                continue
            if not isinstance(rec, dict):
                continue
            kind = rec.get("type")
            ts = parse_ts(rec.get("timestamp"))
            uuid = rec.get("uuid")
            duplicate = uuid is not None and uuid in m.seen_uuids
            if uuid is not None:
                m.seen_uuids.add(uuid)

            message = rec.get("message") if isinstance(rec.get("message"), dict) else {}
            content = message.get("content")
            prompt = agent == "main" and is_human_prompt(rec)
            answer = kind == "user" and isinstance(content, list) and any(
                isinstance(b, dict) and b.get("type") == "tool_result"
                and open_tools.get(b.get("tool_use_id"), ("",))[0] in WAITS_ON_USER
                for b in content)
            if prompt:
                cmd = slash_command(rec)
                skill = None
                if cmd and cmd not in BUILTIN_COMMANDS:
                    skill = cmd
            # Records without a branch (queue operations, some system records) keep the last.
            branch = last_branch = rec.get("gitBranch") or last_branch
            keys = {"session": session, "branch": branch, "skill": skill or "(none)", "agent": agent}

            # Active time: the gap this record closes, unless it closes a wait on the user.
            if ts is not None and not duplicate:
                if last_ts is not None and m.in_window(ts):
                    if prompt or answer:
                        m.user_wait += max(ts - last_ts, 0.0)
                    else:
                        gap = min(max(ts - last_ts, 0.0), m.idle_cap)
                        for axis, key in keys.items():
                            m.add(axis, key, seconds=gap)
                last_ts = ts
            if duplicate or not m.in_window(ts):
                if kind == "assistant":  # keep the tool map right for results in the window
                    for block in (rec.get("message") or {}).get("content") or []:
                        if isinstance(block, dict) and block.get("type") == "tool_use":
                            open_tools.setdefault(block.get("id"), ("?", None, None))
                continue
            if prompt:
                m.sessions.add(session)

            if kind == "assistant":
                mid = message.get("id") or uuid
                usage = message.get("usage") or {}
                if mid not in m.seen_messages and usage:
                    m.seen_messages.add(mid)
                    raw, wt, fresh = weighted(usage)
                    m.add_classes(usage)
                    for axis, key in keys.items():
                        m.add(axis, key, raw=raw, wt=wt, count=1)
                    total = sum(size for _, _, size in pending) or 0
                    if pending and fresh:
                        fw = fresh_weighted(usage)
                        for tkey, fkey, size in pending:
                            share = size / total if total else 1 / len(pending)
                            m.add("tool", tkey, raw=fresh * share, wt=fw * share)
                            if fkey:
                                m.add("file", fkey, raw=fresh * share, wt=fw * share)
                    pending = []
                for block in message.get("content") or []:
                    if not isinstance(block, dict) or block.get("type") != "tool_use":
                        continue
                    name = block.get("name") or "?"
                    tinput = block.get("input") if isinstance(block.get("input"), dict) else {}
                    tkey = tool_key(name, tinput)
                    fkey = None
                    if name == "Read" and tinput.get("file_path"):
                        fkey = m.file_key(str(tinput["file_path"]))
                    if name == "Skill" and tinput.get("skill"):
                        skill = str(tinput["skill"])
                        m.known_skills.add(skill)
                    if name == "Agent":
                        m.spawn_skill[block.get("id")] = skill
                    open_tools[block.get("id")] = (tkey, ts, fkey)
                    m.add("tool", tkey, count=1)
                    if fkey:
                        m.add("file", fkey, count=1)
            elif kind == "user":
                for block in content if isinstance(content, list) else []:
                    if not isinstance(block, dict) or block.get("type") != "tool_result":
                        continue
                    tkey, started, fkey = open_tools.pop(block.get("tool_use_id"), ("?", None, None))
                    size = result_size(block)
                    pending.append((tkey, fkey, size))
                    if started is not None and ts is not None and tkey not in WAITS_ON_USER:
                        took = min(max(ts - started, 0.0), m.idle_cap)
                        m.add("tool", tkey, seconds=took)
                        if fkey:
                            m.add("file", fkey, seconds=took)
            elif kind == "attachment":
                att = rec.get("attachment") or {}
                if str(att.get("type", "")).startswith("hook") and att.get("durationMs") is not None:
                    injected = len(str(att.get("content") or ""))
                    m.add("hook", hook_key(att.get("hookEvent"), att.get("command")),
                          raw=injected / 4, wt=injected / 4,
                          seconds=(att.get("durationMs") or 0) / 1000, count=1)
            elif kind == "system" and rec.get("subtype") == "stop_hook_summary":
                for info in rec.get("hookInfos") or []:
                    if isinstance(info, dict) and info.get("durationMs") is not None:
                        m.add("hook", hook_key("Stop", info.get("command")),
                              seconds=info["durationMs"] / 1000, count=1)


def load_meta(path: Path) -> dict:
    meta = path.with_suffix(".meta.json")
    try:
        return json.loads(meta.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def scan(m: Metrics, dirs: list[Path]) -> None:
    mains: list[Path] = []
    subs: list[tuple[int, float, Path, dict]] = []
    for d in dirs:
        mains.extend(d.glob("*.jsonl"))
        for p in d.glob("*/subagents/*.jsonl"):
            meta = load_meta(p)
            subs.append((int(meta.get("spawnDepth") or 1), p.stat().st_mtime, p, meta))
    since = m.since
    for p in sorted(mains, key=lambda p: p.stat().st_mtime):
        if since is not None and p.stat().st_mtime < since:
            continue  # not written to since the window opened
        process_file(m, p, p.stem[:8], "main", None)
    for _, mtime, p, meta in sorted(subs, key=lambda s: (s[0], s[1])):
        if since is not None and mtime < since:
            continue
        session = p.parent.parent.name[:8]
        agent = meta.get("agentType") or "subagent"
        process_file(m, p, session, agent, m.spawn_skill.get(meta.get("toolUseId")))


def branch_prs() -> dict[str, str]:
    try:
        out = subprocess.run(
            ["gh", "pr", "list", "--state", "all", "--limit", "1000", "--json", "number,headRefName",
             "-q", ".[] | [.headRefName, (.number|tostring)] | @tsv"],
            capture_output=True, text=True, timeout=60, check=True,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    prs: dict[str, str] = {}
    for line in out.splitlines():
        branch, _, number = line.partition("\t")
        prs.setdefault(branch, f"#{number}")  # newest first: the latest pull request
    return prs


def human(n: float) -> str:
    for unit, div in (("G", 1e9), ("M", 1e6), ("k", 1e3)):
        if abs(n) >= div:
            return f"{n / div:.1f}{unit}"
    return f"{n:.0f}"


def hours(seconds: float) -> str:
    if seconds >= 3600:
        return f"{seconds / 3600:.1f} h"
    if seconds >= 60:
        return f"{seconds / 60:.0f} min"
    return f"{seconds:.0f} s"


def session_labels(m: Metrics, dirs: list[Path]) -> dict[str, str]:
    """A session id's first date, so a row says when it ran without saying what it did."""
    labels = {}
    for d in dirs:
        for p in d.glob("*.jsonl"):
            with p.open("r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    ts = re.search(r'"timestamp":"(\d{4}-\d{2}-\d{2})', line)
                    if ts:
                        labels[p.stem[:8]] = f"{p.stem[:8]} {ts.group(1)}"
                        break
    return labels


def report(m: Metrics, axes: list[str], top: int, labels: dict[str, str], prs: dict[str, str]) -> str:
    out = []
    agent_rows = m.axes["agent"].values()
    raw = sum(t.raw for t in agent_rows)
    wt = sum(t.weighted for t in agent_rows)
    secs = sum(t.seconds for t in agent_rows)
    out.append(f"Agent metrics — {m.files} transcripts, {m.bytes / 1e6:.0f} MB read, "
               f"{len(m.seen_messages)} model calls, {len(m.sessions)} sessions with a prompt in the window")
    out.append(f"  total: {human(raw)} tokens raw, {human(wt)} weighted, {hours(secs)} active "
               f"(agent time: parallel subagents add up); {hours(m.user_wait)} waiting on the user left out")
    by_class = m.classes
    total_class = sum(w for _, w in by_class.values()) or 1
    out.append("  weighted by price class: " + ", ".join(
        f"{name} {100 * w / total_class:.0f}% ({human(t)} tokens)" for name, (t, w) in by_class.items()))
    for axis in axes:
        rows = m.axes[axis]
        if not rows:
            out.append(f"\n== by {axis}: nothing in the window ==")
            continue

        def name(key: str, axis: str = axis) -> str:
            if axis == "session":
                return labels.get(key, key)
            if axis == "branch" and key in prs:
                return f"{key} ({prs[key]})"
            return key

        what = "calls" if axis in ("session", "branch", "skill", "agent") else "uses"
        out.append(f"\n== by {axis} — top {top} by weighted tokens ==")
        out.append(f"  {'':44} {'raw':>9} {'weighted':>9} {'share':>6} {what:>7}")
        total_wt = sum(t.weighted for t in rows.values()) or 1
        for key, t in sorted(rows.items(), key=lambda kv: -kv[1].weighted)[:top]:
            out.append(f"  {name(key)[:44]:44} {human(t.raw):>9} {human(t.weighted):>9} "
                       f"{100 * t.weighted / total_wt:5.1f}% {t.count:>7}")
        out.append(f"== by {axis} — top {top} by active time ==")
        total_s = sum(t.seconds for t in rows.values()) or 1
        for key, t in sorted(rows.items(), key=lambda kv: -kv[1].seconds)[:top]:
            out.append(f"  {name(key)[:44]:44} {hours(t.seconds):>9} {100 * t.seconds / total_s:5.1f}% {t.count:>7}")
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--since", help="YYYY-MM-DD, inclusive (UTC)")
    ap.add_argument("--until", help="YYYY-MM-DD, exclusive (UTC)")
    ap.add_argument("--by", default=",".join(AXES),
                    help=f"comma-separated axes among {', '.join(AXES)} (default: all)")
    ap.add_argument("--top", type=int, default=10)
    ap.add_argument("--projects-dir", action="append", type=Path,
                    help="a Claude Code project directory to read (repeatable); default: "
                         "~/.claude/projects/<this repository's encoded path>")
    ap.add_argument("--idle-cap", type=float, default=900, help="seconds; a longer gap counts as this")
    ap.add_argument("--no-gh", action="store_true", help="do not ask gh for each branch's pull request")
    args = ap.parse_args(argv)

    axes = [a.strip() for a in args.by.split(",") if a.strip()]
    unknown = [a for a in axes if a not in AXES]
    if unknown:
        ap.error(f"unknown axis {', '.join(unknown)}; choose among {', '.join(AXES)}")
    try:
        since = day_ts(args.since) if args.since else None
        until = day_ts(args.until) if args.until else None
    except ValueError:
        ap.error("--since and --until take YYYY-MM-DD")

    root = repo_root()
    dirs = args.projects_dir or default_projects_dirs(root)
    dirs = [d for d in dirs if d.is_dir()]
    if not dirs:
        print(f"no transcripts found for {root} (use --projects-dir)", file=sys.stderr)
        return 2

    m = Metrics(root=root, since=since, until=until, idle_cap=args.idle_cap)
    scan(m, dirs)
    labels = session_labels(m, dirs) if "session" in axes else {}
    prs = branch_prs() if "branch" in axes and not args.no_gh else {}
    print(report(m, axes, args.top, labels, prs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
