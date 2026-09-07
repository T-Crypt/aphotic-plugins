#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/dev-ports/plugin.toml"
PANE="$ROOT/dev-ports/qml/DevPortsWorkspace.qml"
SCAN="$ROOT/dev-ports/bin/scan.sh"

STRIPPED="$(mktemp -d)"
trap 'rm -rf "$STRIPPED"' EXIT
sed 's|//.*||' "$PANE" > "$STRIPPED/pane.qml"
NO_PANE="$STRIPPED/pane.qml"

rg -q '^name = "dev-ports"$' "$MANIFEST" || fail "wrong plugin name"
rg -q '^\[ui\.workspace\]$' "$MANIFEST" || fail "missing Workspace registration"
rg -q '^requires_layer = "dev"$' "$MANIFEST" || fail "missing dev-layer gate"
rg -q '^binaries = \["ss", "curl", "xdg-open"\]$' "$MANIFEST" || fail "missing declared runtime binaries"

[[ -x "$SCAN" ]] || fail "scan.sh is not executable"
rg -q 'clear-offline' "$SCAN" || fail "scan.sh has no clear-offline mode"
rg -q '\.value\.status = "offline"' "$SCAN" || fail "scan.sh does not mark stale entries offline"

# Status has to stay readable under a wallust-derived palette that
# carries no guaranteed hue -- same reasoning as agent-audit's own
# statusHue, reused here rather than reinvented.
if rg -q '#[0-9A-Fa-f]{6,8}|Qt\.rgba\(' "$NO_PANE"; then
    fail "dev-ports contains a hardcoded color"
fi
rg -q 'function statusHue' "$PANE" || fail "status colour is not derived from the live palette"
rg -q 'statusReference: Colours\.palette' "$PANE" || fail "status derivation is not anchored to the palette"
rg -q 'Colours\.palette' "$PANE" || fail "colours do not resolve through the generated palette"

for token in 'Tokens\.rounding' 'Tokens\.spacing' 'Tokens\.padding' 'Tokens\.font'; do
    rg -q "$token" "$PANE" || fail "workspace does not use $token"
done
for component in StyledRect StyledText StateLayer; do
    rg -q "$component" "$PANE" || fail "workspace does not use $component"
done

# The pane only scans while it is the active Workspace tab -- no
# singleton, no timer that survives the tab closing.
rg -q 'pragma Singleton' "$PANE" && fail "dev-ports should not be a singleton: it must stop scanning when the tab closes"
rg -q 'Timer \{' "$PANE" || fail "missing scan timer"

python3 "$ROOT/tools/build_index.py" --check >/dev/null || fail "catalogue is stale"
surface="$(jq -c '.plugins[] | select(.name == "dev-ports") | .ui.surfaces[]? | select(.surface == "workspace")' "$ROOT/index.json")"
[[ -n "$surface" ]] || fail "catalogue has no Workspace surface"

echo "PASS: dev-ports"
