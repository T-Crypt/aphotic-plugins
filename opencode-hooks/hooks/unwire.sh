#!/usr/bin/env bash
# opencode-hooks/hooks/unwire.sh -- inverse of wire.sh, for
# `aphotic plugin disable|remove opencode-hooks`. Only removes the
# symlinks/config file this plugin's own wire.sh would have created --
# never touches any other plugin the user has in that directory.
set -euo pipefail

dest_dir="$HOME/.config/opencode/plugins"

# The second name is a pre-plugin-era duplicate symlink that older wire
# scripts left behind; remove it here too so a disable really disables.
rm -f "$dest_dir/aphotic_opencode_hook.js" "$dest_dir/opencode_hook.js" \
      "$dest_dir/.aphotic-hook-config.json"
