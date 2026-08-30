#!/usr/bin/env bash
# codex-hooks/hooks/wire.sh -- called by `aphotic plugin install|enable
# codex-hooks` with one argument: core's lib/aphotic directory. Wires
# this plugin's own codex_hook.sh (not core's agent_hook.sh directly --
# Codex's payload needs translating first, see hook/codex_hook.py) into
# ~/.codex/hooks.json, Codex's dedicated user-level hooks source
# (deliberately not config.toml, so the user's own provider/auth/MCP
# settings there are never touched).
#
# Codex's hooks.json uses the same event schema as Claude Code's
# settings.json hooks for the events wired here (SessionStart,
# PreToolUse, PostToolUse, SubagentStop, Stop, SessionEnd hand the hooked
# command a JSON payload whose field names already match what
# agent_hook.py reads); PostToolUseFailure and Notification do not exist
# in Codex's hook schema at all. PreToolUse/PostToolUse run async because
# Codex executes those two events synchronously (they'd block the
# calling session's own tool call otherwise); SessionEnd is capped at 3
# seconds by Codex itself, so that timeout is hard-stopped there.
#
# Merged with jq rather than templated, so any hooks the user already has
# for other tools are preserved untouched. Idempotent -- matches on the
# plugin's own codex_hook.sh path (not the full command string, since the
# appended lib_dir argument could differ across reinstalls at a different
# clone path) so re-running install/enable replaces the one entry this
# plugin owns rather than duplicating or orphaning it.
set -euo pipefail

lib_dir="$1"
plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook_script="${plugin_dir}/hook/codex_hook.sh"
hooks_dir="$HOME/.codex"
hooks_file="$hooks_dir/hooks.json"

command -v jq >/dev/null 2>&1 || { echo "jq not found; cannot wire Codex hooks" >&2; exit 1; }
chmod +x "$hook_script" "${plugin_dir}/hook/codex_hook.py" 2>/dev/null || true

mkdir -p "$hooks_dir"
[[ -f "$hooks_file" ]] || echo '{}' > "$hooks_file"

if ! jq -e . "$hooks_file" >/dev/null 2>&1; then
    echo "existing $hooks_file is not valid JSON; leaving Codex hooks unconfigured" >&2
    exit 1
fi

full_cmd="${hook_script} $(printf '%q' "$lib_dir")"

tmp="$(mktemp)"
jq \
    --arg cmd "$full_cmd" \
    --arg match "$hook_script" \
    '
    def entry($timeoutSec; $async):
      {matcher: "", hooks: ([{type: "command", command: $cmd}
        + (if $timeoutSec > 0 then {timeoutSec: $timeoutSec} else {} end)
        + (if $async then {async: true} else {} end)])};
    def upsert($event; $timeoutSec; $async):
      .hooks[$event] = ((.hooks[$event] // [])
        | map(select((.hooks // []) | any(.command | startswith($match)) | not))
        + [entry($timeoutSec; $async)]);
    upsert("SessionStart"; 5; false)
    | upsert("PreToolUse"; 10; true)
    | upsert("PostToolUse"; 10; true)
    | upsert("SubagentStop"; 5; false)
    | upsert("Stop"; 5; false)
    | upsert("SessionEnd"; 3; false)
    ' \
    "$hooks_file" > "$tmp" && mv "$tmp" "$hooks_file"
