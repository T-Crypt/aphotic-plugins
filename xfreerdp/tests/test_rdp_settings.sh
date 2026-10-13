#!/usr/bin/env bash
# The pane's state holder, driven headlessly.
#
# The pane itself cannot be instantiated by a bare `qs -p` probe: it imports
# qs.config and qs.components, whose `qs` prefix maps to the installed
# shell's own directory, and pulling the shell's service graph up offscreen
# dies inside the notification history. So the check is the repo's own
# working pattern instead (llm-fit/tests/test_llmfit_service.sh): one
# headless singleton, probed on its own, offscreen, under a throwaway HOME.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$ROOT/xfreerdp/tests/RdpSettingsProbe.qml"
FIXTURE="$ROOT/xfreerdp/tests/fixtures/settings.json"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/imports/qs/modules/plugins" \
         "$TEST_ROOT/home" "$TEST_ROOT/config" "$TEST_ROOT/data" \
         "$TEST_ROOT/state" "$TEST_ROOT/runtime"
ln -s "$ROOT/xfreerdp/qml" "$TEST_ROOT/imports/qs/modules/plugins/xfreerdp"

SETTINGS="$TEST_ROOT/config/aphotic/plugins/xfreerdp/settings.json"
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

# ------------------------------------------------------- the shipped defaults

rm -rf "$TEST_ROOT/config/aphotic"
OUTPUT="$(XFREERDP_TEST_CASE=defaults run_probe 2>&1)"
expect "$OUTPUT" \
    "the settings read resolved" \
    "the default window class is work-rdp" \
    "the default security is NLA" \
    "the default resolution mode is dynamic" \
    "the settings schema carries no keybind key" \
    "no keybind key is resolved into the settings"
[[ -f "$SETTINGS" ]] && fail "merely reading the settings must not create the file"

# ---------------------------------------- a partial profile merges over them

# Derived from the shipped fixture, so the values the CLI test asserts are
# the same ones this reads, and the file is a partial one on purpose: it
# names three keys and has to leave every other default standing.
mkdir -p "$(dirname "$SETTINGS")"
jq '{host, user, window: {workspace: "3"}}' "$FIXTURE" > "$SETTINGS"
jq -e '.host == "192.0.2.10" and .user == "EXAMPLE\\user"' "$SETTINGS" >/dev/null \
    || fail "the fixture no longer carries the neutral profile"

OUTPUT="$(XFREERDP_TEST_CASE=merge run_probe 2>&1)"
expect "$OUTPUT" \
    "the settings read resolved" \
    "the profile's host is read" \
    "the profile's user is read as typed" \
    "the profile's workspace pin is read" \
    "a partial window block keeps the default class" \
    "a partial window block keeps the default gfx" \
    "an absent resolution block keeps its defaults" \
    "an absent port keeps the default" \
    "set() updates the host in memory" \
    "the settings file round-trips through JSON" \
    "the host edit reached the file" \
    "the write kept the value the file already had" \
    "the write kept the defaults" \
    "the write introduced no keybind key"

# The file really is on disk, as a whole document, with the edit in it.
[[ -f "$SETTINGS" ]] || fail "set() did not create the settings file"
jq -e '.host == "192.0.2.20"' "$SETTINGS" >/dev/null || fail "the file does not hold the edit"
jq -e '.window.workspace == "3" and .window.class == "work-rdp"' "$SETTINGS" >/dev/null \
    || fail "the write lost a value that was already in the file"
jq -e '.resolution.width == 1920 and .resolution.height == 1080' "$SETTINGS" >/dev/null \
    || fail "the write lost a default"
jq -e 'has("keybind") | not' "$SETTINGS" >/dev/null || fail "the write introduced a keybind key"

# ------------------------------------------------------------- the status read

cat > "$TEST_ROOT/bin/aphotic" <<'STUB'
#!/usr/bin/env bash
echo running
STUB
chmod +x "$TEST_ROOT/bin/aphotic"

OUTPUT="$(XFREERDP_TEST_CASE=status XFREERDP_TEST_EXPECT=running run_probe 2>&1)"
expect "$OUTPUT" \
    "the status read answered" \
    "a running session is reported as running"

rm -f "$TEST_ROOT/bin/aphotic"
OUTPUT="$(XFREERDP_TEST_CASE=status XFREERDP_TEST_EXPECT=unknown run_probe 2>&1)"
expect "$OUTPUT" \
    "no aphotic answers nothing, not an error" \
    "an unanswerable status is not reported as running"

# A CLI that answers something the plugin does not understand is unknown
# too, not a wrong answer.
cat > "$TEST_ROOT/bin/aphotic" <<'STUB'
#!/usr/bin/env bash
printf 'some other thing\n'
exit 0
STUB
chmod +x "$TEST_ROOT/bin/aphotic"
OUTPUT="$(XFREERDP_TEST_CASE=status XFREERDP_TEST_EXPECT=unknown run_probe 2>&1)"
expect "$OUTPUT" "no aphotic answers nothing, not an error"

# A CLI that fails is unknown as well.
cat > "$TEST_ROOT/bin/aphotic" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$TEST_ROOT/bin/aphotic"
OUTPUT="$(XFREERDP_TEST_CASE=status XFREERDP_TEST_EXPECT=unknown run_probe 2>&1)"
expect "$OUTPUT" "an unanswerable status is not reported as running"

echo "PASS: xfreerdp settings"
