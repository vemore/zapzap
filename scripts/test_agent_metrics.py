"""Tests for scripts/agent_metrics.py, on a synthetic projects directory under tmp_path.

Run: uv run --no-project --with pytest pytest -v scripts/test_agent_metrics.py
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("agent_metrics", Path(__file__).with_name("agent_metrics.py"))
assert _spec is not None and _spec.loader is not None
am = importlib.util.module_from_spec(_spec)
sys.modules["agent_metrics"] = am  # dataclasses look their module up
_spec.loader.exec_module(am)

SECRET = "the quick brown secret prompt"


def ts(minute: float) -> str:
    whole = int(minute)
    seconds = round((minute - whole) * 60)
    return f"2026-09-20T10:{whole:02d}:{seconds:02d}.000Z"


def usage(inp=0, write=0, read=0, out=0, one_hour=False):
    split = {"ephemeral_1h_input_tokens": write, "ephemeral_5m_input_tokens": 0} if one_hour else \
        {"ephemeral_1h_input_tokens": 0, "ephemeral_5m_input_tokens": write}
    return {"input_tokens": inp, "cache_creation_input_tokens": write, "cache_read_input_tokens": read,
            "output_tokens": out, "cache_creation": split}


def assistant(uid, minute, mid, u, blocks=(), branch="main"):
    return {"type": "assistant", "uuid": uid, "timestamp": ts(minute), "gitBranch": branch,
            "message": {"id": mid, "usage": u, "content": list(blocks)}}


def prompt(uid, minute, text=SECRET):
    return {"type": "user", "uuid": uid, "timestamp": ts(minute), "gitBranch": "main",
            "message": {"role": "user", "content": text}}


def result(uid, minute, tool_id, text, branch="main"):
    return {"type": "user", "uuid": uid, "timestamp": ts(minute), "gitBranch": branch,
            "toolUseResult": {}, "message": {"content": [
                {"type": "tool_result", "tool_use_id": tool_id, "content": text}]}}


def tool_use(tid, name, **inp):
    return {"type": "tool_use", "id": tid, "name": name, "input": inp}


def write_jsonl(path: Path, records) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r) + "\n" for r in records) + '{"truncated": ', encoding="utf-8")


@pytest.fixture
def projects(tmp_path: Path) -> Path:
    d = tmp_path / "-home-u-zapzap"
    main = [
        prompt("p1", 0),
        assistant("a1", 1, "m1", usage(inp=10, write=1000, read=0, out=50),
                  [tool_use("t1", "Skill", skill="ship-parallel")]),
        result("r1", 1.5, "t1", "skill body"),
        # The same message streamed as two records: counted once.
        assistant("a2", 2, "m2", usage(inp=5, write=200, read=1000, out=20),
                  [tool_use("t2", "Read", file_path="/home/u/zapzap/.claude/worktrees/agent-x/lib/a.dart")]),
        assistant("a2b", 2, "m2", usage(inp=5, write=200, read=1000, out=20),
                  [tool_use("t3", "Bash", command="cd /x && git -C /y commit -m 'msg'")]),
        result("r2", 2.5, "t2", "x" * 300),
        result("r3", 4.5, "t3", "y" * 100),
        assistant("a3", 5, "m3", usage(inp=0, write=400, read=2000, out=10),
                  [tool_use("t4", "Agent", subagent_type="Explore"),
                   tool_use("t5", "AskUserQuestion")]),
        result("r4", 5.5, "t4", "spawned"),
        result("r5", 30, "t5", "user answer"),       # 24.5 min waiting on the user
        assistant("a4", 31, "m4", usage(out=5)),
        prompt("p2", 50),                            # 19 min waiting on the user
        assistant("a5", 51, "m5", usage(out=7)),
        {"type": "attachment", "uuid": "h1", "timestamp": ts(51), "gitBranch": "main",
         "attachment": {"type": "hook_success", "hookEvent": "SessionStart",
                        "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/session-start.sh",
                        "durationMs": 1500, "content": "c" * 40}},
    ]
    write_jsonl(d / "sess1234-aaaa.jsonl", main)
    sub = d / "sess1234-aaaa" / "subagents" / "agent-1.jsonl"
    write_jsonl(sub, [
        {"type": "user", "uuid": "s0", "timestamp": ts(6), "gitBranch": "feat/x",
         "message": {"content": "task prompt from the parent"}},
        assistant("s1", 7, "sm1", usage(inp=1, write=100, read=100, out=100), branch="feat/x"),
        assistant("s2", 8, "m1", usage(inp=10, write=1000, out=50), branch="feat/x"),  # repeat of m1
    ])
    (sub.with_suffix(".meta.json")).write_text(json.dumps({"agentType": "Explore", "toolUseId": "t4", "spawnDepth": 1}))
    return d


def run(projects: Path, capsys, *args) -> str:
    assert am.main(["--projects-dir", str(projects), "--no-gh", *args]) == 0
    return capsys.readouterr().out


def collect(projects: Path, **kw) -> am.Metrics:
    m = am.Metrics(root=Path("/home/u/zapzap"), since=kw.get("since"), until=None,
                   idle_cap=kw.get("idle_cap", 900))
    am.scan(m, [projects])
    return m


def test_tokens_counted_once_per_message_and_weighted(projects):
    m = collect(projects)
    agent = m.axes["agent"]
    # m1 1060, m2 1225, m3 2410, m4 5, m5 7; the subagent: sm1 301 (m1 again is skipped).
    assert agent["main"].raw == 1060 + 1225 + 2410 + 5 + 7
    assert agent["Explore"].raw == 301
    assert agent["Explore"].count == 1
    # m1: 10 input + 1000 5-min writes x1.25 + 50 output x5
    assert am.weighted(usage(inp=10, write=1000, out=50)) == (1060, 10 + 1250 + 250, 1010)
    assert am.weighted(usage(write=100, one_hour=True))[1] == 200
    assert am.weighted(usage(read=1000))[1] == pytest.approx(100)


def test_skill_follows_until_the_next_prompt_and_into_subagents(projects):
    m = collect(projects)
    skills = m.axes["skill"]
    assert skills["ship-parallel"].raw == 1225 + 2410 + 5 + 301  # m2..m4 and the subagent
    assert skills["(none)"].raw == 1060 + 7                        # m1 invoked it; m5 is after a prompt


def test_tool_and_file_get_the_fresh_input_that_read_their_results(projects):
    m = collect(projects)
    tools, files = m.axes["tool"], m.axes["file"]
    # m3's fresh input (400) splits 3:1 between the Read (300 chars) and the Bash (100).
    assert tools["Read"].raw == pytest.approx(300)
    assert files["lib/a.dart"].raw == pytest.approx(300)
    assert tools["Bash git commit"].raw == pytest.approx(100)
    assert tools["Bash git commit"].seconds == pytest.approx(150)   # 2:00 -> 4:30
    assert tools["Skill ship-parallel"].count == 1


def test_waits_on_the_user_are_left_out(projects):
    m = collect(projects)
    assert m.axes["tool"]["AskUserQuestion"].seconds == 0
    assert m.user_wait == pytest.approx(24.5 * 60 + 19 * 60)
    # Main transcript: 0->5.5 min active, 30->31 active, 50->51 active.
    assert m.axes["agent"]["main"].seconds == pytest.approx(5.5 * 60 + 60 + 60)


def test_idle_cap_bounds_a_gap(projects):
    m = collect(projects, idle_cap=30)
    assert m.axes["tool"]["Bash git commit"].seconds == 30


def test_hooks(projects):
    m = collect(projects)
    hook = m.axes["hook"]["SessionStart session-start.sh"]
    assert (hook.seconds, hook.count, hook.raw) == (1.5, 1, 10)


def test_branch_carries_the_record_branch(projects):
    m = collect(projects)
    assert m.axes["branch"]["feat/x"].raw == 301
    assert set(m.axes["session"]) == {"sess1234"}


def test_since_skips_older_records(projects):
    m = collect(projects, since=am.day_ts("2026-09-21"))
    assert m.axes["agent"] == {}


def test_report_prints_every_axis_and_no_content(projects, capsys):
    out = run(projects, capsys, "--since", "2026-09-01")
    for axis in am.AXES:
        assert f"== by {axis} — top 10 by weighted tokens ==" in out
        assert f"== by {axis} — top 10 by active time ==" in out
    for text in (SECRET, "task prompt", "user answer", "skill body", "msg", "xxxx"):
        assert text not in out


def test_unknown_axis_is_refused(projects):
    with pytest.raises(SystemExit):
        am.main(["--projects-dir", str(projects), "--by", "colour"])


@pytest.mark.parametrize("command,key", [
    ("git status", "Bash git status"),
    ("cd /a && git -C /b push -u origin x", "Bash git push"),
    ("export A=1 && gh pr checks 12 --watch", "Bash gh pr checks"),
    ("gh api -X PUT repos/o/r/pulls/1/update-branch", "Bash gh api"),
    ("timeout 600 flutter test", "Bash flutter test"),
    ("cd zapzap-rust && cargo clippy --all-targets -- -D warnings", "Bash cargo clippy"),
    ("FOO=1 scripts/wip.sh list", "Bash wip.sh"),
    ("for f in a b; do echo $f; done", "Bash (loop)"),
    ("python3 - <<'EOF'\nprint(1)\nEOF", "Bash python3"),
])
def test_bash_key_names_the_program_never_the_arguments(command, key):
    assert am.bash_key(command) == key


def test_file_keys_strip_worktrees_and_hide_conversation_named_files():
    m = am.Metrics(root=Path("/home/u/zapzap"), since=None, until=None, idle_cap=900)
    assert m.file_key("/home/u/zapzap/lib/x.dart") == "lib/x.dart"
    assert m.file_key("/home/u/zapzap-topic/lib/x.dart") == "lib/x.dart"
    assert m.file_key("/home/u/zapzap/.claude/worktrees/agent-1/wip/a.md") == "wip/a.md"
    assert m.file_key("/tmp/claude-1000/scratch/notes-about-my-prompt.txt") == "(temporary file)"


def test_encode_project_matches_claude_code():
    assert am.encode_project("/home/vemore/workspace/zapzap") == "-home-vemore-workspace-zapzap"


def test_default_projects_dirs_take_the_repository_and_its_worktrees(tmp_path, monkeypatch):
    projects = tmp_path / "projects"
    for name in ("-home-u-zapzap", "-home-u-zapzap--claude-worktrees-agent-1",
                 "-home-u-zapzap-topic", "-home-u-countscore", "-home-u-zapzapper"):
        (projects / name).mkdir(parents=True)
    monkeypatch.setenv("CLAUDE_CONFIG_DIR", str(tmp_path))
    names = [d.name for d in am.default_projects_dirs(Path("/home/u/zapzap"))]
    assert names == ["-home-u-zapzap", "-home-u-zapzap--claude-worktrees-agent-1", "-home-u-zapzap-topic"]
