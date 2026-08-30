#!/usr/bin/env bash
# codex-hooks/hooks/unwire.sh -- inverse of wire.sh, called by
# `aphotic plugin disable|remove codex-hooks`. Drops only entries whose
# command starts with this plugin's own codex_hook.sh path and leaves
# every other hook the user has configured untouched. Also prunes hook
# events left with no entries at all.
set -euo pipefail

plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook_script="${plugin_dir}/hook/codex_hook.sh"
hooks_file="$HOME/.codex/hooks.json"

command -v jq >/dev/null 2>&1 || { echo "jq not found; cannot unwire Codex hooks" >&2; exit 1; }
[[ -f "$hooks_file" ]] || exit 0

if ! jq -e . "$hooks_file" >/dev/null 2>&1; then
    echo "existing $hooks_file is not valid JSON; leaving Codex hooks alone" >&2
    exit 1
fi

tmp="$(mktemp)"
jq \
    --arg match "$hook_script" \
    '
    (.hooks // {}) as $hooks
    | .hooks = ($hooks
        | with_entries(.value |= map(select((.hooks // []) | any(.command | startswith($match)) | not)))
        | with_entries(select((.value | length) > 0)))
    ' \
    "$hooks_file" > "$tmp" && mv "$tmp" "$hooks_file"
