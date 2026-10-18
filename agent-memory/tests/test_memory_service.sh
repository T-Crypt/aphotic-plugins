#!/usr/bin/env bash
# The plane's state holder, driven headlessly.
#
# The state holder on its own, offscreen, under a throwaway state directory.
# The plane is instantiated separately by test_memory_workspace.sh, which
# needs the core shell's modules on its import path.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN="$ROOT/agent-memory"
PROBE="$PLUGIN/tests/MemoryServiceProbe.qml"
FIXTURE="$PLUGIN/tests/fixtures/agent-events.jsonl"
ENGINE="$PLUGIN/python/memory_core.py"

[[ -f "$ENGINE" ]] || fail "the engine is missing: $ENGINE"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/imports/qs/modules/plugins" \
         "$TEST_ROOT/home" "$TEST_ROOT/config" "$TEST_ROOT/data" \
         "$TEST_ROOT/state" "$TEST_ROOT/runtime"
# Mirror the shell's own module link: the module directory is the plugin's
# qml/ directory, symlinked into the qs import root.
ln -s "$PLUGIN/qml" "$TEST_ROOT/imports/qs/modules/plugins/agentMemory"

# The state holder reaches the engine through `aphotic memory`, exactly as a
# live shell does, so the probe gets the same dispatcher: core sources
# cli/memory.sh, and this stub is that source step.
cat > "$TEST_ROOT/bin/aphotic" <<STUB
#!/usr/bin/env bash
[[ "\${1:-}" == "memory" ]] || { echo "unexpected command: \$1" >&2; exit 2; }
shift
exec python3 "$ENGINE" "\$@"
STUB
chmod +x "$TEST_ROOT/bin/aphotic"

PROBE_PATH="$TEST_ROOT/bin:$PATH"

run_probe() {
    env -u WAYLAND_DISPLAY \
        PATH="$PROBE_PATH" \
        QML2_IMPORT_PATH="$TEST_ROOT/imports" \
        QT_QPA_PLATFORM=offscreen \
        HOME="$TEST_ROOT/home" \
        XDG_CONFIG_HOME="$TEST_ROOT/config" \
        XDG_DATA_HOME="$TEST_ROOT/data" \
        XDG_STATE_HOME="$TEST_ROOT/state" \
        XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
        APHOTIC_STATE_HOME="$TEST_ROOT/state/aphotic" \
        MEMORY_SERVICE_CASE="$1" \
        timeout 20 qs -p "$PROBE" || true
}

# Every expected PASS line has to be there, and nothing may have reported a
# failure: a probe that crashes early prints neither, which is exactly the
# case a plain grep-for-PASS would wave through.
expect() {
    local output="$1" line
    shift
    for line in "$@"; do
        grep -qF "PASS: ${line}" <<<"$output" || {
            printf '%s\n' "$output"
            fail "expected a PASS for: ${line}"
        }
    done
    if grep -qF "FAIL:" <<<"$output"; then
        printf '%s\n' "$output"
        fail "the probe reported a failure"
    fi
    return 0
}

# ------------------------------------------------- the paths the plane uses

OUTPUT="$(run_probe path)"
expect "$OUTPUT" \
    "the state home resolved" \
    "the watched log is the one the hooks write, under the state home" \
    "the store lives beside the digest" \
    "the store path is absolute" \
    "the command verb is the manifest's"

# ------------------------------------------------- the fold, end to end

# The fixture log lands in the throwaway state home, so the service finds it
# through the same override the hooks honor.
mkdir -p "$TEST_ROOT/state/aphotic"
cp "$FIXTURE" "$TEST_ROOT/state/aphotic/agent-events.jsonl"

OUTPUT="$(run_probe build)"
expect "$OUTPUT" \
    "the runner captured the command's answer" \
    "the runner is idle once the fold is done" \
    "the fixture project folded into the store" \
    "one session counted" \
    "one turn counted" \
    "both bash calls counted" \
    "the failed bash call counted once as a failure" \
    "the harness is named" \
    "one failure signature" \
    "the signature names the tool" \
    "the signature counted one occurrence" \
    "the signature starts open" \
    "two project rows" \
    "the project row names its path" \
    "the project row carries its calls" \
    "the project name is the basename" \
    "one issue row for that project" \
    "one tool row, counting both calls" \
    "no notes yet" \
    "the digest names the project" \
    "the digest carries the issue" \
    "an action ran the command and the plane sees its result" \
    "the note answered with its id" \
    "forgetting removed the note"

# The store is really on disk, because the CLI and the plane read the same
# file and a fold that only lived in memory would be a lie.
[[ -f "$TEST_ROOT/state/aphotic/agent-memory/store.json" ]] \
    || fail "the build did not write the store"
[[ -f "$TEST_ROOT/state/aphotic/agent-memory/context.md" ]] \
    || fail "the build did not write the digest"
jq -e '.projects["/repo"].tools.bash.calls == 2' \
    "$TEST_ROOT/state/aphotic/agent-memory/store.json" >/dev/null \
    || fail "the store on disk disagrees with what the service read back"
grep -q '^project /repo$' "$TEST_ROOT/state/aphotic/agent-memory/context.md" \
    || fail "the digest on disk does not name the project"
# The probe's note and forget are gone again: an action that leaves state
# behind is not idempotent.
jq -e '.notes | length == 0' "$TEST_ROOT/state/aphotic/agent-memory/store.json" >/dev/null \
    || fail "the probe's note survived its own forget"

# A second build changes nothing: the key ring is what makes the plane
# reopening, or a file it already folded, free.
BEFORE="$(md5sum "$TEST_ROOT/state/aphotic/agent-memory/context.md" | cut -d' ' -f1)"
OUTPUT="$(run_probe build)"
expect "$OUTPUT" "the fixture project folded into the store"
AFTER="$(md5sum "$TEST_ROOT/state/aphotic/agent-memory/context.md" | cut -d' ' -f1)"
[[ "$BEFORE" == "$AFTER" ]] || fail "a rebuild of the same log produced a different digest"

echo "PASS: agent-memory service"
