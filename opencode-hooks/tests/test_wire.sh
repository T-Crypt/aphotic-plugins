#!/usr/bin/env bash
# wire.sh/unwire.sh round trip.
#
# The bug this guards: the plugin's own filename has had three names over
# its life, and wire/unwire only knew the current one. OpenCode loads every
# .js in ~/.config/opencode/plugins, so a leftover from an older wire made
# `aphotic plugin disable` a no-op and `enable` write a second file. Both
# hooks report the same session and every token count doubles.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WIRE="$ROOT/hooks/wire.sh"
UNWIRE="$ROOT/hooks/unwire.sh"

command -v jq >/dev/null 2>&1 || { echo "jq not found; skipping" >&2; exit 0; }

# A HOME and state dir of our own, so this never touches the real config.
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX"
export XDG_STATE_HOME="$SANDBOX/state"
DEST="$HOME/.config/opencode/plugins"
CONFIG="$XDG_STATE_HOME/aphotic/opencode-hook.json"

# An opencode that passes the version gate. wire.sh only reads the version
# and otherwise touches nothing of its own.
mkdir -p "$SANDBOX/bin"
printf '#!/usr/bin/env bash\necho opencode 2.0.18\n' > "$SANDBOX/bin/opencode"
chmod +x "$SANDBOX/bin/opencode"
export PATH="$SANDBOX/bin:$PATH"

# --- enable ------------------------------------------------------------

bash "$WIRE" /opt/lib/aphotic

[[ -L "$DEST/aphotic_opencode_hook.js" ]] || fail "enable did not symlink the hook"
[[ -f "$CONFIG" ]] || fail "enable did not record the hook path in the state dir"
rg -q '"/opt/lib/aphotic/agent_hook\.py"' "$CONFIG" || fail "state config does not name agent_hook.py"

# The state dir, not beside the symlink. See opencode_hook.js's own comment:
# import.meta.url resolves to the link's realpath, so a config next to the
# link was looked for in the plugin repo and never found.
[[ ! -e "$DEST/.aphotic-hook-config.json" ]] \
  || fail "enable still writes the config where the hook cannot read it"

# --- retired names are cleared on enable --------------------------------
#
# Two leftovers, each of which loads as a second copy of this plugin:
# a hand-placed copy from before wire.sh existed, and the pre-plugin-era
# name older wire scripts wrote.
mkdir -p "$DEST"
printf '// stale copy\n' > "$DEST/aphotic-opencode-hook.js"
printf '// stale symlink\n' > "$DEST/opencode_hook.js"

bash "$WIRE" /opt/lib/aphotic

[[ ! -e "$DEST/aphotic-opencode-hook.js" ]] || fail "enable left the hand-placed copy behind"
[[ ! -e "$DEST/opencode_hook.js" ]] || fail "enable left the pre-plugin-era name behind"
[[ -L "$DEST/aphotic_opencode_hook.js" ]] || fail "enable removed its own link"

# --- disable -----------------------------------------------------------

bash "$UNWIRE"

[[ ! -e "$DEST/aphotic_opencode_hook.js" ]] || fail "disable left the live symlink"
[[ ! -e "$CONFIG" ]] || fail "disable left the state config behind"

# Re-seed the retired names and check disable clears them too. A disable
# that only knows the current name is not a disable.
printf '// stale copy\n' > "$DEST/aphotic-opencode-hook.js"
printf '// stale symlink\n' > "$DEST/opencode_hook.js"

bash "$UNWIRE"

[[ ! -e "$DEST/aphotic-opencode-hook.js" ]] || fail "disable left the hand-placed copy behind"
[[ ! -e "$DEST/opencode_hook.js" ]] || fail "disable left the pre-plugin-era name behind"

# --- disable is safe when nothing is wired ------------------------------

bash "$UNWIRE"

# --- the manifest declares what it writes -------------------------------

rg -q 'opencode-hook\.json' "$ROOT/plugin.toml" \
  || fail "[owns] does not declare the state config"

echo "ok: wire/unwire round trip"
