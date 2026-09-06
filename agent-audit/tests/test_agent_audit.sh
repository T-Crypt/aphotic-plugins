#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/agent-audit/plugin.toml"
PANE="$ROOT/agent-audit/qml/AgentAuditWorkspace.qml"
SERVICE="$ROOT/agent-audit/qml/AgentAuditService.qml"

rg -q '^name = "agent-audit"$' "$MANIFEST" || fail "wrong plugin name"
rg -q '^\[ui\.workspace\]$' "$MANIFEST" || fail "missing Workspace registration"
rg -q '^requires_layer = "ai"$' "$MANIFEST" || fail "missing AI gate"
rg -q '^requires_data = "harness"$' "$MANIFEST" || fail "missing harness gate"
rg -q 'agent-events\.jsonl' "$SERVICE" || fail "missing local event feed"
rg -q 'agent-runs' "$SERVICE" || fail "missing run archive reader"
rg -q 'function setSurfaceVisible' "$SERVICE" || fail "missing multi-window visibility tracking"
rg -q 'setSurfaceVisible\(root.owner, visible\)' "$PANE" || fail "Workspace does not identify its visibility owner"
rg -q '^import QtQuick.Controls$' "$PANE" || fail "missing replay controls import"
rg -q 'component EventRow' "$PANE" || fail "event timeline has no shared row chrome"
rg -q 'component EvidenceField' "$PANE" || fail "evidence pane has no structured field chrome"
rg -q 'function eventColour' "$PANE" || fail "event timeline has no semantic colour mapping"
rg -q 'function evidenceFields' "$PANE" || fail "evidence pane still renders raw event JSON"
rg -q 'Colours\.palette\.m3tertiaryOnSurface' "$PANE" || fail "successful tools have no theme-derived accent"
if rg -q 'Colours\.tPalette\.m3surfaceContainerHigh|AgentGraph' "$PANE" "$SERVICE"; then
    fail "invalid palette role or plugin dependency"
fi

python3 "$ROOT/tools/build_index.py" --check >/dev/null || fail "catalogue is stale"
surface="$(jq -c '.plugins[] | select(.name == "agent-audit") | .ui.surfaces[]? | select(.surface == "workspace")' "$ROOT/index.json")"
[[ -n "$surface" ]] || fail "catalogue has no Workspace surface"

echo "PASS: agent-audit"
