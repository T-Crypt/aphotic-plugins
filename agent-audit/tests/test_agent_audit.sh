#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/agent-audit/plugin.toml"
PANE="$ROOT/agent-audit/qml/AgentAuditWorkspace.qml"
SERVICE="$ROOT/agent-audit/qml/AgentAuditService.qml"
TAG_CHIP="$ROOT/agent-audit/qml/TagChip.qml"
QMLDIR="$ROOT/agent-audit/qml/qmldir"

rg -q '^name = "agent-audit"$' "$MANIFEST" || fail "wrong plugin name"
rg -q '^\[ui\.workspace\]$' "$MANIFEST" || fail "missing Workspace registration"
rg -q '^requires_layer = "ai"$' "$MANIFEST" || fail "missing AI gate"
rg -q '^requires_data = "harness"$' "$MANIFEST" || fail "missing harness gate"
rg -q 'agent-events\.jsonl' "$SERVICE" || fail "missing local event feed"
rg -q 'agent-runs' "$SERVICE" || fail "missing run archive reader"
rg -q 'function setSurfaceVisible' "$SERVICE" || fail "missing multi-window visibility tracking"
rg -q 'setSurfaceVisible\(root.owner, visible\)' "$PANE" || fail "Workspace does not identify its visibility owner"
rg -q '^import QtQuick.Controls$' "$PANE" || fail "missing replay controls import"
rg -q 'component StepDelegate' "$PANE" || fail "run tree has no shared step delegate"
rg -q 'component MetricCard' "$PANE" || fail "audit controls have no shared metric card"
rg -q 'function eventColour' "$PANE" || fail "event timeline has no semantic colour mapping"
rg -q 'function payloadText' "$PANE" || fail "payload inspector has no formatted event source"
[[ -f "$TAG_CHIP" ]] || fail "missing reusable TagChip"
rg -q '^TagChip 1\.0 TagChip\.qml$' "$QMLDIR" || fail "TagChip is not exported"
rg -q 'readonly property color applicationBackground: Colours\.palette\.m3surfaceContainer' "$PANE" || fail "application background does not use the generated palette"
rg -q 'readonly property color success: Colours\.palette\.m3tertiaryOnSurface' "$PANE" || fail "success does not use the generated palette"
rg -q 'readonly property color error: Colours\.palette\.m3error' "$PANE" || fail "error does not use the generated palette"
rg -q 'readonly property color warning: Colours\.palette\.m3secondaryOnSurface' "$PANE" || fail "warning does not use the generated palette"
rg -q 'readonly property color toolAccent: Colours\.palette\.m3primaryOnSurface' "$PANE" || fail "tool accents do not use the generated palette"
rg -q 'property var tags:' "$PANE" || fail "missing session-local tag state"
rg -q 'signal reportRequested' "$PANE" || fail "missing future report wiring signal"
rg -q 'id: tagInput' "$PANE" || fail "missing inline tag editor"
rg -q 'onEvidenceChanged:' "$PANE" || fail "payload selection is not reconciled when evidence changes"
rg -q '!root\.evidence\.includes\(root\.selectedEvent\)' "$PANE" || fail "stale payload selection is not cleared"
rg -q 'id: headerTags' "$PANE" || fail "header tag list has no bounded viewport"
rg -q 'orientation: ListView\.Horizontal' "$PANE" || fail "header tags are allowed to wrap under the workbench"
rg -q 'id: reportBar' "$PANE" || fail "missing sticky report bar"
rg -q 'Gradient' "$PANE" || fail "report action has no accent treatment"
rg -q 'font\.family: root\.monoFont' "$PANE" || fail "payload does not use the fixed-pitch token"
if rg -q '#[0-9A-Fa-f]{6,8}|Qt\.rgba\(' "$PANE" "$TAG_CHIP"; then
    fail "agent-audit contains a hardcoded color"
fi
if rg -q 'tags|reportRequested' "$SERVICE"; then
    fail "UI-only tags or report intent leaked into the backend service"
fi
if rg -q 'Colours\.tPalette\.m3surfaceContainerHigh|AgentGraph' "$PANE" "$SERVICE"; then
    fail "invalid palette role or plugin dependency"
fi

python3 "$ROOT/tools/build_index.py" --check >/dev/null || fail "catalogue is stale"
surface="$(jq -c '.plugins[] | select(.name == "agent-audit") | .ui.surfaces[]? | select(.surface == "workspace")' "$ROOT/index.json")"
[[ -n "$surface" ]] || fail "catalogue has no Workspace surface"

echo "PASS: agent-audit"
