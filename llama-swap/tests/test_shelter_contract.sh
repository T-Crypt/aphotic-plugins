#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

for plugin in visualizer pet live-wallpaper; do
    manifest="$ROOT/$plugin/plugin.toml"
    first_section="$(rg -n '^\[' "$manifest" | head -1 | cut -d: -f1)"
    shelter_line="$(rg -n '^shelter = "unload"$' "$manifest" | head -1 | cut -d: -f1 || true)"
    [[ -n "$shelter_line" && "$shelter_line" -lt "$first_section" ]] || fail "$plugin shelter setting is not top-level"
done

python3 "$ROOT/tools/build_index.py" --check >/dev/null || fail "catalogue is stale"
jq -e '.plugins[] | select(.name == "llama-swap") | .ui.surfaces[] | select(.surface == "notch" and .id == "ai")' "$ROOT/index.json" >/dev/null \
    || fail "catalogue has no llama-swap AI notch surface"
rg -q '\[`llama-swap`\]\(llama-swap/\)' "$ROOT/README.md" || fail "root README does not list llama-swap"

echo "PASS: shelter and catalogue"
