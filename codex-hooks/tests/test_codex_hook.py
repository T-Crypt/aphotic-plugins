import json
import os
from pathlib import Path
import subprocess
import sys
import time

import pytest


HOOK = Path(__file__).resolve().parents[1] / "hook" / "codex_hook.py"


def run_hook(tmp_path, payload):
    lib_dir = tmp_path / "lib"
    lib_dir.mkdir()
    capture = tmp_path / "capture.jsonl"
    (lib_dir / "agent_hook.py").write_text(
        "import os, pathlib, sys\n"
        "pathlib.Path(os.environ['CAPTURE_PATH']).open('a').write(sys.stdin.read() + '\\n')\n"
    )
    env = os.environ.copy()
    env["CAPTURE_PATH"] = str(capture)
    result = subprocess.run(
        [sys.executable, str(HOOK), str(lib_dir)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        env=env,
        timeout=5,
        check=False,
    )
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline and not capture.exists():
        time.sleep(0.01)
    records = [json.loads(line) for line in capture.read_text().splitlines()] if capture.exists() else []
    return result, records


@pytest.mark.parametrize(
    ("payload", "expected"),
    [
        (
            {
                "session_id": "s1",
                "hook_event_name": "SessionStart",
                "model": "gpt-5",
                "cwd": "/tmp/project",
            },
            {"event": "session_start", "status": "running", "model": "gpt-5", "cwd": "/tmp/project"},
        ),
        (
            {
                "session_id": "s1",
                "hook_event_name": "PreToolUse",
                "tool_name": "shell",
                "tool_use_id": "t1",
                "agent_id": "a1",
                "agent_type": "worker",
            },
            {
                "event": "tool_call",
                "status": "running",
                "tool": "Bash",
                "toolId": "t1",
                "toolStatus": "running",
                "agentId": "a1",
                "agentType": "worker",
            },
        ),
        (
            {
                "session_id": "s1",
                "hook_event_name": "PostToolUse",
                "tool_name": "spawn_agent",
                "tool_use_id": "t2",
                "duration_ms": 45,
                "tool_response": {
                    "agentId": "a2",
                    "description": "inspect tests",
                    "resolvedModel": "gpt-5-mini",
                },
            },
            {
                "event": "tool_call",
                "status": "running",
                "tool": "Agent",
                "toolId": "t2",
                "toolStatus": "completed",
                "durationMs": 45,
                "spawnedAgentId": "a2",
                "agentDescription": "inspect tests",
                "agentModel": "gpt-5-mini",
            },
        ),
        (
            {"session_id": "s1", "hook_event_name": "Stop"},
            {"event": "turn", "status": "idle"},
        ),
        (
            {"session_id": "s1", "hook_event_name": "SubagentStop", "agent_id": "a1"},
            {"event": "turn", "status": "idle", "agentId": "a1"},
        ),
        (
            {"session_id": "s1", "hook_event_name": "SessionEnd", "reason": "exit"},
            {"event": "session_end", "status": "ended", "endReason": "exit"},
        ),
    ],
)
def test_emits_v2_record_to_shared_writer(tmp_path, payload, expected):
    result, records = run_hook(tmp_path, payload)

    assert result.returncode == 0
    assert result.stdout == ""
    assert result.stderr == ""
    assert len(records) == 1
    record = records[0]
    assert record["v"] == 2
    assert record["harness"] == "codex"
    assert record["provider"] == "openai"
    assert record["sessionId"] == "s1"
    assert isinstance(record["t"], int)
    assert record["ts"].endswith("Z")
    for key, value in expected.items():
        assert record[key] == value


@pytest.mark.parametrize(
    "stdin",
    ["not json", "[]", '{"session_id":"s1"}', '{"session_id":"s1","hook_event_name":["SessionStart"]}'],
)
def test_invalid_input_stays_silent_and_successful(tmp_path, stdin):
    result = subprocess.run(
        [sys.executable, str(HOOK), str(tmp_path)],
        input=stdin,
        text=True,
        capture_output=True,
        timeout=5,
        check=False,
    )

    assert result.returncode == 0
    assert result.stdout == ""
    assert result.stderr == ""


def test_non_string_session_id_is_not_emitted(tmp_path):
    result, records = run_hook(tmp_path, {"session_id": 42, "hook_event_name": "SessionStart"})

    assert result.returncode == 0
    assert records == []
