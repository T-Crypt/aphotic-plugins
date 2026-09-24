#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors
"""Translate one hook payload to v2 and hand it to the shared writer.

Every failure stays silent and exits successfully.
"""
from datetime import datetime, timezone
import json
import os
import subprocess
import sys

TOOL_NAMES = {
    "shell": "Bash",
    "apply_patch": "Edit",
    "spawn_agent": "Agent",
}

EVENTS = {
    "SessionStart": ("session_start", "running", None),
    "PreToolUse": ("tool_call", "running", "running"),
    "PostToolUse": ("tool_call", "running", "completed"),
    "PostToolUseFailure": ("tool_call", "running", "errored"),
    "Stop": ("turn", "idle", None),
    "SubagentStop": ("turn", "idle", None),
    "SessionEnd": ("session_end", "ended", None),
}


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0

    event = payload.get("hook_event_name") or ""
    session_id = payload.get("session_id") or ""
    if not isinstance(event, str) or event not in EVENTS:
        return 0
    if not isinstance(session_id, str) or not session_id:
        return 0

    try:
        kind, status, tool_status = EVENTS[event]
        now = datetime.now(timezone.utc)
        record = {
            "v": 2,
            "harness": "codex",
            "sessionId": session_id,
            "event": kind,
            "t": int(now.timestamp() * 1000),
            "ts": now.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "status": status,
            "provider": "openai",
        }
        if tool_status:
            record["toolStatus"] = tool_status

        for key, field in (
            ("tool_use_id", "toolId"),
            ("agent_id", "agentId"),
            ("agent_type", "agentType"),
            ("duration_ms", "durationMs"),
            ("model", "model"),
            ("cwd", "cwd"),
            ("source", "source"),
        ):
            value = payload.get(key)
            if value not in (None, ""):
                record[field] = value

        tool = payload.get("tool_name")
        if isinstance(tool, str) and tool:
            record["tool"] = TOOL_NAMES.get(tool, tool)

        if event == "SessionEnd":
            reason = payload.get("end_reason") or payload.get("reason")
            if reason:
                record["endReason"] = reason

        response = payload.get("tool_response")
        if isinstance(response, dict):
            for key, field in (
                ("agentId", "spawnedAgentId"),
                ("description", "agentDescription"),
                ("resolvedModel", "agentModel"),
            ):
                value = response.get(key)
                if value not in (None, ""):
                    record[field] = value

        lib_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
        hook_path = os.path.join(lib_dir, "agent_hook.py")
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
