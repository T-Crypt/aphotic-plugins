#!/usr/bin/env bash
# opencode-hooks/hooks/unwire.sh -- inverse of wire.sh, for
# `aphotic plugin disable|remove opencode-hooks`. Only removes the
# symlinks/config file this plugin's own wire.sh would have created --
# never touches any other plugin the user has in that directory.
set -euo pipefail

dest_dir="$HOME/.config/opencode/plugins"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/aphotic"

# Every name this plugin's history has ever written under, not just the
# current one. `aphotic plugin disable` is only a real disable if it also
# clears the files an earlier version left behind, and OpenCode loads every
# .js in that directory, so one survivor keeps double-reporting.
rm -f "$dest_dir/aphotic_opencode_hook.js" \
      "$dest_dir/aphotic-opencode-hook.js" \
      "$dest_dir/opencode_hook.js" \
      "$dest_dir/.aphotic-hook-config.json" \
      "$state_dir/opencode-hook.json"
