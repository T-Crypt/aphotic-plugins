#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE="$ROOT/agent-graph/qml/AgentGraphService.qml"
TAB="$ROOT/agent-graph/qml/AgentGraphTab.qml"
README="$ROOT/agent-graph/README.md"

rg -q 'AgentProviders\.llamaSwapLoadedModels' "$SERVICE" || fail "loaded llama-swap models are ignored"
rg -q 'function _llamaSwapModel' "$SERVICE" || fail "missing llama-swap model resolver"
rg -q 'toLowerCase\(\)' "$SERVICE" || fail "model matching is not case-insensitive"
rg -q 'slice\(slash \+ 1\)' "$SERVICE" || fail "provider-prefixed models are not normalized"
rg -q 'llamaSwapModel \? "llama-swap"' "$SERVICE" || fail "sessions never resolve to llama-swap"
rg -q 'ollamaLoadedModels\.length > 0.*llamaSwapLoadedModels\.length > 0' "$SERVICE" || fail "GPU contention ignores llama-swap"
rg -q 'LlamaSwapStats\.hold\("agent-graph", root\.wantsStats\)' "$SERVICE" || fail "graph stats hold is not visibility-bound"
rg -q 'readonly property var llamaSwapSessions' "$SERVICE" || fail "provider models have no standalone graph nodes"
rg -q 'LlamaSwapStats\.generating' "$SERVICE" || fail "provider nodes have no generating state"
rg -q 'AgentGraphService\.graphSessions' "$TAB" || fail "live graph omits provider nodes"
rg -q 'root\.replayMode \? replay\.sessions : AgentGraphService\.graphSessions' "$TAB" || fail "provider nodes leak into replay or live view"
rg -qi 'llama-swap' "$README" || fail "README does not describe llama-swap nodes"

echo "PASS: agent-graph llama-swap"
