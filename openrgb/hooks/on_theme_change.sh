#!/usr/bin/env bash
# Aphotic plugin hook: fired on every theme/wallpaper change (see
# PLUGIN_SYSTEM.md in the aphotic-hypr repo for the contract). Runs
# standalone -- no access to aphotic's own helper functions, only what's
# on PATH -- and reads the resolved palette as JSON on stdin:
#   {"background":"#...","foreground":"#...","cursor":"#...",
#    "colors":{"color0":"#...", ..., "color15":"#..."}}
#
# v1 scope: flat "every device the same color" sync via OpenRGB's own
# CLI (`--mode Static --color RRGGBB`) -- no SDK client dependency, no
# per-device zone mapping yet. See the plugin's README for the
# color4-as-accent convention this relies on.
set -euo pipefail

command -v openrgb >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

palette="$(cat)"

# color4 is this project's established accent slot (see
# Configs/wallust/templates/colors-quickshell-colours.qml's own
# color4->m3primary mapping in aphotic-hypr) -- falls back to foreground
# if a palette is ever missing it.
accent="$(jq -r '.colors.color4 // .foreground // empty' <<<"$palette")"
[[ -n "$accent" ]] || exit 0

hex="${accent#\#}"
openrgb --mode Static --color "$hex" >/dev/null 2>&1 || true
