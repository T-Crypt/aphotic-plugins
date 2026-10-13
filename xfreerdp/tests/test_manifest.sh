#!/usr/bin/env bash
# The manifest, the catalogue entry and the static rules over the QML.
#
# What this can prove without a shell and without a compositor: that the
# manifest says what the code does, that the combo and the action id agree
# (the local half of the shell's keybind contract -- a rename breaks here
# first), that nothing password-shaped is stored anywhere, that the pane
# follows the repo's QML rules, and that the catalogue entry is current.
# What it cannot prove is that the shell binds the combo: that half lives in
# Aphotic-Hypr and only runs on a live desktop.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN="$ROOT/xfreerdp"
MANIFEST="$PLUGIN/plugin.toml"
QML="$PLUGIN/qml"

[[ -f "$MANIFEST" ]] || fail "manifest missing"

# ------------------------------------------------------------- manifest

python3 - "$MANIFEST" <<'PY' || exit 1
import sys, tomllib

doc = tomllib.load(open(sys.argv[1], "rb"))
plugin = doc["plugin"]

def need(condition, message):
    if not condition:
        print(f"FAIL: {message}")
        sys.exit(1)

for key in ("name", "display_name", "description", "version", "author", "category", "capabilities"):
    need(plugin.get(key), f"[plugin] is missing {key}")
need(plugin["name"] == "xfreerdp", "[plugin].name must match the directory name")
need(plugin["category"] == "productivity", "[plugin].category is not productivity")
for cap in ("ui-surface", "action", "cli", "keybind"):
    need(cap in plugin["capabilities"], f"capabilities is missing {cap}")

# packages REPLACES the list core derives from binaries, so both names have
# to be there: freerdp the package, xfreerdp3 the binary, zenity the helper.
requires = doc["requires"]
need(requires["binaries"] == ["xfreerdp3", "zenity"], "[requires].binaries must name xfreerdp3 and zenity")
need(requires["packages"] == ["freerdp", "zenity"], "[requires].packages must name both packages")

pane = doc["ui"]["settings_pane"]
need(pane["parent"] == "network", "the settings pane must dock under network")
need(pane["component"] == "qml/RdpPane.qml", "the settings pane component moved")
need("requires_layer" not in pane and "requires_data" not in pane,
     "the pane is gated on something: an RDP client reads nothing a layer installs")

# A top level command: a subcommand only resolves against a core
# cmd_xfreerdp.sh, and no core file names a plugin.
cli = doc["cli"]
need(cli["command"] == "xfreerdp", "[cli].command must be xfreerdp")
need("subcommand" not in cli or cli["subcommand"] == "",
     "[cli].subcommand cannot resolve: nothing in core provides an xfreerdp command")
need(cli["script"] == "cli/rdp.sh", "[cli].script moved")
need(cli["summary"].strip(), "[cli].summary is empty")

action = doc["action"]
keybind = doc["keybind"]
need(keybind.get("combo"), "[keybind].combo is missing")
need(keybind.get("action"), "[keybind].action is missing")
need(keybind.get("description", "").strip(), "[keybind].description is missing")
need(keybind["action"] == action["id"],
     f"[keybind].action '{keybind['action']}' is not an action this manifest declares ('{action['id']}')")

combo = keybind["combo"]
need(combo == combo.upper(), "[keybind].combo must be the canonical upper-case form")
allowed = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+ ")
need(set(combo) <= allowed, "[keybind].combo carries a character outside MODS + KEY")
need(" + " in combo, "[keybind].combo must separate its tokens with ' + '")
need(len(combo.split(" + ")) >= 2, "[keybind].combo needs a modifier and a key")

# The bind is the shell's to register; the plugin's own settings file has no
# say in it, and a second source of truth is the bug this checks for.
need("keybind" not in doc.get("owns", {}), "[owns] must not carry a keybind")

# Nothing password-shaped is ever declared, in this section or any other.
import re
for section, values in doc.items():
    if not isinstance(values, dict):
        continue
    for key, value in values.items():
        if not isinstance(value, str):
            continue
        if re.search(r"pass(word)?|secret|token|keyring|credential", f"{key} {value}", re.I):
            print(f"FAIL: [{section}].{key} looks like stored credential material")
            sys.exit(1)
PY

# --------------------------------------------------------------- files

[[ -f "$PLUGIN/cli/rdp.sh" ]] || fail "cli/rdp.sh missing"
[[ -f "$PLUGIN/bin/rdp-askpass" ]] || fail "bin/rdp-askpass missing"
[[ -f "$PLUGIN/qml/RdpSettings.qml" ]] || fail "qml/RdpSettings.qml missing"
[[ -f "$PLUGIN/qml/RdpPane.qml" ]] || fail "qml/RdpPane.qml missing"
[[ -f "$PLUGIN/qml/actions/Connect.qml" ]] || fail "qml/actions/Connect.qml missing"
[[ -f "$PLUGIN/qml/actions/Disconnect.qml" ]] || fail "qml/actions/Disconnect.qml missing"
[[ -f "$PLUGIN/README.md" ]] || fail "README.md missing"

# Install copies the tree and chmods hooks/ only, so an executable bit
# anywhere else has to be committed. The git mode is the one that survives
# the copy; the filesystem check still runs untracked, which is what makes
# this usable before the first commit.
for f in xfreerdp/cli/rdp.sh xfreerdp/bin/rdp-askpass; do
    [[ -x "$ROOT/$f" ]] || fail "$f is not executable"
    if git -C "$ROOT" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
        [[ "$(git -C "$ROOT" ls-files -s -- "$f" | awk '{print $1}')" == "100755" ]] \
            || fail "$f is committed without the executable bit"
    fi
done

# Sourced, never executed: core sources this in a subshell, so an `exit`
# would take the dispatcher's subshell with it.
grep -qE '\bexit\b' "$PLUGIN/cli/rdp.sh" && fail "cli/rdp.sh must use return, not exit"
grep -qE '\breturn\b' "$PLUGIN/cli/rdp.sh" || fail "cli/rdp.sh never returns"

# The password is asked for, never carried on the command line where `ps`
# would show it.
grep -qF '/p:' "$PLUGIN/cli/rdp.sh" && fail "cli/rdp.sh passes a password argument"
grep -qF 'FREERDP_ASKPASS' "$PLUGIN/cli/rdp.sh" || fail "cli/rdp.sh does not point FreeRDP at the askpass helper"
grep -qF 'zenity --password' "$PLUGIN/bin/rdp-askpass" || fail "bin/rdp-askpass no longer prompts through zenity"

# ------------------------------------------------------------- qmldir

[[ -f "$QML/qmldir" ]] || fail "qml/qmldir missing"
grep -qE '^module qs\.modules\.plugins\.xfreerdp$' "$QML/qmldir" || fail "the module path changed"
grep -qE '^singleton RdpSettings ' "$QML/qmldir" || fail "RdpSettings is not exported as a singleton"
grep -qE '^RdpPane ' "$QML/qmldir" || fail "RdpPane is not exported"

# --------------------------------------------------------- QML rules

if grep -rnE '\bTimer\b' "$QML" --include='*.qml'; then
    fail "no Timer may exist in the plugin: the status line follows compositor events"
fi

if grep -rnE '#[0-9A-Fa-f]{6,8}|Qt\.rgba\(' "$QML" --include='*.qml'; then
    fail "hardcoded colour found; resolve it through Colours.palette"
fi

grep -q 'Tokens\.' "$QML/RdpPane.qml" || fail "the pane does not use Tokens"
grep -q 'Colours\.palette' "$QML/RdpPane.qml" || fail "the pane's colours must resolve through Colours.palette"
grep -q 'pragma Singleton' "$QML/RdpPane.qml" && fail "the pane must not be a singleton: its host instantiates it"
grep -q 'RdpSettings' "$QML/RdpPane.qml" || fail "the pane never references RdpSettings; the singleton would never construct"
grep -qE '^[[:space:]]*Connections[[:space:]]*\{' "$QML/RdpPane.qml" || fail "the pane does not follow the compositor's window events"
grep -q 'onRawEvent' "$QML/RdpPane.qml" || fail "the pane's status line is not event driven"

# The singleton is the one place the schema exists, and it stays free of
# qs.* so tests/test_rdp_settings.sh can load it alone offscreen.
grep -q 'pragma Singleton' "$QML/RdpSettings.qml" || fail "RdpSettings must be a singleton"
if grep -nE '^import qs\.' "$QML/RdpSettings.qml"; then
    fail "RdpSettings imports qs.*; that is what makes it unprobeable offscreen"
fi

# The settings schema carries no keybind: the combo lives in the manifest
# only, and a key here would be a source of truth nothing reads.
python3 - "$QML/RdpSettings.qml" <<'PY' || exit 1
import re, sys

text = open(sys.argv[1]).read()
match = re.search(r"readonly property var defaultSettings: \(\{.*?\n    \}\)", text, re.S)
if not match:
    print("FAIL: the settings schema could not be found in RdpSettings.qml")
    sys.exit(1)
if "keybind" in match.group(0):
    print("FAIL: the settings schema carries a keybind field")
    sys.exit(1)
for key in ("host", "port", "user", "sec", "cert", "mic", "speaker", "camera", "resolution", "window", "extra"):
    if not re.search(rf"^\s+{key}: ", match.group(0), re.M):
        print(f"FAIL: the settings schema is missing {key}")
        sys.exit(1)
PY

# The two actions are headless and reach the session through the CLI, so
# there is one place that decides whether to focus or launch.
for action in Connect Disconnect; do
    grep -qE '^QtObject \{' "$QML/actions/$action.qml" || fail "$action.qml must be a headless QtObject"
    grep -q 'Component.onCompleted: Quickshell.execDetached(\["aphotic", "xfreerdp",' "$QML/actions/$action.qml" \
        || fail "$action.qml must run the plugin's own CLI"
done
grep -q '"connect"' "$QML/actions/Connect.qml" || fail "Connect.qml does not run the connect verb"
grep -q '"disconnect"' "$QML/actions/Disconnect.qml" || fail "Disconnect.qml does not run the disconnect verb"

# ------------------------------------------------- fixtures and secrets

[[ -f "$PLUGIN/tests/fixtures/settings.json" ]] || fail "the CLI fixture is missing"
grep -q '192\.0\.2\.10' "$PLUGIN/tests/fixtures/settings.json" || fail "the fixture must use the RFC 5737 documentation address"

# This file names the patterns it looks for, so it excludes itself.
if grep -rnE --exclude='test_manifest.sh' '10\.0\.0\.132|TrevinTindall|AzureAD|Corsair|work-laptop' "$PLUGIN"; then
    fail "a real host or account name is in the plugin"
fi

if grep -rniE '"(password|passwd|pass|secret|token|api_key)"' "$PLUGIN/tests/fixtures/"; then
    fail "a fixture carries credential material"
fi

# -------------------------------------------------------- the catalogue

python3 "$ROOT/tools/build_index.py" --check

python3 - "$ROOT/index.json" <<'PY' || exit 1
import json, sys

data = json.load(open(sys.argv[1]))
entry = next((p for p in data["plugins"] if p["name"] == "xfreerdp"), None)
if entry is None:
    print("FAIL: xfreerdp is missing from index.json")
    sys.exit(1)
if "keybind" not in entry["capabilities"]:
    print("FAIL: the index entry does not carry the keybind capability")
    sys.exit(1)
surfaces = {s["surface"] for s in entry.get("ui", {}).get("surfaces", [])}
if "settings" not in surfaces:
    print(f"FAIL: the index entry's surfaces are incomplete: {surfaces}")
    sys.exit(1)
if entry.get("category") != "productivity":
    print("FAIL: the index entry's category changed")
    sys.exit(1)
PY

grep -q 'xfreerdp/' "$ROOT/README.md" || fail "the root README does not list xfreerdp"
grep -qF '[keybind]' "$ROOT/WRITING-PLUGINS.md" || fail "WRITING-PLUGINS.md does not document the [keybind] block"

# --------------------------------------------------- optional install smoke

# Off unless asked, and it refuses to run when anything it needs is absent
# so it can never turn into an accidental package install.
#
# APHOTIC_PLUGINS_REPO has to be a real checkout, one where .git is a
# directory: the CLI decides to clone rather than read when it is not (a
# linked worktree has .git as a file). XFREERDP_TEST_REPO points the smoke
# at another copy of this tree without changing what it defaults to.
if [[ "${XFREERDP_TEST_INSTALL:-}" == "1" ]]; then
    for bin in aphotic xfreerdp3 zenity; do
        command -v "$bin" >/dev/null 2>&1 || fail "XFREERDP_TEST_INSTALL=1 but $bin is not installed"
    done

    REPO_SRC="${XFREERDP_TEST_REPO:-$ROOT}"
    [[ -d "${REPO_SRC}/.git" ]] || fail "${REPO_SRC} is not a checkout the CLI will read (a linked worktree has .git as a file)"

    T="$(mktemp -d)"
    trap 'rm -rf "$T"' EXIT
    XDG_DATA_HOME="$T/data" XDG_CONFIG_HOME="$T/config" XDG_STATE_HOME="$T/state" \
        APHOTIC_PLUGINS_REPO="$REPO_SRC" \
        aphotic plugin install xfreerdp --link || fail "the plugin did not install"

    # The module link is what makes `qs.modules.plugins.xfreerdp`
    # resolvable in the running shell; it lives under the shell's own
    # config dir, not the data dir the plugin is copied into.
    MODULE="$T/config/quickshell/aphotic/modules/plugins/xfreerdp"
    [[ -e "$MODULE" ]] || fail "install did not link the QML module"
    [[ -f "$MODULE/qmldir" ]] || fail "the linked module has no qmldir"

    REGISTRY="$T/state/aphotic/plugins.json"
    jq -e '.installed | has("xfreerdp")' "$REGISTRY" >/dev/null || fail "install did not write the registry entry"
    jq -e '.installed.xfreerdp.display_name == "Remote Desktop (xfreerdp)"' "$REGISTRY" >/dev/null \
        || fail "the registry entry lost its display name"
    jq -e '.installed.xfreerdp | .capabilities | index("keybind") != null' "$REGISTRY" >/dev/null \
        || fail "the registry entry lost the keybind capability"
    jq -e '.installed.xfreerdp.ui.surfaces[] | select(.surface == "settings") | .parent == "network"' "$REGISTRY" >/dev/null \
        || fail "the registry entry lost the settings surface"

    # A shell that hosts the capability records the bind with it; this one
    # does not yet, and the install says so rather than refusing.
    if jq -e '.installed.xfreerdp | has("keybinds")' "$REGISTRY" >/dev/null 2>&1; then
        jq -e '.installed.xfreerdp.keybinds[0].action == "connect"' "$REGISTRY" >/dev/null \
            || fail "the registry entry's keybind does not name the connect action"
    else
        echo "note: this Aphotic has no host for the keybind capability, so the registry has no keybinds entry"
    fi

    # The command the manifest declares has to resolve through the real
    # dispatcher, sourced exactly as core sources it.
    mkdir -p "$T/config/aphotic/plugins/xfreerdp"
    cp "$PLUGIN/tests/fixtures/settings.json" "$T/config/aphotic/plugins/xfreerdp/settings.json"
    ARGV="$(XDG_DATA_HOME="$T/data" XDG_CONFIG_HOME="$T/config" XDG_STATE_HOME="$T/state" \
        aphotic xfreerdp connect --dry-run)" || fail "the installed command did not resolve"
    grep -qx -- '-v:192.0.2.10:3389' <<<"$ARGV" || fail "the installed command built an unexpected argv"
    grep -qx -- '-grab-keyboard' <<<"$ARGV" || fail "the installed command lost -grab-keyboard"
fi

echo "PASS: xfreerdp manifest, catalogue and QML rules"
