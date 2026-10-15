#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/ios-dev/plugin.toml"
CTL="$ROOT/ios-dev/bin/iosctl"
LIB="$ROOT/ios-dev/bin/lib.sh"

rg -q '^name = "ios-dev"$' "$MANIFEST" || fail "wrong plugin name"

# Every surface, action and keybind carries the gate. A surface that
# slipped through ungated would appear on a machine with no dev layer,
# which is the one thing this plugin promises not to do.
for section in ui.workspace ui.notch_tile ui.settings_pane action action_2 keybind; do
    rg -q "^requires_layer = \"dev\"$" <(sed -n "/^\[${section}\]/,/^\[/p" "$MANIFEST") \
        || fail "[${section}] is missing requires_layer = \"dev\""
done

# A command that names a core subcommand would resolve to nothing, because
# core is tried first and no core file ever names a plugin.
rg -q '^command = "ios"$' "$MANIFEST" || fail "cli does not declare the ios command"
rg -q '^subcommand = ' "$MANIFEST" && fail "cli must be top-level, not a subcommand"

# Declaring the toolchain binaries here would send core down its
# `yay -S <binary-name>` path, and no package by those names exists.
for binary in swift xtool; do
    rg -q "binaries = \[[^]]*\"${binary}\"" "$MANIFEST" && fail "${binary} must not be in requires.binaries"
done
rg -q 'binaries = \["inotifywait", "usbmuxd"\]' "$MANIFEST" || fail "missing declared runtime binaries"
rg -q 'packages = \["inotify-tools", "usbmuxd"\]' "$MANIFEST" || fail "missing the package-name override"

# Every component and script the manifest names has to exist inside the
# plugin's own tree, or the surface loads nothing and errors nowhere.
for path in $(sed -n 's/^component = "\(.*\)"$/\1/p' "$MANIFEST"; sed -n 's/^script = "\(.*\)"$/\1/p' "$MANIFEST"); do
    [[ -f "$ROOT/ios-dev/$path" ]] || fail "manifest names a missing path: $path"
done

rg -q '^\[api\]' "$MANIFEST" || fail "missing the [api] declaration"
rg -q 'uses = \["notifications.publish"\]' "$MANIFEST" || fail "missing the notifications.publish grant"

for script in bin/iosctl bin/lib.sh bin/ios-setup bin/ios-new bin/ios-run cli/ios.sh; do
    [[ -r "$ROOT/ios-dev/$script" ]] || fail "missing $script"
done
[[ -x "$CTL" ]] || fail "iosctl is not executable"
[[ -x "$ROOT/ios-dev/bin/ios-setup" ]] || fail "ios-setup is not executable"
[[ -x "$ROOT/ios-dev/bin/ios-new" ]] || fail "ios-new is not executable"
[[ -x "$ROOT/ios-dev/bin/ios-run" ]] || fail "ios-run is not executable"

# Nothing in the plugin may run a privileged command on its own. Every
# install step asks, and the package manager asks for the password.
for script in "$ROOT/ios-dev"/bin/* "$ROOT/ios-dev"/cli/*.sh; do
    rg -q '^\s*sudo ' "$script" && fail "$(basename "$script") runs sudo"
done

# The xtool pin covers both architectures, because swift-bin ships both and
# a host that gets an unpinned download gets whatever the asset became.
for arch in X86_64 AARCH64; do
    rg -q "_IOS_XTOOL_SHA_${arch}=\"[0-9a-f]{64}\"" "$LIB" || fail "missing the ${arch} checksum pin"
done
rg -q '_IOS_XTOOL_VERSION="' "$LIB" || fail "missing the pinned xtool version"

# The gate the registry evaluates is evaluated by the engine too, in one
# place, so the CLI cannot be a second way in.
rg -q '_ios_require_layer' "$CTL" || fail "the engine does not check the dev layer"

# The two surfaces that draw both follow the same colour rule: no hardcoded
# status colour, because the derived palette promises no hue.
for pane in qml/IosWorkspace.qml qml/IosNotchTile.qml; do
    NO_PANE="$(mktemp)"
    sed 's|//.*||' "$ROOT/ios-dev/$pane" >"$NO_PANE"
    if rg -q '#[0-9A-Fa-f]{6,8}|Qt\.rgba\(' "$NO_PANE"; then
        fail "$pane contains a hardcoded color"
    fi
    rg -q 'function statusHue' "$ROOT/ios-dev/$pane" || fail "$pane does not derive status colour from the palette"
    rg -q 'Colours\.palette' "$ROOT/ios-dev/$pane" || fail "$pane does not resolve colours through the palette"
done

for token in 'Tokens\.rounding' 'Tokens\.spacing' 'Tokens\.padding' 'Tokens\.font'; do
    rg -q "$token" "$ROOT/ios-dev/qml/IosWorkspace.qml" || fail "workspace does not use $token"
done
for component in StyledRect StyledText StateLayer MaterialIcon; do
    rg -q "$component" "$ROOT/ios-dev/qml/IosWorkspace.qml" || fail "workspace does not use $component"
done

# A state file written by two processes needs a lock; one writer needs none.
rg -q 'FileView' "$ROOT/ios-dev/qml/IosNotchTile.qml" || fail "the notch tile does not watch the state file"
rg -q 'Timer \{' "$ROOT/ios-dev/qml/IosNotchTile.qml" && fail "the notch tile must not poll"

# Behaviour, not implementation: the engine answers correctly with nothing
# installed, which is the state every user is in before setup.
STATE_HOME="$(mktemp -d)"
trap 'rm -rf "$STATE_HOME"' EXIT
export XDG_CONFIG_HOME="$STATE_HOME"
export HOME="$STATE_HOME"

out="$(HOME="$STATE_HOME" XDG_CONFIG_HOME="$STATE_HOME" "$CTL" doctor)"
[[ "$out" == *"MISSING"* ]] || fail "doctor reports nothing missing on a machine with no toolchain"

paths="$(HOME="$STATE_HOME" XDG_CONFIG_HOME="$STATE_HOME" "$CTL" paths)"
[[ "$paths" == *"$STATE_HOME/aphotic/plugins/ios-dev/state.json"* ]] \
    || fail "paths does not resolve the state file under XDG_CONFIG_HOME"

status="$(HOME="$STATE_HOME" XDG_CONFIG_HOME="$STATE_HOME" "$CTL" status)"
echo "$status" | jq -e '.session.state == "idle" and .ready == false' >/dev/null \
    || fail "status does not report an idle session on a fresh machine"

# The layer gate refuses rather than running quietly, and it is the same
# answer the registry already gives for every surface.
mkdir -p "$STATE_HOME/Aphotic-Hypr"
printf '[install]\nprofile = "full"\nlayers = ["gaming"]\n' >"$STATE_HOME/Aphotic-Hypr/aphotic.toml"
if HOME="$STATE_HOME" APHOTIC_DOTS_DIR="$STATE_HOME/Aphotic-Hypr" "$CTL" doctor >/dev/null 2>&1; then
    fail "the CLI runs on a machine without the dev layer"
fi

python3 "$ROOT/tools/build_index.py" --check >/dev/null || fail "catalogue is stale"
surface="$(jq -c '.plugins[] | select(.name == "ios-dev") | .ui.surfaces[]? | select(.surface == "workspace")' "$ROOT/index.json")"
[[ -n "$surface" ]] || fail "catalogue has no Workspace surface"
jq -e '.plugins[] | select(.name == "ios-dev") | .ui.surfaces[]? | select(.requires_layer == "dev")' \
    "$ROOT/index.json" >/dev/null || fail "the catalogue entry carries no dev gate"

echo "PASS: ios-dev"
