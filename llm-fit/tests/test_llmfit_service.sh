#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/imports/qs/modules/plugins"
ln -s "$ROOT/llm-fit/qml" "$TEST_ROOT/imports/qs/modules/plugins/llmFit"

run_probe() {
    env -u WAYLAND_DISPLAY \
    PATH="$TEST_ROOT/bin:$PATH" \
    QML2_IMPORT_PATH="$TEST_ROOT/imports" \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
    timeout 15 qs -p "$ROOT/llm-fit/tests/LlmFitServiceProbe.qml"
}

cp "$ROOT/llm-fit/tests/fixtures/llmfit.sh" "$TEST_ROOT/bin/llmfit"
chmod +x "$TEST_ROOT/bin/llmfit"
OUTPUT="$(run_probe 2>&1)"

printf '%s\n' "$OUTPUT"
grep -q "PASS: successful llmfit scan publishes recommendations" <<<"$OUTPUT"

cp "$ROOT/llm-fit/tests/fixtures/llmfit-broken.sh" "$TEST_ROOT/bin/llmfit"
chmod +x "$TEST_ROOT/bin/llmfit"
OUTPUT="$(LLMFIT_TEST_EXPECT_FAILURE=1 run_probe 2>&1)"

printf '%s\n' "$OUTPUT"
grep -q "PASS: failed llmfit launch returns the advisor to idle" <<<"$OUTPUT"
