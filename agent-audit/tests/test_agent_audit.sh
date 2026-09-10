#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/agent-audit/plugin.toml"
PANE="$ROOT/agent-audit/qml/AgentAuditWorkspace.qml"
SERVICE="$ROOT/agent-audit/qml/AgentAuditService.qml"
TAG_CHIP="$ROOT/agent-audit/qml/TagChip.qml"
QMLDIR="$ROOT/agent-audit/qml/qmldir"

# Every "this must not appear" check below runs against a comment-stripped
# copy. Prose explaining why a thing was removed names that thing, and a
# naive grep then fails on the explanation. The singleton reachability
# test in core strips comments for the same reason.
STRIPPED="$(mktemp -d)"
trap 'rm -rf "$STRIPPED"' EXIT
for f in "$PANE" "$SERVICE" "$TAG_CHIP"; do
    sed 's|//.*||' "$f" > "$STRIPPED/$(basename "$f")"
done
NO_PANE="$STRIPPED/AgentAuditWorkspace.qml"
NO_SERVICE="$STRIPPED/AgentAuditService.qml"
NO_CHIP="$STRIPPED/TagChip.qml"

rg -q '^name = "agent-audit"$' "$MANIFEST" || fail "wrong plugin name"
rg -q '^\[ui\.workspace\]$' "$MANIFEST" || fail "missing Workspace registration"
rg -q '^requires_layer = "ai"$' "$MANIFEST" || fail "missing AI gate"
rg -q '^requires_data = "harness"$' "$MANIFEST" || fail "missing harness gate"

# --- The data path -----------------------------------------------------
#
# Every check in this block guards a way the first cut showed an empty
# workstation over a log with a thousand events in it.

rg -q 'agent-events\.jsonl' "$SERVICE" || fail "missing local event feed"
rg -q 'agent-runs' "$SERVICE" || fail "missing run archive reader"
rg -q 'function setSurfaceVisible' "$SERVICE" || fail "missing multi-window visibility tracking"
rg -q 'setSurfaceVisible\(root.owner, visible\)' "$PANE" || fail "Workspace does not identify its visibility owner"

# The pet and the notch tile hold the AgentEvents tail from shell start,
# so this plugin never receives that tail's backlog and has to read the
# same log itself.
rg -q 'id: seeder' "$SERVICE" || fail "service does not seed from the event log"
rg -q 'function reseed' "$SERVICE" || fail "no way to re-read the backlog when the surface opens"
rg -q 'root\.reseed\(\)' "$SERVICE" || fail "the seed is never triggered"

# Runs were sorted by filename, which is sorting UUIDs.
rg -q 'stat -c %Y' "$SERVICE" || fail "run list is not ordered by modification time"
rg -q 'sort -k2,2nr' "$SERVICE" || fail "run list does not sort on the timestamp field"

# The archive was unreachable: loadRun existed and nothing called it.
rg -q 'AgentAuditService\.loadRun\(' "$PANE" || fail "run picker never loads a run"
rg -q 'AgentAuditService\.clearRun\(' "$PANE" || fail "no way back to the live stream"
rg -q 'model: AgentAuditService\.runs' "$PANE" || fail "archived runs are never listed"
rg -q 'component RunDelegate' "$PANE" || fail "run picker has no shared delegate"

# --- Classification ----------------------------------------------------

rg -q 'function eventColour' "$PANE" || fail "event timeline has no semantic colour mapping"
rg -q 'function eventKind' "$PANE" || fail "steps are not classified"
rg -q 'function detailFields' "$PANE" || fail "inspector has no field table"
rg -q 'post_tool_use_failure' "$PANE" || fail "failures are not recognised"
rg -q 'spawnedAgentId' "$PANE" || fail "subagent attribution is not read"

# The schema carries no tool input or output, so nothing here may claim
# to show a payload or a diff.
if rg -q 'payloadText|Payload inspector' "$NO_PANE"; then
    fail "inspector still advertises payloads the event schema does not carry"
fi
# No harness writes an event name containing "memory"; the kind was dead.
if rg -q 'Memory access' "$NO_PANE"; then
    fail "step kinds still include a category no harness emits"
fi
# None of these fields exist on any event, so a metric reading them is
# permanently n/a.
if rg -q 'tokenCount|usage\?\.total_tokens' "$NO_PANE"; then
    fail "a metric reads token fields the schema does not carry"
fi

# --- Presentation ------------------------------------------------------

[[ -f "$TAG_CHIP" ]] || fail "missing reusable TagChip"
rg -q '^TagChip 1\.0 TagChip\.qml$' "$QMLDIR" || fail "TagChip is not exported"
rg -q 'property var tags:' "$PANE" || fail "missing session-local tag state"
rg -q 'signal reportRequested' "$PANE" || fail "missing future report wiring signal"
rg -q 'id: tagInput' "$PANE" || fail "missing inline tag editor"
rg -q 'onEvidenceChanged:' "$PANE" || fail "step selection is not reconciled when evidence changes"
rg -q '!root\.evidence\.includes\(root\.selectedEvent\)' "$PANE" || fail "stale step selection is not cleared"
rg -q 'orientation: ListView\.Horizontal' "$PANE" || fail "header tags are allowed to wrap under the workbench"

# The workspace host draws its own chrome from the shared design system.
# A plugin sitting inside it that rolls its own radii and type scale is
# the reason this surface read as a foreign app.
for token in 'Tokens\.rounding' 'Tokens\.spacing' 'Tokens\.padding' 'Tokens\.font'; do
    rg -q "$token" "$PANE" || fail "workspace does not use $token"
    rg -q "$token" "$TAG_CHIP" || fail "TagChip does not use $token"
done
rg -q 'Tokens\.font\.mono' "$PANE" || fail "fixed-pitch text does not use the shared mono token"
for component in StyledRect StyledText; do
    rg -q "$component" "$PANE" || fail "workspace does not use $component"
done

# Qt's font.family takes one family name and does not parse a CSS
# fallback list, so "JetBrains Mono, Fira Code, monospace" resolves to
# nothing and silently renders in the default sans.
if rg -q 'font\.family:.*,' "$NO_PANE" "$NO_CHIP"; then
    fail "font.family carries a comma list Qt cannot resolve"
fi
if rg -q 'font\.pixelSize' "$NO_PANE" "$NO_CHIP"; then
    fail "hardcoded pixel type size instead of a Tokens font style"
fi

# --- Colour ------------------------------------------------------------

if rg -q '#[0-9A-Fa-f]{6,8}|Qt\.rgba\(' "$NO_PANE" "$NO_CHIP"; then
    fail "agent-audit contains a hardcoded color"
fi
rg -q 'Colours\.palette' "$PANE" || fail "colours do not resolve through the generated palette"

# Status has to stay readable under a palette wallust derived from a
# wallpaper, where the ANSI slots carry no guaranteed hue.
rg -q 'function statusHue' "$PANE" || fail "status colours are not derived from the live palette"
rg -q 'statusReference: Colours\.palette' "$PANE" || fail "status derivation is not anchored to the palette"
for role in statusPass statusWarn statusFail; do
    rg -q "readonly property color $role: root\.statusHue\(" "$PANE" || fail "$role is not a derived status colour"
done

# Warning and the agent accent were the same palette property, so the
# two states were never distinguishable.
accents="$(rg -o 'readonly property color accent[A-Za-z]+: Colours\.palette\.[A-Za-z0-9]+' "$PANE" | sed 's/.*palette\.//' | sort)"
[[ "$(echo "$accents" | wc -l)" -eq "$(echo "$accents" | sort -u | wc -l)" ]] || fail "two accent roles resolve to the same palette colour"

if rg -q 'tags|reportRequested' "$NO_SERVICE"; then
    fail "UI-only tags or report intent leaked into the backend service"
fi
if rg -q 'Colours\.tPalette\.m3surfaceContainerHigh|AgentGraph' "$NO_PANE" "$NO_SERVICE"; then
    fail "invalid palette role or plugin dependency"
fi

python3 "$ROOT/tools/build_index.py" --check >/dev/null || fail "catalogue is stale"
surface="$(jq -c '.plugins[] | select(.name == "agent-audit") | .ui.surfaces[]? | select(.surface == "workspace")' "$ROOT/index.json")"
[[ -n "$surface" ]] || fail "catalogue has no Workspace surface"

echo "PASS: agent-audit"
