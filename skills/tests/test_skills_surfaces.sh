#!/usr/bin/env bash
# skills/tests/test_skills_surfaces.sh -- the surfaces, instantiated headlessly.
#
# The surfaces import qs.config, qs.components and qs.services, so this probe
# needs the core shell's QML modules on its import path. It finds them the way
# a running machine does, from the shell config that is linked next to the
# plugin tree, and it says so and exits 0 when there is no core to point at.
# A bare `qs -p` probe is the rule here, offscreen, never on a live session.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES="$ROOT/skills/tests/fixtures"

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

# The chain is qs -> bash -> lib/skillscli.sh -> jq/sed/awk -> the stub.
SHIM="$TEST_ROOT/bin"
mkdir -p "$SHIM" "$TEST_ROOT/imports/qs/modules/plugins" "$TEST_ROOT/home" \
         "$TEST_ROOT/runtime" "$TEST_ROOT/config" "$TEST_ROOT/data" \
         "$TEST_ROOT/state"

# `qs` in an import is the core shell's own directory, so the probe's import
# path is that directory wearing a different hat: the modules get linked in
# beside the plugin's own, which is how a running shell resolves the same
# names.
for dir in config components services utils data shaders; do
    [[ -d "$shell_root/$dir" ]] && ln -sfn "$shell_root/$dir" "$TEST_ROOT/imports/qs/$dir"
done
for dir in "$shell_root"/modules/*/; do
    [[ -d "$dir" ]] && ln -sfn "$dir" "$TEST_ROOT/imports/qs/modules/$(basename "$dir")"
done
ln -sfn "$ROOT/skills/qml" "$TEST_ROOT/imports/qs/modules/plugins/skills"

for bin in bash sh jq column awk sed tr head cut sha256sum dirname basename pwd \
           cat cp mkdir ln rm timeout env; do
    found="$(command -v "$bin" 2>/dev/null)" || continue
    ln -sf "$found" "$SHIM/$bin"
done
ln -sf "$(command -v qs)" "$SHIM/qs"

# The service resolves the plugin by its installed path, so the throwaway
# HOME gets the same link a real install would have.
mkdir -p "$TEST_ROOT/home/.local/share/aphotic/plugins"
ln -sfn "$ROOT/skills" "$TEST_ROOT/home/.local/share/aphotic/plugins/skills"

chmod +x "$FIXTURES/skills-manager-cli"

output="$(
    env -u WAYLAND_DISPLAY \
        HOME="$TEST_ROOT/home" \
        PATH="$SHIM" \
        APHOTIC_SKILLS_CLI="$FIXTURES/skills-manager-cli" \
        SKILLS_STUB_FIXTURES="$FIXTURES" \
        QML2_IMPORT_PATH="$TEST_ROOT/imports" \
        QT_QPA_PLATFORM=offscreen \
        XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
        timeout 40 qs -p "$ROOT/skills/tests/SkillsSurfacesProbe.qml" 2>&1
)" || true
printf '%s\n' "$output"

grep -q 'FAIL:' <<<"$output" && die "the surfaces probe failed"
grep -q 'PASS: every named surface and shared part instantiates' <<<"$output" \
    || die "the probe never reached its pass line"

# A surface can also "load" while quietly throwing from a binding. Those
# arrive as warnings rather than a null object, so the run is checked for the
# shapes of them too.
if grep -qE 'ReferenceError|TypeError|is not a type|Unable to assign|Cannot assign|has no property named|Cannot read property|Binding loop detected|Non-existent' <<<"$output"; then
    die "the probe logged a QML error"
fi
