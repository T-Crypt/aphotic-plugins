#!/usr/bin/env bash
# The manifest, the catalogue entry and the static rules over the QML.
#
# What this can prove without a shell and without a compositor: that the
# manifest says what the code does, that the CLI verb is a top-level command
# (a subcommand only resolves against a core cmd_*.sh, and no core file
# names a plugin), that the workspace plane is gated the way every other
# agent surface is, that the plane follows the repo's QML rules, that the
# state holder stays probeable offscreen, and that the catalogue is current.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN="$ROOT/agent-memory"
MANIFEST="$PLUGIN/plugin.toml"
QML="$PLUGIN/qml"
SERVICE="$QML/MemoryService.qml"
PANE="$QML/MemoryWorkspace.qml"
QMLDIR="$QML/qmldir"

[[ -f "$MANIFEST" ]] || fail "manifest missing"

# ------------------------------------------------------------- manifest

python3 - "$MANIFEST" <<'PY' || exit 1
import re
import sys
import tomllib

doc = tomllib.load(open(sys.argv[1], "rb"))
plugin = doc["plugin"]


def need(condition, message):
    if not condition:
        print(f"FAIL: {message}")
        sys.exit(1)


for key in ("name", "display_name", "description", "version", "author", "category", "capabilities"):
    need(plugin.get(key), f"[plugin] is missing {key}")
need(plugin["name"] == "agent-memory", "[plugin].name must match the directory name")
need(plugin["category"] == "ai", "[plugin].category is not ai")
for cap in ("ui-surface", "cli"):
    need(cap in plugin["capabilities"], f"capabilities is missing {cap}")
need(len(plugin["capabilities"]) == 2,
     "capabilities carries more than this plugin actually implements")

workspace = doc["ui"]["workspace"]
need(workspace["id"] == "agentMemory", "[ui.workspace].id is not agentMemory")
need(workspace["component"] == "qml/MemoryWorkspace.qml", "[ui.workspace].component moved")
need(workspace["requires_layer"] == "ai", "the plane is not gated on the ai layer")
need(workspace["requires_data"] == "harness", "the plane is not gated on harness events")

# A top-level command: a subcommand only resolves against a core cmd_memory.sh,
# and no core file names a plugin.
cli = doc["cli"]
need(cli["command"] == "memory", "[cli].command must be memory")
need("subcommand" not in cli or cli["subcommand"] == "",
     "[cli].subcommand cannot resolve: nothing in core provides a memory command")
need(cli["script"] == "cli/memory.sh", "[cli].script moved")
need(cli["summary"].strip(), "[cli].summary is empty")

# What the uninstaller has to say it will take with it.
owns = doc.get("owns")
need("agent-memory" in "".join(owns["external_config"]),
     "[owns].external_config does not name the store")

# Nothing password-shaped is ever declared, in this section or any other.
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

for f in cli/memory.sh python/memory_core.py qml/MemoryService.qml \
         qml/MemoryWorkspace.qml qml/qmldir README.md; do
    [[ -f "$PLUGIN/$f" ]] || fail "$f missing"
done
for t in tests/test_memory_core.py tests/test_memory_cli.sh tests/test_manifest.sh \
         tests/test_memory_service.sh tests/MemoryServiceProbe.qml; do
    [[ -f "$PLUGIN/$t" ]] || fail "$t missing"
done

# Install copies the tree and chmods hooks/ only, so an executable bit
# anywhere else has to be committed. The git mode is the one that survives
# the copy; the filesystem check still runs untracked, which is what makes
# this usable before the first commit.
[[ -x "$PLUGIN/cli/memory.sh" ]] || fail "cli/memory.sh is not executable"
if git -C "$ROOT" ls-files --error-unmatch agent-memory/cli/memory.sh >/dev/null 2>&1; then
    [[ "$(git -C "$ROOT" ls-files -s -- agent-memory/cli/memory.sh | awk '{print $1}')" == "100755" ]] \
        || fail "cli/memory.sh is committed without the executable bit"
fi

# Sourced, never executed: core sources this in a subshell, so an `exit`
# would take the dispatcher's subshell with it.
grep -qE '\bexit\b' "$PLUGIN/cli/memory.sh" && fail "cli/memory.sh must use return, not exit"
grep -qE '\breturn\b' "$PLUGIN/cli/memory.sh" || fail "cli/memory.sh never returns"

# --------------------------------------------------------------- engine

grep -q 'hashlib' "$PLUGIN/python/memory_core.py" || fail "the signature is not a hash"
grep -q 'os.replace' "$PLUGIN/python/memory_core.py" || fail "the store is not written atomically"
grep -q 'APHOTIC_STATE_HOME' "$PLUGIN/python/memory_core.py" || fail "the state home override is gone"

# --------------------------------------------------------------- qmldir

grep -qE '^module qs\.modules\.plugins\.agentMemory$' "$QMLDIR" \
    || fail "the module path changed"
grep -qE '^singleton MemoryService ' "$QMLDIR" || fail "MemoryService is not exported as a singleton"
grep -qE '^MemoryWorkspace ' "$QMLDIR" || fail "MemoryWorkspace is not exported"

# ----------------------------------------------------------- QML rules

# Every "this must not appear" check below runs against a comment-stripped
# copy. Prose explaining why a thing was removed names that thing, and a
# naive grep then fails on the explanation. The singleton reachability
# test in core strips comments for the same reason.
STRIPPED="$(mktemp -d)"
trap 'rm -rf "$STRIPPED"' EXIT
for f in "$SERVICE" "$PANE"; do
    sed 's|//.*||' "$f" > "$STRIPPED/$(basename "$f")"
done
NO_SERVICE="$STRIPPED/MemoryService.qml"
NO_PANE="$STRIPPED/MemoryWorkspace.qml"

if grep -nE '#[0-9A-Fa-f]{6,8}|Qt\.rgba\(' "$NO_PANE"; then
    fail "the plane contains a hardcoded color"
fi
if grep -qE 'font\.pixelSize' "$NO_PANE"; then
    fail "hardcoded pixel type size instead of a Tokens font style"
fi
if grep -qE 'font\.family:.*,' "$NO_PANE"; then
    fail "font.family carries a comma list Qt cannot resolve"
fi

grep -q 'Tokens\.' "$PANE" || fail "the plane does not use Tokens"
grep -q 'Colours\.palette' "$PANE" || fail "the plane's colours must resolve through Colours.palette"
for component in StyledRect StyledText; do
    grep -q "$component" "$PANE" || fail "the plane does not use $component"
done

# Status has to stay readable under a palette wallust derived from a
# wallpaper, where the ANSI slots carry no guaranteed hue.
grep -q 'function statusHue' "$PANE" || fail "status colours are not derived from the live palette"
grep -q 'statusReference: Colours\.palette' "$PANE" || fail "status derivation is not anchored to the palette"

# The state holder is the one file that can be instantiated offscreen under
# a throwaway state directory, which is what the probe test does.
grep -q 'pragma Singleton' "$SERVICE" || fail "MemoryService must be a singleton"
if grep -nE '^import qs\.' "$SERVICE"; then
    fail "MemoryService imports qs.*; that is what makes it unprobeable offscreen"
fi
if grep -nE '\bFileView\b|\bTimer\b' "$NO_SERVICE"; then
    fail "the state holder holds a watch: that is what makes a closed plane cost something"
fi

# The plane is the only consumer, so it owns the only watch.
grep -q 'FileView' "$PANE" || fail "the plane does not follow the event log"
grep -q 'watchChanges: true' "$PANE" || fail "the event log watch is not incremental"
grep -q 'cliPrefix' "$SERVICE" || fail "the service does not name the command verb"
grep -q '"aphotic", root.cliPrefix' "$SERVICE" || fail "the service does not run the plugin command"
grep -q 'build()' "$PANE" || fail "the plane never asks for a build"
grep -q 'inject' "$PANE" || fail "the plane cannot manage the injected digest"

# -------------------------------------------------------- the catalogue

python3 "$ROOT/tools/build_index.py" --check
python3 - "$ROOT/index.json" <<'PY' || exit 1
import json
import sys

catalogue = json.load(open(sys.argv[1]))
entry = next((p for p in catalogue["plugins"] if p["name"] == "agent-memory"), None)
if entry is None:
    print("FAIL: the catalogue has no agent-memory entry")
    sys.exit(1)
if not any(s.get("surface") == "workspace" for s in entry.get("ui", {}).get("surfaces", [])):
    print("FAIL: the catalogue entry has no workspace surface")
    sys.exit(1)
PY

grep -q 'agent-memory/' "$ROOT/README.md" || fail "the root README does not list agent-memory"

echo "PASS: agent-memory manifest, catalogue and QML rules"
