#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN="$ROOT/llama-swap"
MANIFEST="$PLUGIN/plugin.toml"
SERVICE="$PLUGIN/qml/LlamaSwapService.qml"
TILE="$PLUGIN/qml/LlamaSwapNotchTile.qml"
QMLDIR="$PLUGIN/qml/qmldir"

for file in "$MANIFEST" "$SERVICE" "$TILE" "$QMLDIR" "$PLUGIN/README.md"; do
    [[ -f "$file" ]] || fail "missing ${file#$ROOT/}"
done

rg -q '^name = "llama-swap"$' "$MANIFEST" || fail "wrong plugin name"
rg -q '^capabilities = \["ui-surface"\]$' "$MANIFEST" || fail "missing UI capability"
rg -q '^\[ui\.notch_tile\]$' "$MANIFEST" || fail "missing notch tile registration"
rg -q '^id = "ai"$' "$MANIFEST" || fail "wrong notch tile id"
rg -q '^icon = "memory"$' "$MANIFEST" || fail "wrong notch icon"
rg -q '^label = "AI"$' "$MANIFEST" || fail "wrong notch label"
rg -q '^requires_layer = "ai"$' "$MANIFEST" || fail "missing AI layer gate"
rg -q '^binaries = \["curl", "pgrep"\]$' "$MANIFEST" || fail "spawned binaries are not declared"

rg -q '^singleton LlamaSwapService 1\.0 LlamaSwapService\.qml$' "$QMLDIR" || fail "service is not exported"
rg -q '^LlamaSwapNotchTile 1\.0 LlamaSwapNotchTile\.qml$' "$QMLDIR" || fail "tile is not exported"
rg -q 'function setSurfaceVisible' "$SERVICE" || fail "service has no visibility refcount"
rg -q 'LlamaSwapStats\.hold\("llama-swap-tile", root\.active\)' "$SERVICE" || fail "stats hold is not visibility-bound"
rg -q 'AiProviders\.llamaSwapRunningModels' "$SERVICE" || fail "service does not consume running models"
rg -q 'ResourceEngine\.claimById\(`llama-swap-proc-\$\{pid\}`\)' "$SERVICE" || fail "service does not resolve measured model claims"
rg -q 'command: \["pgrep", "-a", "-x", "llama-server"\]' "$SERVICE" || fail "service does not map model ports to PIDs"
rg -q 'api/models/unload' "$SERVICE" || fail "service has no unload request"

rg -q 'AiConfig\.llamaSwapHostConfigured' "$TILE" || fail "tile has no unset-host state"
rg -q '^import qs\.services$' "$TILE" || fail "tile does not import shared shell services"
rg -q 'AiProviders\.llamaSwapReachable' "$TILE" || fail "tile has no host reachability state"
rg -q 'LlamaSwapService\.models' "$TILE" || fail "tile does not list models"
rg -q 'LlamaSwapStats\.tokensPerSecond' "$TILE" || fail "tile does not show live throughput"
rg -q 'LlamaSwapStats\.nCtx' "$TILE" || fail "tile does not show context"
rg -q 'InferenceMode\.enter\(' "$TILE" || fail "tile cannot enter inference mode"
rg -q 'InferenceMode\.exit\(' "$TILE" || fail "tile cannot exit inference mode"
rg -q 'LlamaSwapService\.unload\(' "$TILE" || fail "tile has no model unload action"

STRIPPED="$(mktemp -d)"
trap 'rm -rf "$STRIPPED"' EXIT
for file in "$SERVICE" "$TILE"; do
    sed 's|//.*||' "$file" > "$STRIPPED/$(basename "$file")"
done
if rg -q 'Timer\s*\{' "$STRIPPED"; then
    fail "plugin adds a polling timer"
fi
if rg -q '#[0-9A-Fa-f]{6,8}|Qt\.rgba\(' "$STRIPPED"; then
    fail "plugin contains a hardcoded color"
fi
for token in 'Tokens\.rounding' 'Tokens\.spacing' 'Tokens\.padding' 'Tokens\.font' 'Colours\.palette'; do
    rg -q "$token" "$TILE" || fail "tile does not use $token"
done

echo "PASS: llama-swap"
