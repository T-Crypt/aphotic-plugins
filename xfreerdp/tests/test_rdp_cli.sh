#!/usr/bin/env bash
# The argv `aphotic xfreerdp` builds, and the three things it does with it:
# focus an existing window, launch a detached session, or answer whether one
# is up.
#
# Everything the script touches is stubbed into a temp tree: HOME and the
# XDG paths point at it, `hyprctl` and `setsid` record their arguments
# instead of doing anything, and `xfreerdp3` never runs at all. So this
# proves the decision logic (flags, toggle, pin, status) without a compositor
# and without a Windows host, and it is why the same script can run in a
# container.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN="$ROOT/xfreerdp"
CLI="$PLUGIN/cli/rdp.sh"
FIXTURE="$PLUGIN/tests/fixtures/settings.json"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

# Absolute, because two cases run with a PATH that deliberately holds no
# hyprctl -- and therefore no bash either.
BASH_BIN="$(command -v bash)"

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/config/plugins/xfreerdp" "$TEST_ROOT/home" \
         "$TEST_ROOT/data" "$TEST_ROOT/state" "$TEST_ROOT/runtime" "$TEST_ROOT/emptybin"

# ---------------------------------------------------------------- stubs

cat > "$TEST_ROOT/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >> "$HYPRCTL_LOG"
if [[ "${1:-}" == "clients" ]]; then
    if [[ -f "$CLIENTS_RUNNING_MARKER" ]]; then
        printf '%s\n' "$CLIENTS_RUNNING_JSON"
    else
        printf '[]\n'
    fi
fi
exit 0
STUB

# Stands in for the real `setsid -f xfreerdp3 ...`: records the argv it was
# handed and the askpass path the session would have inherited, then marks
# the window as up so the pin and fullscreen waits have something to find.
cat > "$TEST_ROOT/bin/setsid" <<'STUB'
#!/usr/bin/env bash
{
    printf 'setsid'
    for arg in "$@"; do printf ' %s' "$arg"; done
    printf '\n'
    printf 'FREERDP_ASKPASS=%s\n' "${FREERDP_ASKPASS:-}"
} >> "$SETSID_LOG"
touch "$CLIENTS_RUNNING_MARKER"
exit 0
STUB

# Never runs (setsid is stubbed above); present so aphotic_require finds it.
cat > "$TEST_ROOT/bin/xfreerdp3" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$XFREERDP_LOG"
exit 0
STUB
chmod +x "$TEST_ROOT/bin/hyprctl" "$TEST_ROOT/bin/setsid" "$TEST_ROOT/bin/xfreerdp3"

# The helpers core sources before a plugin's [cli] script. Only the three the
# script uses, with the same warn-and-return contract core has.
cat > "$TEST_ROOT/helpers.sh" <<'HELPERS'
aphotic_err()  { printf '[fail] %s\n' "$*" >&2; }
aphotic_warn() { printf '[warn] %s\n' "$*" >&2; }
aphotic_log()  { printf '[aphotic] %s\n' "$*"; }
aphotic_require() {
    command -v "$1" >/dev/null 2>&1 || { aphotic_err "missing dependency: $1"; return 1; }
}
HELPERS

export HYPRCTL_LOG="$TEST_ROOT/hyprctl.log"
export SETSID_LOG="$TEST_ROOT/setsid.log"
export XFREERDP_LOG="$TEST_ROOT/xfreerdp.log"
export CLIENTS_RUNNING_MARKER="$TEST_ROOT/state/window-up"
export CLIENTS_RUNNING_JSON='[{"class":"work-rdp","title":"Remote Desktop"}]'
export HYPRLAND_INSTANCE_SIGNATURE="test-signature"

export HOME="$TEST_ROOT/home"
export XDG_CONFIG_HOME="$TEST_ROOT/config"
export XDG_DATA_HOME="$TEST_ROOT/data"
export XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
export APHOTIC_CONFIG_HOME="$TEST_ROOT/config"
export PATH="$TEST_ROOT/bin:$PATH"

# ----------------------------------------------------------------- driver

# A case is a subshell with core's own options, because that is how core
# sources a plugin's script (bin/aphotic runs under set -euo pipefail).
run_rdp() {
    (
        set -- "$@"
        # shellcheck source=/dev/null
        . "$TEST_ROOT/helpers.sh"
        # shellcheck source=/dev/null
        . "$CLI"
    )
}

reset_state() {
    rm -f "$HYPRCTL_LOG" "$SETSID_LOG" "$XFREERDP_LOG" "$CLIENTS_RUNNING_MARKER"
    : > "$HYPRCTL_LOG"
    : > "$SETSID_LOG"
}

# Installs a settings file (or removes the directory entirely) so each case
# starts from a known profile.
use_profile() {
    rm -rf "$TEST_ROOT/config/plugins/xfreerdp"
    mkdir -p "$TEST_ROOT/config/plugins/xfreerdp"
    if [[ -n "${1:-}" ]]; then
        cp "$1" "$TEST_ROOT/config/plugins/xfreerdp/settings.json"
    fi
}

# ------------------------------------------------------- argv, dry run

use_profile "$FIXTURE"
reset_state

out="$(run_rdp connect --dry-run 2>"$TEST_ROOT/err")" || fail "dry run exited non-zero: $(cat "$TEST_ROOT/err")"

expected="$(cat <<'ARGV'
-v:192.0.2.10:3389
/u:EXAMPLE\user
/sec:nla
/cert:ignore
/size:1920x1080
/dynamic-resolution
/dvc:rdpecam
/gfx:AVC420
/sound:sys:pulse,dev:alsa_output.test.analog-stereo
/microphone:sys:pulse,dev:alsa_input.test.mono-fallback
/wm-class:work-rdp
/auto-reconnect
-grab-keyboard
ARGV
)"

if [[ "$out" != "$expected" ]]; then
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$out") || true
    fail "the full profile did not build the baseline argv, in order"
fi

grep -q '/p:' <<<"$out" && fail "a password argument reached the argv"
[[ -s "$HYPRCTL_LOG" ]] && fail "a dry run must not call hyprctl"

# Mic off removes the /microphone: flag entirely; /size: stays, because the
# session still needs a starting geometry in both modes.
use_profile "$FIXTURE"
jq '.mic.enabled = false' "$FIXTURE" > "$TEST_ROOT/off.json"
use_profile "$TEST_ROOT/off.json"
out="$(run_rdp connect --dry-run)" || fail "dry run with the mic off exited non-zero"
grep -q '^/microphone:' <<<"$out" && fail "a disabled microphone still produced a /microphone: flag"
grep -q '^/size:1920x1080$' <<<"$out" || fail "/size: must be passed in dynamic mode too"
grep -q '^/dynamic-resolution$' <<<"$out" || fail "/dynamic-resolution missing in dynamic mode"

# Fixed mode, camera off, empty device names, both optional flags off.
jq '.resolution.mode = "fixed"
  | .resolution.width = 2560 | .resolution.height = 1440
  | .camera.enabled = false
  | .mic.device = "" | .speaker.device = ""
  | .window.grab_keyboard = false | .window.auto_reconnect = false
  | .window.workspace = "3"' "$FIXTURE" > "$TEST_ROOT/fixed.json"
use_profile "$TEST_ROOT/fixed.json"
out="$(run_rdp connect --dry-run)" || fail "dry run in fixed mode exited non-zero"
grep -q '^/size:2560x1440$' <<<"$out" || fail "the initial /size: did not follow the profile"
grep -q '^/dynamic-resolution$' <<<"$out" && fail "/dynamic-resolution must not be passed in fixed mode"
grep -q '^/dvc:rdpecam$' <<<"$out" && fail "a disabled camera still requested the rdpecam channel"
grep -q '^/sound:sys:pulse$' <<<"$out" || fail "an empty speaker device must fall back to bare sys:pulse"
grep -q '^/microphone:sys:pulse$' <<<"$out" || fail "an empty mic device must fall back to bare sys:pulse"
grep -q '^/auto-reconnect$' <<<"$out" && fail "auto-reconnect was off and still passed"
grep -q '^-grab-keyboard$' <<<"$out" && fail "grab-keyboard was off and still passed"

# A free-form tail is split into its own words, not re-expanded as one.
jq '.extra = "/f /bpp:16"' "$FIXTURE" > "$TEST_ROOT/extra.json"
use_profile "$TEST_ROOT/extra.json"
out="$(run_rdp connect --dry-run)" || fail "dry run with extra args exited non-zero"
[[ "$(tail -2 <<<"$out")" == "/f
/bpp:16" ]] || fail "the extra tail was not split into separate arguments"

# ------------------------------------------------ argv, refused profiles

jq '.host = ""' "$FIXTURE" > "$TEST_ROOT/nohost.json"
use_profile "$TEST_ROOT/nohost.json"
rc=0
out="$(run_rdp connect 2>"$TEST_ROOT/err")" || rc=$?
[[ "$rc" -eq 1 ]] || fail "an empty host must fail, got exit ${rc}"
[[ -z "$out" ]] || fail "an empty host still printed an argv"
grep -q 'Settings > Network > Remote Desktop' "$TEST_ROOT/err" || fail "the empty-host error does not name the pane"
[[ -s "$SETSID_LOG" ]] && fail "an empty host still launched a session"

use_profile ""
rc=0
out="$(run_rdp connect 2>"$TEST_ROOT/err")" || rc=$?
[[ "$rc" -eq 1 ]] || fail "a missing settings file must fail, got exit ${rc}"
[[ -z "$out" ]] || fail "a missing settings file still printed an argv"
grep -q 'Settings > Network > Remote Desktop' "$TEST_ROOT/err" || fail "the missing-profile error does not name the pane"

use_profile "$FIXTURE"
printf '{"host": "192.0.2.10"' > "$TEST_ROOT/config/plugins/xfreerdp/settings.json"
rc=0
out="$(run_rdp connect 2>"$TEST_ROOT/err")" || rc=$?
[[ "$rc" -eq 1 ]] || fail "a truncated settings file must fail, got exit ${rc}"
[[ -z "$out" ]] || fail "a truncated settings file still printed an argv"
grep -q 'settings.json' "$TEST_ROOT/err" || fail "the corrupt-file error does not name the file"
[[ -s "$SETSID_LOG" ]] && fail "a corrupt profile still launched a session"

# Valid JSON of the wrong shape (an array where an object belongs) makes jq
# itself fail, which used to end in the same bash crash as a newline.
use_profile "$FIXTURE"
printf '{"mic":[]}' > "$TEST_ROOT/config/plugins/xfreerdp/settings.json"
rc=0
out="$(run_rdp connect --dry-run 2>"$TEST_ROOT/err")" || rc=$?
[[ "$rc" -eq 1 ]] || fail "a wrongly shaped settings file must fail, got exit ${rc}"
[[ -z "$out" ]] || fail "a wrongly shaped settings file still printed an argv"
grep -q 'settings.json' "$TEST_ROOT/err" || fail "the wrongly shaped file error does not name the file"
grep -q 'unbound variable' "$TEST_ROOT/err" && fail "a wrongly shaped file still reaches bash as an unbound variable"

# ------------------------------------------ values a shell cannot carry

# A newline in a value is reachable from the pane (a single-line TextInput
# still keeps one through paste, and setHost trims only the ends). It used
# to cut the record short and abort the CLI with `f[1]: unbound variable`:
# a raw bash error, no message, nothing run. It has to come back as a
# refusal that names the setting.
jq '.host = "good.example\nBAD.example"' "$FIXTURE" > "$TEST_ROOT/newline-host.json"
use_profile "$TEST_ROOT/newline-host.json"
rc=0
out="$(run_rdp connect --dry-run 2>"$TEST_ROOT/err")" || rc=$?
[[ "$rc" -eq 1 ]] || fail "a newline in the host must be refused, got exit ${rc}"
[[ -z "$out" ]] || fail "a newline in the host still printed an argv"
grep -q "'host'" "$TEST_ROOT/err" || fail "the newline refusal does not name the host setting"
grep -q 'line break' "$TEST_ROOT/err" || fail "the newline refusal does not say what is wrong"
grep -q 'unbound variable' "$TEST_ROOT/err" && fail "a newline still reaches bash as an unbound variable"

# The same value in extra used to drop every flag after the newline without
# a word about it.
jq '.extra = "/f\n/bpp:16"' "$FIXTURE" > "$TEST_ROOT/newline-extra.json"
use_profile "$TEST_ROOT/newline-extra.json"
rc=0
out="$(run_rdp connect --dry-run 2>"$TEST_ROOT/err")" || rc=$?
[[ "$rc" -eq 1 ]] || fail "a newline in extra must be refused, got exit ${rc}"
[[ -z "$out" ]] || fail "a newline in extra still printed an argv"
grep -q "'extra'" "$TEST_ROOT/err" || fail "the newline refusal does not name the extra setting"

# A NUL cannot travel in a bash variable at all, so a value holding one is
# refused as a damaged record rather than read as a shifted field list.
jq '.host = "a\u0000b"' "$FIXTURE" > "$TEST_ROOT/nul-host.json"
use_profile "$TEST_ROOT/nul-host.json"
rc=0
out="$(run_rdp connect --dry-run 2>"$TEST_ROOT/err")" || rc=$?
[[ "$rc" -eq 1 ]] || fail "a NUL in a value must be refused, got exit ${rc}"
[[ -z "$out" ]] || fail "a NUL in a value still printed an argv"
grep -q 'settings.json' "$TEST_ROOT/err" || fail "the damaged-record error does not name the file"
grep -q 'unbound variable' "$TEST_ROOT/err" && fail "a NUL still reaches bash as an unbound variable"

# --------------------------------------------------- password flags

# `extra` is passed as typed, so it is the one field a password could reach
# the argv through, where `ps` would show it. The README and the pane both
# say that cannot happen; the boundary refuses it instead. FreeRDP treats
# /p:, -p: and +p: as one flag, so all three are refused, along with the
# flags that carry a credential in the same argument.
while read -r flag; do
    jq --arg f "$flag" '.extra = ("/f " + $f)' "$FIXTURE" > "$TEST_ROOT/password.json"
    use_profile "$TEST_ROOT/password.json"
    reset_state
    rc=0
    out="$(run_rdp connect --dry-run 2>"$TEST_ROOT/err")" || rc=$?
    [[ "$rc" -eq 1 ]] || fail "'${flag}' in extra must be refused, got exit ${rc}"
    [[ -z "$out" ]] || fail "'${flag}' still printed an argv"
    grep -q "'extra'" "$TEST_ROOT/err" || fail "the refusal for '${flag}' does not name the extra setting"
    grep -q 'unbound variable' "$TEST_ROOT/err" && fail "'${flag}' still reaches bash as an unbound variable"
done <<'FLAGS'
/p:hunter2
-p:hunter2
+p:hunter2
/p
/pth:deadbeef
-assistance:hunter2
/gateway:g:host,u:u,p:hunter2
/proxy:http://user:hunter2@127.0.0.1:3128
FLAGS

# And the launch path refuses it too, not just the dry run.
jq '.extra = "/f /p:hunter2"' "$FIXTURE" > "$TEST_ROOT/password.json"
use_profile "$TEST_ROOT/password.json"
reset_state
rc=0
run_rdp connect 2>"$TEST_ROOT/err" || rc=$?
[[ "$rc" -eq 1 ]] || fail "a password flag must refuse the launch, got exit ${rc}"
[[ -s "$SETSID_LOG" ]] && fail "a password flag still launched a session"

# A gateway to a host whose port looks like the flag, and a proxy URL with a
# bare user, carry nothing and must still be passed through.
while read -r flag; do
    jq --arg f "$flag" '.extra = $f' "$FIXTURE" > "$TEST_ROOT/clearextra.json"
    use_profile "$TEST_ROOT/clearextra.json"
    out="$(run_rdp connect --dry-run 2>"$TEST_ROOT/err")" || fail "'${flag}' must not be refused: $(cat "$TEST_ROOT/err")"
    [[ "$(tail -1 <<<"$out")" == "$flag" ]] || fail "'${flag}' did not reach the argv as one argument"
done <<'FLAGS'
/gateway:g:rdp:443,u:u,d:domain
/proxy:http://127.0.0.1:3128
/prevent-session-lock
FLAGS

# ------------------------------------------------------------ toggle

use_profile "$FIXTURE"
reset_state
touch "$CLIENTS_RUNNING_MARKER"

out="$(run_rdp connect)" || fail "the toggle case exited non-zero"
[[ -z "$out" ]] || fail "focusing an existing session printed something"
[[ "$(grep -c '^hyprctl dispatch focuswindow class:\^(work-rdp)\$$' "$HYPRCTL_LOG")" -eq 1 ]] \
    || fail "expected exactly one focuswindow dispatch, got: $(cat "$HYPRCTL_LOG")"
grep -q 'closewindow\|movetoworkspacesilent\|fullscreen' "$HYPRCTL_LOG" \
    && fail "the toggle case dispatched more than focuswindow"
[[ -s "$SETSID_LOG" ]] && fail "the toggle case launched a second session"

# ------------------------------------------------------------ launch

reset_state
out="$(run_rdp connect)" || fail "the launch case exited non-zero"
grep -q '^setsid -f xfreerdp3 ' "$SETSID_LOG" || fail "no detached xfreerdp3 launch was recorded"
grep -q '/wm-class:work-rdp' "$SETSID_LOG" || fail "the launch argv lost /wm-class:work-rdp"
grep -q -- '-grab-keyboard' "$SETSID_LOG" || fail "the launch argv lost -grab-keyboard"
grep -q "^FREERDP_ASKPASS=$PLUGIN/bin/rdp-askpass\$" "$SETSID_LOG" \
    || fail "the launch did not export this plugin's askpass helper"

use_profile "$TEST_ROOT/fixed.json"
reset_state
run_rdp connect >/dev/null || fail "the pinned launch case exited non-zero"
grep -q '^hyprctl dispatch movetoworkspacesilent 3,class:\^(work-rdp)\$$' "$HYPRCTL_LOG" \
    || fail "workspace pinning did not dispatch, got: $(cat "$HYPRCTL_LOG")"

use_profile "$FIXTURE"
reset_state
run_rdp connect >/dev/null || fail "the default launch case exited non-zero"
grep -q 'movetoworkspacesilent\|fullscreen 0' "$HYPRCTL_LOG" \
    && fail "workspace = none and fullscreen = false must dispatch neither"

# The one dispatch path with no baseline to copy: fullscreen focuses the
# window first and then asks for fullscreen, in that order.
jq '.window.fullscreen = true | .window.workspace = "none"' "$FIXTURE" > "$TEST_ROOT/fullscreen.json"
use_profile "$TEST_ROOT/fullscreen.json"
reset_state
run_rdp connect >/dev/null || fail "the fullscreen launch case exited non-zero"
[[ "$(grep -c '^hyprctl dispatch' "$HYPRCTL_LOG")" -eq 2 ]] \
    || fail "fullscreen must dispatch exactly focuswindow then fullscreen, got: $(cat "$HYPRCTL_LOG")"
[[ "$(grep '^hyprctl dispatch' "$HYPRCTL_LOG" | sed -n '1p')" == 'hyprctl dispatch focuswindow class:^(work-rdp)$' ]] \
    || fail "fullscreen must focus the window first, got: $(cat "$HYPRCTL_LOG")"
[[ "$(grep '^hyprctl dispatch' "$HYPRCTL_LOG" | sed -n '2p')" == 'hyprctl dispatch fullscreen 0' ]] \
    || fail "fullscreen was not asked for after focusing, got: $(cat "$HYPRCTL_LOG")"

# ------------------------------------------------------------ status

use_profile "$FIXTURE"
reset_state
touch "$CLIENTS_RUNNING_MARKER"
[[ "$(run_rdp status)" == "running" ]] || fail "a matching window must report running"

reset_state
[[ "$(run_rdp status)" == "not-running" ]] || fail "no matching window must report not-running"

# Still running: the class is whatever the profile says.
jq '.window.class = "other-rdp"' "$FIXTURE" > "$TEST_ROOT/other.json"
use_profile "$TEST_ROOT/other.json"
reset_state
touch "$CLIENTS_RUNNING_MARKER"
[[ "$(run_rdp status)" == "not-running" ]] || fail "status must match the profile's own window class"

use_profile "$FIXTURE"
reset_state
rc=0
out="$(env -u HYPRLAND_INSTANCE_SIGNATURE "$BASH_BIN" -c "
    set -euo pipefail
    . '$TEST_ROOT/helpers.sh'
    . '$CLI' status
")" || rc=$?
[[ "$rc" -eq 0 ]] || fail "status must always exit 0, got ${rc}"
[[ "$out" == "unknown" ]] || fail "no compositor signature must read as unknown, got '${out}'"

rc=0
out="$(env PATH="$TEST_ROOT/emptybin" "$BASH_BIN" -c "
    set -euo pipefail
    . '$TEST_ROOT/helpers.sh'
    . '$CLI' status
")" || rc=$?
[[ "$rc" -eq 0 ]] || fail "status without hyprctl must exit 0, got ${rc}"
[[ "$out" == "unknown" ]] || fail "a missing hyprctl must read as unknown, got '${out}'"

# ------------------------------------------------------------ disconnect

use_profile "$FIXTURE"
reset_state
touch "$CLIENTS_RUNNING_MARKER"
run_rdp disconnect 2>"$TEST_ROOT/err" || fail "disconnect exited non-zero on a live session"
grep -q '^hyprctl dispatch closewindow class:\^(work-rdp)\$$' "$HYPRCTL_LOG" \
    || fail "disconnect did not close the session window, got: $(cat "$HYPRCTL_LOG")"

reset_state
rc=0
run_rdp disconnect 2>"$TEST_ROOT/err" || rc=$?
[[ "$rc" -eq 0 ]] || fail "disconnect with nothing open must still exit 0, got ${rc}"
grep -q '\[warn\]' "$TEST_ROOT/err" || fail "disconnect with nothing open must warn"

# ------------------------------------------------------------ usage

out="$(run_rdp 2>&1)" || fail "no arguments must print usage and exit 0"
grep -q 'connect' <<<"$out" || fail "usage does not list connect"
grep -q 'status' <<<"$out" || fail "usage does not list status"
grep -q 'disconnect' <<<"$out" || fail "usage does not list disconnect"

rc=0
out="$(run_rdp wibble 2>&1)" || rc=$?
[[ "$rc" -eq 1 ]] || fail "an unknown verb must fail, got ${rc}"
grep -q 'wibble' <<<"$out" || fail "the unknown-verb error does not name the verb"

echo "PASS: xfreerdp CLI"
