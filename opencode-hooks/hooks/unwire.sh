#!/usr/bin/env bash
# opencode-hooks/hooks/unwire.sh -- inverse of wire.sh, for
# `aphotic plugin disable|remove opencode-hooks`. Only removes the
# symlink/config file this plugin's own wire.sh would have created --
# never touches any other plugin the user has in that directory.
set -euo pipefail

dest_dir="$HOME/.config/opencode/plugins"

rm -f "$dest_dir/aphotic_opencode_hook.js" "$dest_dir/.aphotic-hook-config.json"
