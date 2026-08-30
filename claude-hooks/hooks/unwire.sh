#!/usr/bin/env bash
# claude-hooks/hooks/unwire.sh -- inverse of wire.sh, called by
# `aphotic plugin disable|remove claude-hooks`. Drops only the entries
# pointing at this plugin's own agent_hook.sh path and leaves every
# other hook the user has configured untouched. Also prunes hook events
# left with no entries at all, so settings.json doesn't accumulate empty
# arrays.
set -euo pipefail

lib_dir="$1"
hook_script="${lib_dir}/agent_hook.sh"
settings_file="$HOME/.claude/settings.json"

command -v jq >/dev/null 2>&1 || { echo "jq not found; cannot unwire Claude Code hooks" >&2; exit 1; }
[[ -f "$settings_file" ]] || exit 0

if ! jq -e . "$settings_file" >/dev/null 2>&1; then
    echo "existing $settings_file is not valid JSON; leaving Claude Code hooks alone" >&2
    exit 1
fi

tmp="$(mktemp)"
jq \
    --arg cmd "$hook_script" \
    '
    (.hooks // {}) as $hooks
    | .hooks = ($hooks
        | with_entries(.value |= map(select((.hooks // []) | any(.command == $cmd) | not)))
        | with_entries(select((.value | length) > 0)))
    ' \
    "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
