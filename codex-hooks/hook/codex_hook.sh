#!/usr/bin/env bash
# codex-hooks/hook/codex_hook.sh -- Codex's side of the single event
# pipeline behind both the bar's agent popout and the agent graph
# surface. Invoked by Codex on SessionStart/PreToolUse/PostToolUse/
# SubagentStop/Stop/SessionEnd with the event JSON piped to stdin, plus
# one positional argument (core's lib/aphotic dir) appended by wire.sh
# into the hooks.json command string itself -- see codex_hook.py for why
# that argument exists. Must be fast and must never fail the hook since
# a slow or failing hook blocks the calling session's own tool execution
# -- hence exec (no extra process) into one python3 worker and the
# unconditional exit 0 on the fallback path, exactly like agent_hook.sh.
set -u

hook_dir="${BASH_SOURCE[0]%/*}"
[[ "$hook_dir" == "${BASH_SOURCE[0]}" ]] && hook_dir="."

exec python3 "$hook_dir/codex_hook.py" "$@" || exit 0
