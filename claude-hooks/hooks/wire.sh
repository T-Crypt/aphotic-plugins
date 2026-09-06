#!/usr/bin/env bash
# claude-hooks/hooks/wire.sh -- called by `aphotic plugin install|enable
# claude-hooks` with one argument: this shell's own lib/aphotic directory
# (where agent_hook.sh/agent_hook.py live), so this plugin's translator
# never has to assume a fixed clone location. Claude Code's own hook
# payload already matches agent_hook.py's expected field names, so no
# per-harness adapter script is needed here -- agent_hook.sh is wired
# straight into ~/.claude/settings.json.
#
# Merged with jq (guaranteed present, both install profiles' prep stage
# installs it) rather than templated, so any hooks the user already has
# for other tools are preserved untouched. Idempotent -- re-running
# install/enable doesn't duplicate the entry, it replaces the one this
# script itself previously added. SessionEnd is what retires a session
# (Stop fires at the end of every assistant turn, not the session).
set -euo pipefail

lib_dir="$1"
hook_script="${lib_dir}/agent_hook.sh"
statusline_script="${lib_dir}/agent_statusline.sh"
settings_dir="$HOME/.claude"
settings_file="$settings_dir/settings.json"

command -v jq >/dev/null 2>&1 || { echo "jq not found; cannot wire Claude Code hooks" >&2; exit 1; }

if [[ ! -x "$hook_script" ]]; then
    echo "agent_hook.sh not found or not executable at $hook_script" >&2
    exit 1
fi

mkdir -p "$settings_dir"
[[ -f "$settings_file" ]] || echo '{}' > "$settings_file"

if ! jq -e . "$settings_file" >/dev/null 2>&1; then
    echo "existing $settings_file is not valid JSON; leaving Claude Code hooks unconfigured" >&2
    exit 1
fi

tmp="$(mktemp)"
jq \
    --arg cmd "$hook_script" \
    '
    def entry($timeout): {matcher: "", hooks: [{type: "command", command: $cmd} + (if $timeout > 0 then {timeout: $timeout} else {} end)]};
    def upsert($event; $timeout):
      .hooks[$event] = ((.hooks[$event] // []) | map(select((.hooks // []) | any(.command == $cmd) | not)) + [entry($timeout)]);
    upsert("SessionStart"; 10)
    | upsert("UserPromptSubmit"; 10)
    | upsert("PreToolUse"; 30)
    | upsert("PostToolUse"; 30)
    | upsert("PostToolUseFailure"; 30)
    | upsert("Notification"; 10)
    | upsert("PreCompact"; 10)
    | upsert("PostCompact"; 10)
    | upsert("Stop"; 0)
    | upsert("SubagentStop"; 0)
    | upsert("SessionEnd"; 10)
    ' \
    "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"

# The statusLine slot holds one command, and it is the only place Claude
# Code reports how much of a rate-limit window a session has spent -- the
# notch tile's quota bars have no other source. Claiming it replaces
# whatever the user sees in their own terminal, so a slot that already
# belongs to someone else is left alone and reported rather than taken:
# the bars stay empty, every hook above still works, and the user decides.
if [[ -x "$statusline_script" ]]; then
    existing="$(jq -r '.statusLine.command // ""' "$settings_file")"
    if [[ -z "$existing" || "$existing" == "$statusline_script" ]]; then
        tmp="$(mktemp)"
        jq --arg cmd "$statusline_script" \
            '.statusLine = {type: "command", command: $cmd}' \
            "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
    else
        echo "$settings_file already has a statusLine command ($existing); leaving it alone. The notch tile's quota bars stay empty until it points at $statusline_script." >&2
    fi
fi
