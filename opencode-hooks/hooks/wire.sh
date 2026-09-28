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

# Keep in sync with MIN_VERSION in opencode_hook.js.
MIN_VERSION="2.0.14"

lib_dir="$1"
plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin_script="${plugin_dir}/hook/opencode_hook.js"
dest_dir="$HOME/.config/opencode/plugins"

command -v jq >/dev/null 2>&1 || { echo "jq not found; cannot wire OpenCode hooks" >&2; exit 1; }
[[ -f "$plugin_script" ]] || { echo "opencode_hook.js not found at $plugin_script" >&2; exit 1; }

# The hook is built on OpenCode's v2 plugin API. A wired-but-dead hook
# reads as a broken plugin, so refuse below the floor instead of wiring
# something that can never report. (The hook also gates itself off at
# runtime, so a hand-wired old install stays quiet rather than noisy.)
oc_version="$(opencode --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1 || true)"
if [[ -z "$oc_version" ]]; then
    echo "WARNING: could not parse an opencode version; wiring anyway." >&2
    echo "         The hook stays silent at runtime below $MIN_VERSION." >&2
elif [[ "$(printf '%s\n%s\n' "$oc_version" "$MIN_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]]; then
    echo "opencode $oc_version is too old for this hook (needs >= $MIN_VERSION); not wired." >&2
    exit 1
fi

mkdir -p "$dest_dir"
ln -sfn "$plugin_script" "$dest_dir/aphotic_opencode_hook.js"
# A pre-plugin-era duplicate symlink used to sit beside the real one,
# pointing into a core checkout that no longer carries the file. OpenCode
# loads every .js in this directory, so a leftover would double-report.
rm -f "$dest_dir/opencode_hook.js"
jq -n --arg p "${lib_dir}/agent_hook.py" '{agentHookPy: $p}' > "$dest_dir/.aphotic-hook-config.json"

# OpenCode rescans the plugins directory when it changes and reloads
# plugins, but a running session may keep the old module it already
# loaded. A restart is the reliable path.
if pgrep -x opencode >/dev/null 2>&1; then
    echo "NOTE: OpenCode is running. Restart it (or start a new session)" >&2
    echo "      to be sure the hook is picked up." >&2
fi
