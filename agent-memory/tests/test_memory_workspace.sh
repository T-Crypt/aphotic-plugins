#!/usr/bin/env bash
# The workspace plane, instantiated headlessly against a folded fixture.
#
# The plane imports qs.config, qs.components and qs.services, so the probe
# needs the core shell's QML modules on its import path. It finds them from
# the shell config linked at ~/.config/quickshell/aphotic, and skips when there
# is no core to point at. Offscreen, never on a live session.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN="$ROOT/agent-memory"
ENGINE="$PLUGIN/python/memory_core.py"

shell_root="${APHOTIC_SHELL_ROOT:-}"
if [[ -z "$shell_root" && -e "$HOME/.config/quickshell/aphotic" ]]; then
    shell_root="$(readlink -f "$HOME/.config/quickshell/aphotic")"
fi
if [[ -z "$shell_root" || ! -d "$shell_root/components" ]]; then
    echo "SKIP: no core shell checkout found; set APHOTIC_SHELL_ROOT to the quickshell/aphotic directory"
    exit 0
fi

APHOTIC_SHELL_ROOT="$shell_root" python3 "$ROOT/tools/check_qml_imports.py" "$PLUGIN" \
    || fail "a plugin file uses a core singleton it does not import"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/imports/qs/modules/plugins" "$TEST_ROOT/home" \
         "$TEST_ROOT/config" "$TEST_ROOT/data" "$TEST_ROOT/state/aphotic" "$TEST_ROOT/runtime"
for dir in config components services utils data shaders; do
    [[ -d "$shell_root/$dir" ]] && ln -sfn "$shell_root/$dir" "$TEST_ROOT/imports/qs/$dir"
done
for dir in "$shell_root"/modules/*/; do
    [[ -d "$dir" ]] && ln -sfn "$dir" "$TEST_ROOT/imports/qs/modules/$(basename "$dir")"
done
ln -sfn "$PLUGIN/qml" "$TEST_ROOT/imports/qs/modules/plugins/agentMemory"

cat > "$TEST_ROOT/bin/aphotic" <<STUB
#!/usr/bin/env bash
[[ "\${1:-}" == "memory" ]] || { echo "unexpected command: \$1" >&2; exit 2; }
shift
exec python3 "$ENGINE" "\$@"
STUB
chmod +x "$TEST_ROOT/bin/aphotic"

cp "$PLUGIN/tests/fixtures/agent-events.jsonl" "$TEST_ROOT/state/aphotic/agent-events.jsonl"

output="$(
    env -u WAYLAND_DISPLAY \
        PATH="$TEST_ROOT/bin:$PATH" \
        QML2_IMPORT_PATH="$TEST_ROOT/imports" \
        QT_QPA_PLATFORM=offscreen \
        HOME="$TEST_ROOT/home" \
        XDG_CONFIG_HOME="$TEST_ROOT/config" \
        XDG_DATA_HOME="$TEST_ROOT/data" \
        XDG_STATE_HOME="$TEST_ROOT/state" \
        XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
        APHOTIC_STATE_HOME="$TEST_ROOT/state/aphotic" \
        timeout 40 qs -p "$PLUGIN/tests/MemoryWorkspaceProbe.qml" 2>&1
)" || true

for line in "the workspace plane instantiated" "the plane read the folded store" \
            "the plane's palette resolved" "the selected project lists its tools" \
            "the plane lists the harnesses it can inject into" "the plane reads lessons and imports"; do
    grep -qF "PASS: $line" <<<"$output" || { printf '%s\n' "$output"; fail "expected a PASS for: $line"; }
done
grep -qF "FAIL:" <<<"$output" && { printf '%s\n' "$output"; fail "the probe reported a failure"; }

# Only this plugin's own files are held to the error scan; the shell's
# services may warn offscreen about things no plugin controls.
if grep -E 'ReferenceError|TypeError|is not a type|Unable to assign|Cannot assign|has no property named|Cannot read property|Binding loop detected' <<<"$output" \
        | grep -F "agentMemory/" >/dev/null; then
    printf '%s\n' "$output"
    fail "the plane logged a QML error"
fi

echo "PASS: agent-memory workspace"
