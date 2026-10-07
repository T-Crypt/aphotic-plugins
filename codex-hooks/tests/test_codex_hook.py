#!/usr/bin/env python3
"""Tests for codex-hooks/hook/codex_hook.py.

Runs the translator against recorded Codex hook payloads (the field
names Codex 0.15x actually sends) and a fixture session log, with a
stub standing in for core's agent_hook.py: it appends every record it
receives on stdin to a capture file, exactly like the writer's
three-sink shape reduced to one sink.

Run with `python3 -m pytest codex-hooks/tests/` or plain
`python3 codex-hooks/tests/test_codex_hook.py`.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOOK = HERE.parent / "hook" / "codex_hook.py"

SID = "01test-sid-0000-0000-000000000000"

# --- fixture session log -------------------------------------------------
#
# Line one is session_meta (the provider lives there); the token_count
# lines carry per-response last_token_usage and rate_limits, the same
# shape Codex 0.15x writes to ~/.codex/sessions/.../rollout-*.jsonl.

SESSION_META = {
    "timestamp": "2026-10-06T12:00:00.000Z",
    "ordinal": 0,
    "type": "session_meta",
    "payload": {
        "session_id": SID,
        "cwd": "/tmp",
        "model_provider": "openai",
        "cli_version": "0.159.2",
        "source": "startup",
    },
}

RESPONSE_ITEM = {
    "timestamp": "2026-10-06T12:00:01.000Z",
    "ordinal": 5,
    "type": "response_item",
    "payload": {"type": "message", "role": "assistant", "content": []},
}

TOKEN_COUNT_10 = {
    "timestamp": "2026-10-06T12:00:02.000Z",
    "ordinal": 10,
    "type": "event_msg",
    "payload": {
        "type": "token_count",
        "info": {
            "last_token_usage": {
                "input_tokens": 100,
                "cached_input_tokens": 5,
                "cache_write_input_tokens": 2,
                "output_tokens": 10,
                "reasoning_output_tokens": 3,
                "total_tokens": 118,
            },
            "model_context_window": 258400,
        },
        "rate_limits": {
            "limit_id": "codex",
            "primary": {"used_percent": 4.0, "window_minutes": 300, "resets_at": 111},
            "secondary": {"used_percent": 5.0, "window_minutes": 10080, "resets_at": 222},
        },
    },
}

TOKEN_COUNT_11 = {
    "timestamp": "2026-10-06T12:00:03.000Z",
    "ordinal": 11,
    "type": "event_msg",
    "payload": {
        "type": "token_count",
        "info": {
            "last_token_usage": {
                "input_tokens": 200,
                "cached_input_tokens": 0,
                "cache_write_input_tokens": 0,
                "output_tokens": 20,
                "reasoning_output_tokens": 0,
                "total_tokens": 220,
            },
        },
        "rate_limits": {
            "limit_id": "codex",
            "primary": {"used_percent": 4.5, "window_minutes": 300, "resets_at": 111},
            "secondary": {"used_percent": 5.0, "window_minutes": 10080, "resets_at": 222},
        },
    },
}

STUB_WRITER = (
    "import json, os, sys, time\n"
    "data = sys.stdin.read()\n"
    "record = json.loads(data)\n"
    "record[\"_t\"] = int(time.time() * 1000)\n"
    "with open(os.environ[\"STUB_CAPTURE\"], \"a\") as fh:\n"
    "    fh.write(json.dumps(record) + \"\\n\")\n"
)

# --- recorded Codex payloads ---------------------------------------------


def payload(event, **extra):
    base = {
        "session_id": SID,
        "hook_event_name": event,
        "model": "gpt-5.5",
        "permission_mode": "bypassPermissions",
    }
    base.update(extra)
    return base


SESSION_START = payload("SessionStart", transcript_path=None, cwd="/tmp", source="startup")
USER_PROMPT = payload(
    "UserPromptSubmit", turn_id="t1", prompt="run the thing", transcript_path=None, cwd="/tmp"
)
PRE_TOOL = payload(
    "PreToolUse",
    turn_id="t1",
    tool_name="shell",
    tool_input={"command": "echo hi"},
    tool_use_id="call_1",
    transcript_path=None,
    cwd="/tmp",
)
POST_TOOL = payload(
    "PostToolUse",
    turn_id="t1",
    tool_name="shell",
    tool_input={"command": "echo hi"},
    tool_response="hi\n",
    tool_use_id="call_1",
    transcript_path=None,
    cwd="/tmp",
)
STOP = payload("Stop", turn_id="t1", stop_hook_active=False, last_assistant_message="DONE",
               transcript_path=None)
SESSION_END = payload("SessionEnd", reason="other", transcript_path=None, cwd="/tmp")
SUBAGENT_STOP = payload("SubagentStop", turn_id="t1", agent_id="a1", agent_type="explorer",
                        transcript_path=None)


class Env:
    """A temp home with a stub writer, a fixture log and the adapter."""

    def __init__(self):
        self.root = Path(tempfile.mkdtemp(prefix="codex-hook-test-"))
        self.lib = self.root / "lib"
        self.lib.mkdir()
        (self.lib / "agent_hook.py").write_text(STUB_WRITER)
        self.state = self.root / "state"
        self.state.mkdir()
        self.capture = self.root / "capture.jsonl"
        self.log = self.root / "rollout.jsonl"
        self.write_log([SESSION_META, RESPONSE_ITEM])
        self.transcript = str(self.log)

    def write_log(self, lines):
        with self.log.open("w") as fh:
            for line in lines:
                fh.write(json.dumps(line) + "\n")

    def append_log(self, line):
        with self.log.open("a") as fh:
            fh.write(json.dumps(line) + "\n")

    def run(self, record, stdin_text=None):
        env = dict(os.environ)
        env["APHOTIC_STATE_HOME"] = str(self.state)
        env["STUB_CAPTURE"] = str(self.capture)
        if isinstance(record, (dict, list)):
            stdin_text = json.dumps(record)
        proc = subprocess.run(
            [sys.executable, str(HOOK), str(self.lib)],
            input=(stdin_text or "").encode(),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert proc.returncode == 0, (
            f"adapter exited {proc.returncode}: {proc.stderr.decode()}"
        )
        return proc

    def records(self, minimum=1, timeout=10):
        """The stub's captured records, polled until at least `minimum`
        arrived: the adapter spawns the writer without waiting for it."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.capture.exists():
                lines = [json.loads(l) for l in self.capture.read_text().splitlines() if l]
                if len(lines) >= minimum:
                    return lines
            time.sleep(0.05)
        if self.capture.exists():
            return [json.loads(l) for l in self.capture.read_text().splitlines() if l]
        return []

    def clear_capture(self):
        if self.capture.exists():
            self.capture.unlink()

    def with_transcript(self, *payloads):
        out = []
        for p in payloads:
            q = dict(p)
            q["transcript_path"] = self.transcript
            out.append(q)
        return out


def test_session_start_becomes_a_v2_record():
    env = Env()
    env.run(env.with_transcript(SESSION_START)[0])
    (record,) = env.records(1)
    assert record["v"] == 2
    assert record["harness"] == "codex"
    assert record["sessionId"] == SID
    assert record["event"] == "session_start"
    assert record["status"] == "running"
    assert record["model"] == "gpt-5.5"
    assert record["cwd"] == "/tmp"
    assert record["source"] == "startup"
    assert record["provider"] == "openai"
    # Lifecycle events are not usage events: no extra records.
    assert len(env.records(1)) == 1


def test_prompt_and_stop_map_to_turns():
    env = Env()
    env.run(env.with_transcript(USER_PROMPT)[0])
    (record,) = env.records(1)
    assert record["event"] == "turn"
    assert record["status"] == "running"
    env.clear_capture()
    env.run(env.with_transcript(STOP)[0])
    records = env.records(1)
    (turn,) = [r for r in records if r["event"] == "turn"]
    assert turn["status"] == "idle"
    # prompt / last_assistant_message must never reach the writer
    for r in records:
        assert "prompt" not in r
        assert "last_assistant_message" not in r


def test_tool_events_carry_tool_status_and_alias():
    env = Env()
    start, post = env.with_transcript(PRE_TOOL, POST_TOOL)
    env.run(start)
    (pre,) = env.records(1)
    assert pre["event"] == "tool_call"
    assert pre["toolStatus"] == "running"
    assert pre["tool"] == "Bash"  # Codex's `shell` alias, graph vocabulary
    assert pre["toolId"] == "call_1"
    # tool_input is a privacy hole: it must not be written
    assert "tool_input" not in pre and "tool_response" not in pre

    env.clear_capture()
    env.run(post)
    records = env.records(1)
    (tool,) = [r for r in records if r["event"] == "tool_call"]
    assert tool["toolStatus"] == "completed"
    assert "tool_response" not in tool

    # A name the alias table does not know passes through untouched.
    env.clear_capture()
    exotic = dict(PRE_TOOL)
    exotic["tool_name"] = "mcp__filesystem__read_file"
    env.run(env.with_transcript(exotic)[0])
    (passthrough,) = env.records(1)
    assert passthrough["tool"] == "mcp__filesystem__read_file"


def test_post_tool_use_adds_usage_and_quota_from_the_log():
    env = Env()
    env.append_log(TOKEN_COUNT_10)
    env.run(env.with_transcript(POST_TOOL)[0])
    records = env.records(3)
    # The adapter spawns one writer per record without waiting, so the
    # writer's own timestamps order them, not the spawn order.
    by_kind = {r["event"]: r for r in records}
    assert set(by_kind) == {"tool_call", "usage", "quota"}, [r["event"] for r in records]

    usage = by_kind["usage"]
    assert usage["harness"] == "codex"
    assert usage["provider"] == "openai"
    assert usage["inputTokens"] == 100
    assert usage["outputTokens"] == 10
    assert usage["reasoningTokens"] == 3
    assert usage["cacheReadTokens"] == 5
    assert usage["cacheWriteTokens"] == 2

    quota = by_kind["quota"]
    # Codex's positional names resolve to the feed's canonical window
    # keys from each window's length (300 min -> fiveHour, 10080 ->
    # sevenDay), which is what the consumers draw.
    assert quota["quota"] == {
        "fiveHour": {"usedPercent": 4.0, "resetsAt": 111},
        "sevenDay": {"usedPercent": 5.0, "resetsAt": 222},
    }


def test_unknown_window_lengths_keep_their_own_names():
    env = Env()
    odd = dict(TOKEN_COUNT_10)
    payload = dict(odd["payload"])
    payload["rate_limits"] = {
        "limit_id": "codex",
        "primary": {"used_percent": 9.0, "window_minutes": 720, "resets_at": 333},
    }
    odd["ordinal"] = 12
    odd["payload"] = payload
    env.append_log(odd)
    env.run(env.with_transcript(POST_TOOL)[0])
    records = env.records(3)
    by_kind = {r["event"]: r for r in records}
    # 720 minutes is no window the feed knows: it stays under the name
    # Codex gave it instead of being renamed to something false.
    assert by_kind["quota"]["quota"] == {
        "primary": {"usedPercent": 9.0, "resetsAt": 333},
    }


def test_a_token_count_is_counted_once_no_matter_who_sees_it():
    env = Env()
    env.append_log(TOKEN_COUNT_10)
    first = env.with_transcript(POST_TOOL)[0]
    env.run(first)
    assert len(env.records(3)) == 3

    # The same log tail again (a parallel tool call, or Stop right
    # after): only the lifecycle record, no repeated usage/quota.
    env.clear_capture()
    env.run(first)
    (again,) = env.records(1)
    assert again["event"] == "tool_call"

    env.clear_capture()
    env.run(env.with_transcript(STOP)[0])
    (stop,) = env.records(1)
    assert stop["event"] == "turn"

    # SessionEnd follows Stop on every real session: still no repeat.
    env.clear_capture()
    end = dict(SESSION_END)
    end["transcript_path"] = env.transcript
    env.run(end)
    (ended,) = env.records(1)
    assert ended["event"] == "session_end"
    assert ended["status"] == "ended"
    assert ended["endReason"] == "other"

    # A newer response's token_count is new information: claimed again.
    env.append_log(TOKEN_COUNT_11)
    env.clear_capture()
    env.run(env.with_transcript(STOP)[0])
    records = env.records(3)
    by_kind = {r["event"]: r for r in records}
    assert set(by_kind) == {"turn", "usage", "quota"}, [r["event"] for r in records]
    assert by_kind["usage"]["inputTokens"] == 200


def test_provider_comes_from_the_log_not_a_guessed_default():
    env = Env()
    local = json.loads(json.dumps(SESSION_META))
    local["payload"]["model_provider"] = "llama-swap"
    env.write_log([local, RESPONSE_ITEM])
    env.run(env.with_transcript(SESSION_START)[0])
    (record,) = env.records(1)
    assert record["provider"] == "llama-swap"


def test_session_end_maps_its_reason():
    env = Env()
    end = dict(SESSION_END)
    end["transcript_path"] = env.transcript
    env.run(end)
    (record,) = env.records(1)
    assert record["event"] == "session_end"
    assert record["status"] == "ended"
    assert record["endReason"] == "other"


def test_subagent_events_carry_the_agent_identity():
    env = Env()
    stop = dict(SUBAGENT_STOP)
    stop["transcript_path"] = env.transcript
    env.run(stop)
    (record,) = env.records(1)
    assert record["event"] == "turn"
    assert record["status"] == "idle"
    assert record["agentId"] == "a1"
    assert record["agentType"] == "explorer"


def test_unknown_events_and_bad_input_stay_silent():
    env = Env()
    env.run(payload("SomethingNew", transcript_path=env.transcript))
    assert env.records(0) == []
    env.run({"hook_event_name": "SessionStart", "transcript_path": env.transcript})
    assert env.records(0) == []
    env.run(None, stdin_text="this is not json")
    assert env.records(0) == []
    env.run(None, stdin_text="[1, 2, 3]")
    assert env.records(0) == []


def test_a_missing_log_yields_no_usage_but_still_writes_the_record():
    env = Env()
    env.log.unlink()
    payload_ = dict(POST_TOOL)
    payload_["transcript_path"] = str(env.log)
    env.run(payload_)
    (record,) = env.records(1)
    assert record["event"] == "tool_call"
    assert "provider" not in record


if __name__ == "__main__":
    failed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"PASS {name}")
            except AssertionError as e:
                failed += 1
                print(f"FAIL {name}: {e}")
    sys.exit(1 if failed else 0)
