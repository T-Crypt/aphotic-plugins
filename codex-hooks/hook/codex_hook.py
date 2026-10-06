#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors
"""Codex agent hook translator -- v2 contract.

Codex's command hooks hand this process one JSON object on stdin per
event. Its field names already match Claude Code's hook vocabulary
(session_id, tool_use_id, tool_name, transcript_path, ...), so the
work here is the v2 contract (docs/HARNESS_HOOKS_V2.md): build the
record with the contract's names and kinds, and hand core's
agent_hook.py the finished record on stdin -- the same single writer,
validation and sinks as every other adapter.

Two things Codex does not say on the hook payload:

  * tokens and rate limits. Codex records both in the session log the
    payload points at (transcript_path): a `token_count` event_msg
    after every model response carries `last_token_usage` (that
    response's own counts) and `rate_limits` (primary/secondary
    windows). On the events that close a model response
    (PostToolUse, Stop, SessionEnd) this adapter tails the log and
    adds a `usage` record and, when windows are present, a `quota`
    record. `last_token_usage` is a per-response delta, the same
    shape Claude's per-tool usage lines carry, so a consumer summing
    usage records gets a session total, not a running total repeated.
  * which provider served the session. The log's first line
    (session_meta) names `model_provider`, so a session running on a
    local provider is not mislabelled "openai".

A tiny per-session sidecar next to the writer's own session files
remembers the last `token_count` ordinal this adapter already
emitted. One process per event is otherwise stateless, and without
the sidecar two hooks that see the same log tail (parallel tool
calls, Stop followed by SessionEnd) would count one response twice.
The check-and-set on the sidecar takes an exclusive file lock so
hooks that spawn at the same instant still decide in turn. The
writer's stale sweep reclaims the sidecar with the session files.

Nothing in here is allowed to raise: a slow or failing hook blocks
the calling session's own tool execution, and the spawn of the
writer below is the only thing that could.

The translator lives in this plugin's own package, decoupled from
core's agent_hook.py (Configs/.local/lib/aphotic/). codex_hook.sh
passes core's lib dir as argv[1] (supplied by cmd_plugin.sh's
harness-hook wire contract); the same-directory fallback below only
matters for local plugin development against a checked-out core repo
laid out the old way.
"""
import fcntl
import json
import os
import subprocess
import sys

TOOL_NAMES = {
    "shell": "Bash",
    "apply_patch": "Edit",
    "spawn_agent": "Agent",
}

# Codex raw hook name -> (v2 event, status, toolStatus or None). The
# set Codex 0.15x actually fires; PostToolUseFailure is kept because
# newer builds send it for sandboxed tools that fail.
EVENTS = {
    "SessionStart": ("session_start", "running", None),
    "UserPromptSubmit": ("turn", "running", None),
    "PreToolUse": ("tool_call", "running", "running"),
    "PostToolUse": ("tool_call", "running", "completed"),
    "PostToolUseFailure": ("tool_call", "running", "errored"),
    "PreCompact": ("turn", "compacting", None),
    "PostCompact": ("turn", "running", None),
    "PermissionRequest": ("turn", "waiting", None),
    "Stop": ("turn", "idle", None),
    "SubagentStop": ("turn", "idle", None),
    "SubagentStart": ("turn", "running", None),
    "Interrupt": ("turn", "idle", None),
    "SessionEnd": ("session_end", "ended", None),
}

# The events at which a model response has just finished, so the log
# carries a token_count line that no earlier hook has seen yet.
USAGE_EVENTS = {"PostToolUse", "Stop", "SessionEnd"}

# How far back the tail must reach for the newest token_count line:
# one such line is a few KB, and a turn's log growth between the log
# write and this hook's spawn is bounded.
TAIL_BYTES = 128 * 1024
# session_meta is the log's first line; it can be long (embedded
# instructions), so read a bounded head, not the whole file.
HEAD_BYTES = 512 * 1024


def read_head(path, limit):
    """Up to `limit` bytes from the start of `path`, or b'' on any error."""
    if not path:
        return b""
    try:
        with open(path, "rb") as fh:
            return fh.read(limit)
    except OSError:
        return b""


def read_tail(path, limit):
    """Up to `limit` bytes from the end of `path`, or b'' on any error."""
    if not path:
        return b""
    try:
        with open(path, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            if size <= limit:
                fh.seek(0)
            else:
                fh.seek(size - limit)
            return fh.read()
    except OSError:
        return b""


def parse_json_line(line):
    """The line as a JSON object, or None for anything else.

    The tail starts mid-line, so its first fragment fails here and is
    skipped rather than special-cased.
    """
    try:
        data = json.loads(line)
    except (ValueError, TypeError):
        return None
    return data if isinstance(data, dict) else None


def transcript_provider(path):
    """The model_provider from the log's first line, or '' on any miss."""
    head = read_head(path, HEAD_BYTES)
    if not head:
        return ""
    meta = parse_json_line(head.split(b"\n", 1)[0])
    if not meta or meta.get("type") != "session_meta":
        return ""
    payload = meta.get("payload")
    if isinstance(payload, dict) and isinstance(payload.get("model_provider"), str):
        return payload["model_provider"]
    return ""


def token_stats(payload):
    """(usage, quota) fields from one token_count payload, or None."""
    usage = None
    info = payload.get("info")
    if isinstance(info, dict):
        last = info.get("last_token_usage")
        if isinstance(last, dict):
            record = None
            for src, field in (
                ("input_tokens", "inputTokens"),
                ("output_tokens", "outputTokens"),
                ("reasoning_output_tokens", "reasoningTokens"),
                ("cached_input_tokens", "cacheReadTokens"),
                ("cache_write_input_tokens", "cacheWriteTokens"),
            ):
                value = last.get(src)
                if isinstance(value, (int, float)) and not isinstance(value, bool):
                    record = record or {}
                    record[field] = value
            if record:
                usage = record

    quota = None
    limits = payload.get("rate_limits")
    if isinstance(limits, dict):
        windows = {}
        for name in ("primary", "secondary"):
            window = limits.get(name)
            if not isinstance(window, dict):
                continue
            percent = window.get("used_percent")
            if not isinstance(percent, (int, float)) or isinstance(percent, bool):
                continue
            resets = window.get("resets_at")
            if not isinstance(resets, (int, float)) or isinstance(resets, bool):
                resets = 0
            windows[name] = {"usedPercent": percent, "resetsAt": int(resets)}
        if windows:
            quota = windows

    return usage, quota


def latest_token_count(tail):
    """(ordinal, usage, quota) of the newest token_count in the tail.

    None when the tail holds no token_count line at all (the log
    write can land after this process reads it; the next hook sees it).
    """
    best = None
    if not tail:
        return None
    for line in tail.split(b"\n"):
        event = parse_json_line(line)
        if not event or event.get("type") != "event_msg":
            continue
        payload = event.get("payload")
        if not isinstance(payload, dict) or payload.get("type") != "token_count":
            continue
        usage, quota = token_stats(payload)
        ordinal = event.get("ordinal")
        if not isinstance(ordinal, int) or isinstance(ordinal, bool):
            ordinal = None
        best = (ordinal, usage, quota)
    return best


def usage_state_file(state_home, session_id):
    """The sidecar's path, beside the writer's own session files.

    The name ends in .json so the writer's stale sweep reclaims it
    with the session files it belongs to.
    """
    return os.path.join(state_home, "agent-sessions", "%s.codex-usage.json" % session_id)


def claim_token_count(state_home, session_id, ordinal):
    """True if this process may emit the stats of `ordinal`.

    The sidecar's check-and-set runs under an exclusive lock, so two
    hooks spawned at the same instant still decide in turn. A lock or
    write failure means staying silent: the next hook of the session
    sees the same log tail and retries the claim.
    """
    sidecar = usage_state_file(state_home, session_id)
    try:
        os.makedirs(os.path.dirname(sidecar), exist_ok=True)
        with open(sidecar, "a+") as fh:
            fcntl.flock(fh, fcntl.LOCK_EX)
            fh.seek(0)
            try:
                known = json.loads(fh.read() or "{}")
            except ValueError:
                known = {}
            if not isinstance(known, dict):
                known = {}
            if known.get("ordinal") == ordinal:
                return False
            known["ordinal"] = ordinal
            fh.seek(0)
            fh.truncate()
            fh.write(json.dumps(known, separators=(",", ":")) + "\n")
    except OSError:
        return False
    return True


def build_record(payload, raw):
    """The v2 record for one Codex hook payload, or None to drop it."""
    event = EVENTS.get(raw)
    if not event or not isinstance(payload.get("session_id"), str) or not payload["session_id"]:
        return None
    v2_event, status, tool_status = event

    record = {
        "v": 2,
        "harness": "codex",
        "sessionId": payload["session_id"],
        "event": v2_event,
        "status": status,
    }
    for key, field in (("model", "model"), ("cwd", "cwd"), ("source", "source")):
        value = payload.get(key)
        if isinstance(value, str) and value:
            record[field] = value

    tool = payload.get("tool_name")
    if isinstance(tool, str) and tool:
        record["tool"] = TOOL_NAMES.get(tool, tool)
    tool_id = payload.get("tool_use_id")
    if isinstance(tool_id, str) and tool_id:
        record["toolId"] = tool_id
    if tool_status:
        record["toolStatus"] = tool_status
    for key, field in (("agent_id", "agentId"), ("agent_type", "agentType")):
        value = payload.get(key)
        if isinstance(value, str) and value:
            record[field] = value
    if v2_event == "session_end":
        reason = payload.get("reason")
        if isinstance(reason, str) and reason:
            record["endReason"] = reason

    return record


def spawn_writer(lib_dir, record):
    hook_path = os.path.join(lib_dir, "agent_hook.py")
    try:
        proc = subprocess.Popen(
            [sys.executable, hook_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        proc.stdin.write(json.dumps(record, separators=(",", ":")).encode())
        proc.stdin.close()
    except Exception:
        pass


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0

    raw = payload.get("hook_event_name") or ""
    record = build_record(payload, raw)
    if record is None:
        return 0

    state_home = os.environ.get("APHOTIC_STATE_HOME", os.path.expanduser("~/.local/state/aphotic"))
    transcript = payload.get("transcript_path")
    provider = transcript_provider(transcript)
    if provider:
        record["provider"] = provider
    records = [record]

    if raw in USAGE_EVENTS:
        newest = latest_token_count(read_tail(transcript, TAIL_BYTES))
        ordinal = newest[0] if newest else None
        claimed = ordinal is not None and claim_token_count(state_home, record["sessionId"], ordinal)
        if claimed and newest[1]:
            stats = {
                "v": 2,
                "harness": "codex",
                "sessionId": record["sessionId"],
                "event": "usage",
                "status": record["status"],
            }
            if provider:
                stats["provider"] = provider
            stats.update(newest[1])
            records.append(stats)
        if claimed and newest[2]:
            records.append({
                "v": 2,
                "harness": "codex",
                "sessionId": record["sessionId"],
                "event": "quota",
                "status": record["status"],
                "quota": newest[2],
            })

    lib_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    for one in records:
        spawn_writer(lib_dir, one)
    return 0


if __name__ == "__main__":
    sys.exit(main())
