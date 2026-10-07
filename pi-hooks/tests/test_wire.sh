#!/usr/bin/env bash
# pi-hooks/hooks/wire.sh + unwire.sh round trip.
#
# The invariants this guards: one symlink per installed harness, each in
# that harness's own discovery dir; the writer path recorded in the
# shell's state dir (never beside the symlink); a harness that is absent
# or too old is skipped without aborting the other; neither present is a
# refusal, not a silent no-op; and disable removes every trace so a
# re-enable wires exactly one copy per harness.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WIRE="$ROOT/hooks/wire.sh"
UNWIRE="$ROOT/hooks/unwire.sh"

command -v jq >/dev/null 2>&1 || { echo "jq not found; skipping" >&2; exit 0; }

# A HOME and state dir of our own, so this never touches the real config.
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX"
export XDG_STATE_HOME="$SANDBOX/state"
PI_DEST="$HOME/.pi/agent/extensions"
OMP_DEST="$HOME/.omp/agent/hooks/pre"
LINK_NAME="aphotic_pi_hook.js"
CONFIG="$XDG_STATE_HOME/aphotic/pi-hook.json"

mkdir -p "$SANDBOX/bin"

# Harness stand-ins: wire.sh only ever asks for `--version`.
fake_harness() { # $1 = name, $2 = version line
    rm -f "$SANDBOX/bin/$1"
    printf '#!/usr/bin/env bash\necho %s\n' "$2" > "$SANDBOX/bin/$1"
    chmod +x "$SANDBOX/bin/$1"
}
drop_harness() { rm -f "$SANDBOX/bin/$1"; }
# Only sandbox and system tool dirs: this box's real pi/omp live in
# ~/.local/bin and must not be visible to wire.sh's `command -v`.
export PATH="$SANDBOX/bin:/usr/bin:/bin"

fake_harness pi "pi 1.0.0"
fake_harness omp "omp v18.5.1"

bash "$WIRE" /opt/lib/aphotic

[[ -L "$PI_DEST/$LINK_NAME" ]] || fail "enable did not symlink into pi's discovery dir"
# OMP's discovery scan ignores symlinks, so it gets a re-export shim: a
# regular file whose one import names the plugin's adapter.
[[ -f "$OMP_DEST/$LINK_NAME" && ! -L "$OMP_DEST/$LINK_NAME" ]] \
    || fail "enable did not write the shim into omp's discovery dir"
rg -q "export \{ default \} from \"$ROOT/hook/pi_omp_hook\.js\"" "$OMP_DEST/$LINK_NAME" \
    || fail "omp shim does not re-export the plugin adapter"
[[ -f "$CONFIG" ]] || fail "enable did not record the hook path in the state dir"
rg -q '"/opt/lib/aphotic/agent_hook\.py"' "$CONFIG" || fail "state config does not name agent_hook.py"

# Both install shapes load the one adapter file: the pi symlink resolves
# to it, the omp shim re-exports it.
[[ "$(readlink -f "$PI_DEST/$LINK_NAME")" == "$ROOT/hook/pi_omp_hook.js" ]] \
    || fail "pi link does not resolve to the plugin adapter"

# --- a too-old harness is unwired, the other still wires ----------------

drop_harness omp
fake_harness pi "pi 0.9.0"
bash "$WIRE" /opt/lib/aphotic
[[ ! -L "$PI_DEST/$LINK_NAME" ]] || fail "a below-floor pi kept its link"
[[ -e "$OMP_DEST/$LINK_NAME" ]] || fail "a below-floor pi aborted the omp wire"

fake_harness pi "pi 1.0.0"
fake_harness omp "omp v18.5.1"

# --- exactly one harness installed wires only that one -------------------

drop_harness omp
bash "$WIRE" /opt/lib/aphotic
[[ -L "$PI_DEST/$LINK_NAME" ]] || fail "a pi-only machine did not wire pi"
rm -f "$OMP_DEST/$LINK_NAME"

# --- neither installed is a refusal, not a silent no-op ------------------

drop_harness pi
if bash "$WIRE" /opt/lib/aphotic >/dev/null 2>&1; then
    fail "wire succeeded with neither pi nor omp installed"
fi

# --- disable removes every trace ----------------------------------------

fake_harness pi "pi 1.0.0"
fake_harness omp "omp v18.5.1"
bash "$WIRE" /opt/lib/aphotic
bash "$UNWIRE"

[[ ! -e "$PI_DEST/$LINK_NAME" ]] || fail "disable left the pi symlink"
[[ ! -e "$OMP_DEST/$LINK_NAME" ]] || fail "disable left the omp symlink"
[[ ! -e "$CONFIG" ]] || fail "disable left the state config behind"

# --- disable is safe when nothing is wired ------------------------------

bash "$UNWIRE"

# --- the manifest declares what it writes -------------------------------

rg -q 'pi-hook\.json' "$ROOT/plugin.toml" \
    || fail "[owns] does not declare the state config"
rg -q 'hooks/wire\.sh' "$ROOT/plugin.toml" \
    || fail "[harness] does not declare the wire script"
rg -q 'hooks/unwire\.sh' "$ROOT/plugin.toml" \
    || fail "[harness] does not declare the unwire script"

echo "ok: wire/unwire round trip"
