#!/usr/bin/env bash
# Aphotic plugin hook: fired when a ProfileEngine domain profile activates.
# Single positional arg: the profile id ("gaming"). Only ids listed in
# PROFILE_IDS (settings.conf, default "gaming") do anything; every other
# domain's profile is ignored rather than assumed to want lighting.
#
# Activating swaps to the theme accent at full saturation, static -- same
# hue the desktop is already wearing, just unmistakably louder. It is
# deliberately not a different color: the point is "this machine is in
# game mode", not a second palette to keep in sync with the first.
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
openrgb_plugin_run profile activate "${1:-}"
