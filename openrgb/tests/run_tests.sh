#!/usr/bin/env bash
# Offline test for the OpenRGB Sync plugin: runs the real hook entry point
# against tests/stub/, a stand-in for openrgb-python (see its docstring for
# the hardware shapes it models). No OpenRGB, no SDK server, no RGB hardware.
#
# What it is actually for: the mode-resolution rules in rgb_common.py encode
# lessons learned against one specific rig, and the whole point of the port
# was to re-derive them at runtime for hardware nobody here has. This pins
# the resolutions the original hardcoded, so a future change to the
# preference lists can't silently undo one of them.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export PYTHONPATH="$here/stub"
export OPENRGB_PLUGIN_CONFIG_DIR="$work/config"
export OPENRGB_PLUGIN_STATE_DIR="$work/state"
mkdir -p "$OPENRGB_PLUGIN_CONFIG_DIR" "$OPENRGB_PLUGIN_STATE_DIR"

rgb_sync="$here/../scripts/rgb_sync.py"
hooks="$here/../hooks"
log="$OPENRGB_PLUGIN_STATE_DIR/sync.log"
failures=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    echo "  ok   - $label"
  else
    echo "  FAIL - $label"
    echo "         expected to contain: $expected"
    echo "         got:                 $actual"
    failures=$((failures + 1))
  fi
}

echo "== mode resolution (each of these was a hardcoded per-device entry upstream) =="
inventory="$(python3 "$rgb_sync" devices)"
check "GPU with only Direct falls back to it for breathing too" \
  "static -> Direct, breathing -> Direct" "$(grep -A1 'RTX 4090' <<<"$inventory" | tail -1)"
check "motherboard uses its real Static/Breathing" \
  "static -> Static, breathing -> Breathing" "$(grep -A1 'Z790' <<<"$inventory" | tail -1)"
check "multi-zone hub prefers its PER_LED Custom over a MODE_SPECIFIC Static" \
  "static -> Custom, breathing -> Custom" "$(grep -A1 'SL Infinity' <<<"$inventory" | tail -1)"
check "DRAM with no PER_LED breathing uses MODE_SPECIFIC Color Pulse" \
  "static -> Direct, breathing -> Color Pulse" "$(grep -A1 'Vengeance' <<<"$inventory" | tail -1)"

echo "== theme hook =="
echo '{"background":"#101014","foreground":"#c8ccd4","colors":{"color4":"#7aa2f7"}}' | "$hooks/on_theme_change.sh"
check "applies the palette's color4, static" "theme: static #7aa2f7" "$(tail -n +1 "$log")"
check "one failing device does not block the rest" "4/5 devices OK" "$(tail -n +1 "$log")"
check "the failure is logged, not swallowed" "ERROR - Flaky HID Controller" "$(tail -n +1 "$log")"

echo "== gaming profile =="
"$hooks/on_profile_activate.sh" gaming
check "same hue, saturated" "profile gaming activate: static #0052ff" "$(tail -2 "$log")"
"$hooks/on_profile_activate.sh" security
check "an unwatched profile id writes nothing new" \
  "profile gaming activate" "$(tail -2 "$log")"

echo "== agent events =="
echo '{"sessionId":"s1","event":"session_start","harness":"claude"}' | "$hooks/on_agent_event.sh"
check "gaming outranks an agent session" "agent active: already static #0052ff" "$(tail -1 "$log")"
"$hooks/on_profile_deactivate.sh" gaming
check "leaving gaming with an agent live breathes, forced" \
  "profile gaming deactivate: breathing #7aa2f7" "$(tail -2 "$log")"
echo '{"sessionId":"s2","event":"session_start","harness":"claude"}' | "$hooks/on_agent_event.sh"
echo '{"sessionId":"s1","event":"stop","harness":"claude"}' | "$hooks/on_agent_event.sh"
check "one of two sessions stopping changes nothing" \
  "profile gaming deactivate" "$(tail -2 "$log" | head -1)"
echo '{"sessionId":"s2","event":"stop","harness":"claude"}' | "$hooks/on_agent_event.sh"
check "the last session stopping reverts to static, forced" \
  "agent idle: static #7aa2f7" "$(tail -2 "$log")"

echo "== failure posture =="
FAKE_REFUSE=1 "$hooks/on_theme_change.sh" <<<'{"colors":{"color4":"#7aa2f7"}}'
check "a refused connection is logged, not swallowed" \
  "SDK server refused the connection" "$(tail -1 "$log")"
FAKE_NO_DEVICES=1 python3 "$rgb_sync" apply || true
check "zero devices is called out" "reports zero devices" "$(tail -1 "$log")"
check "and nudges toward setup once" "setup.sh" \
  "$(cat "$OPENRGB_PLUGIN_STATE_DIR/notified-udev" 2>/dev/null || echo MISSING)"

echo
if [[ "$failures" -eq 0 ]]; then
  echo "All checks passed."
else
  echo "$failures check(s) failed."
  exit 1
fi
