#!/usr/bin/env bash
# Aphotic plugin hook: fired when a Workspace Profile is launched (see
# PLUGIN_SYSTEM.md in the aphotic-hypr repo for the contract). Runs
# standalone -- no access to aphotic's own helper functions, only what's
# on PATH. Single positional arg: the profile's name.
set -euo pipefail

profile_name="${1:-}"
[[ -n "$profile_name" ]] || exit 0

log_dir="${XDG_DATA_HOME:-$HOME/.local/share}/aphotic-plugins/workspace-session-log"
mkdir -p "$log_dir" 2>/dev/null || exit 0

printf '%s\tlaunched\t%s\n' "$(date -Iseconds)" "$profile_name" >> "$log_dir/launches.log" 2>/dev/null || true
