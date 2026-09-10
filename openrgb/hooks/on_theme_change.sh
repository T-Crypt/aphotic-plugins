#!/usr/bin/env bash
# Aphotic plugin hook: fired on every theme/wallpaper change (see
# PLUGIN_SYSTEM.md in the aphotic-hypr repo for the contract). Runs
# standalone -- no access to aphotic's own helper functions, only what's
# on PATH -- and reads the resolved palette as JSON on stdin:
#   {"background":"#...","foreground":"#...","cursor":"#...",
#    "colors":{"color0":"#...", ..., "color15":"#..."}}
#
# The work itself is in ../scripts/rgb_sync.py: this only exists to load
# settings.conf and hand the palette over. Notably it does NOT end in
# `|| true` the way the previous CLI-based version did -- swallowing the
# exit status there is what hid a real "connection attempt failed" during
# testing. rgb_sync.py owns its own failure posture instead: fail closed,
# log the reason, and say something out loud for the one first-run cause
# (missing udev rules) a user can't be expected to guess.
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
openrgb_plugin_run theme
