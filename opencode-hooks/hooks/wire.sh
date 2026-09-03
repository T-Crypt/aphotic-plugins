#!/usr/bin/env bash
# opencode-hooks/hooks/wire.sh -- called by `aphotic plugin install|enable
# opencode-hooks` with one argument: core's lib/aphotic directory.
# Symlinks this plugin's own opencode_hook.js into OpenCode's global
# plugin auto-discovery directory (~/.config/opencode/plugins/ -- any
# .js/.ts file dropped there loads at startup, no config.json entry
# needed) and writes a tiny companion config file next to it recording
# core's agent_hook.py path, since the plugin script can't derive that
# from its own location (see opencode_hook.js's own comment). A symlink,
# not a copy, so this plugin's own repo is the only place its logic ever
# needs editing.
set -euo pipefail

lib_dir="$1"
plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin_script="${plugin_dir}/hook/opencode_hook.js"
dest_dir="$HOME/.config/opencode/plugins"

command -v jq >/dev/null 2>&1 || { echo "jq not found; cannot wire OpenCode hooks" >&2; exit 1; }
[[ -f "$plugin_script" ]] || { echo "opencode_hook.js not found at $plugin_script" >&2; exit 1; }

mkdir -p "$dest_dir"
ln -sfn "$plugin_script" "$dest_dir/aphotic_opencode_hook.js"
jq -n --arg p "${lib_dir}/agent_hook.py" '{agentHookPy: $p}' > "$dest_dir/.aphotic-hook-config.json"

# OpenCode discovers plugins once, at startup -- unlike Claude Code and
# Codex, which read their hook config per session, so those two start
# reporting on the next session with no restart. An OpenCode already
# running when this is installed never loads the plugin and says nothing
# about it: it simply never appears in the bar or the graph, which reads
# as a broken plugin rather than a stale process.
if pgrep -x opencode >/dev/null 2>&1; then
    echo "NOTE: OpenCode is running, and loads plugins only at startup." >&2
    echo "      Restart it before this hook reports anything." >&2
fi
