#!/usr/bin/env bash
# game-launcher/tests/test_games_notch_tile.sh -- the notch tile, instantiated
# headlessly.
#
# The tile imports qs.config, qs.components, qs.services and
# qs.services.profile, so this probe needs the core shell's QML modules on
# its import path. It finds them the way a running machine does, from the
# shell checkout the spec names, and says so and exits 0 when there is none
# to point at. A bare `qs -p` probe is the rule here, offscreen, never on a
# live session.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

shell_root="${APHOTIC_SHELL_ROOT:-}"
if [[ -z "$shell_root" && -e "$HOME/.config/quickshell/aphotic" ]]; then
    shell_root="$(readlink -f "$HOME/.config/quickshell/aphotic")"
fi
if [[ -z "$shell_root" || ! -d "$shell_root/components" ]]; then
    echo "SKIP: no core shell checkout found; set APHOTIC_SHELL_ROOT to the quickshell/aphotic directory"
    exit 0
fi

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# The chain is qs -> the symlinked core modules -> the plugin module, the
# same names a running shell resolves.
SHIM="$TEST_ROOT/bin"
mkdir -p "$SHIM" "$TEST_ROOT/imports/qs/modules/plugins" "$TEST_ROOT/home" \
         "$TEST_ROOT/runtime" "$TEST_ROOT/config" "$TEST_ROOT/data" \
         "$TEST_ROOT/state"

for dir in config components services utils data shaders; do
    [[ -d "$shell_root/$dir" ]] && ln -sfn "$shell_root/$dir" "$TEST_ROOT/imports/qs/$dir"
done
for dir in "$shell_root"/modules/*/; do
    [[ -d "$dir" ]] && ln -sfn "$dir" "$TEST_ROOT/imports/qs/modules/$(basename "$dir")"
done
ln -sfn "$ROOT/game-launcher/qml" "$TEST_ROOT/imports/qs/modules/plugins/gameLauncher"

for bin in sh sed awk grep dirname basename pwd cat mkdir ln rm timeout env python3; do
    found="$(command -v "$bin" 2>/dev/null)" || continue
    ln -sf "$found" "$SHIM/$bin"
done
ln -sf "$(command -v qs)" "$SHIM/qs"

# The service resolves the scanner by its installed path, so the throwaway
# HOME gets the same link a real install would have, and the scan runs the
# real script over an empty home: no store client, no game.
mkdir -p "$TEST_ROOT/home/.local/share/aphotic/plugins"
ln -sfn "$ROOT/game-launcher" "$TEST_ROOT/home/.local/share/aphotic/plugins/game-launcher"

output="$(
    env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$TEST_ROOT/home" \
        PATH="$SHIM" \
        APHOTIC_SHELL_ROOT="$shell_root" \
        QML2_IMPORT_PATH="$TEST_ROOT/imports" \
        QT_QPA_PLATFORM=offscreen \
        XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
        XDG_CONFIG_HOME="$TEST_ROOT/config" \
        XDG_DATA_HOME="$TEST_ROOT/data" \
        XDG_STATE_HOME="$TEST_ROOT/state" \
        timeout 40 qs -p "$ROOT/game-launcher/tests/GamesNotchTileProbe.qml" 2>&1
)" || true
printf '%s\n' "$output"

grep -q 'FAIL:' <<<"$output" && die "the notch tile probe failed"
grep -q 'PASS: the games notch tile follows the service, the scan and the gaming profile' <<<"$output" \
    || die "the probe never reached its pass line"

# A tile can also "load" while quietly throwing from a binding. Those
# arrive as warnings rather than a null object, so the run is checked for
# the shapes of them too.
if grep -qE 'ReferenceError|TypeError|is not a type|Unable to assign|Cannot assign|has no property named|Cannot read property|Binding loop detected|Non-existent' <<<"$output"; then
    die "the probe logged a QML error"
fi

echo "PASS: game-launcher notch tile"
