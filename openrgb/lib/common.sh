#!/usr/bin/env bash
# Shared helpers for the OpenRGB Sync plugin's hooks + setup script.
# Sourced, not executed directly -- no shebang execution expected.
#
# Everything device-facing moved to lib/rgb_common.py + scripts/rgb_sync.py
# when the plugin stopped shelling out to the `openrgb` CLI. What is left
# here is the part bash is still the right tool for: locating the plugin's
# own directory, bootstrapping the user's config files, and turning
# settings.conf into the environment the Python side reads.

: "${OPENRGB_PLUGIN_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/aphotic-plugins/openrgb}"
: "${OPENRGB_PLUGIN_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/aphotic-plugins/openrgb}"
export OPENRGB_PLUGIN_CONFIG_DIR OPENRGB_PLUGIN_STATE_DIR
SETTINGS_FILE="$OPENRGB_PLUGIN_CONFIG_DIR/settings.conf"
ZONES_FILE="$OPENRGB_PLUGIN_CONFIG_DIR/zones.conf"

# Plugin's own root dir (parent of lib/), independent of caller's cwd and
# resolved through a directory-level symlink (`aphotic plugin install --link`).
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RGB_SYNC="$PLUGIN_DIR/scripts/rgb_sync.py"

# Copies the shipped config templates into the user's config dir on first
# run only -- never overwrites an existing file, so hand edits are safe.
openrgb_plugin_bootstrap_config() {
  mkdir -p "$OPENRGB_PLUGIN_CONFIG_DIR" "$OPENRGB_PLUGIN_STATE_DIR" 2>/dev/null || return 0
  [[ -f "$SETTINGS_FILE" ]] || cp "$PLUGIN_DIR/config/settings.conf.example" "$SETTINGS_FILE" 2>/dev/null || true
  [[ -f "$ZONES_FILE" ]] || cp "$PLUGIN_DIR/config/zones.conf.example" "$ZONES_FILE" 2>/dev/null || true
}

# Sources settings.conf and exports every key, since rgb_sync.py reads them
# from the environment -- one parser for the file (bash, which is what the
# file's own KEY=VALUE syntax already is), not two.
openrgb_plugin_load_settings() {
  ACCENT_OVERRIDE=""
  EXCLUDE_DEVICES=""
  IDLE_EFFECT="static"
  GAMING_EFFECT="static"
  GAMING_SATURATION="1.0"
  GAMING_VALUE="1.0"
  PROFILE_IDS="gaming"
  AGENT_EFFECT="breathing"
  AGENT_HARNESSES=""
  OPENRGB_SDK_HOST="127.0.0.1"
  OPENRGB_SDK_PORT="6742"
  # settings.conf is the user's own file under their config dir -- sourcing
  # it as plain KEY=VALUE bash is the same trust level as sourcing their
  # own .bashrc.
  # shellcheck disable=SC1090
  [[ -f "$SETTINGS_FILE" ]] && source "$SETTINGS_FILE"
  export ACCENT_OVERRIDE EXCLUDE_DEVICES IDLE_EFFECT GAMING_EFFECT \
    GAMING_SATURATION GAMING_VALUE PROFILE_IDS AGENT_EFFECT AGENT_HARNESSES \
    OPENRGB_SDK_HOST OPENRGB_SDK_PORT
}

# Every hook is the same three steps, so they live here once: bootstrap,
# load settings, hand off to the Python entry point. A missing python3 is
# the one failure worth staying quiet about -- there is no log to write to
# yet at that point.
openrgb_plugin_run() {
  command -v python3 >/dev/null 2>&1 || exit 0
  openrgb_plugin_bootstrap_config
  openrgb_plugin_load_settings
  exec python3 "$RGB_SYNC" "$@"
}
