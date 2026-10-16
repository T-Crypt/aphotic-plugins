#!/usr/bin/env bash
# skills/tests/test_contract.sh -- the shapes other plugins also enforce.
#
# Mirrors game-launcher/tests/test_contract.sh, because every plugin keeps
# the same promises: the manifest declares everything it ships, every
# component named in the manifest exists on disk, the qmldir lists every
# component, the service is a singleton and is the single source of truth,
# and the index/README entry the catalogue reads agrees with the manifest.
#
# Two checks are specific to this plugin: the sha256 pin agrees between
# lib/skillscli.sh (which the QML service and the wrapper consult) and
# hooks/install-deps.sh (which downloads against the same pin), and a
# file:// override -- the same one test_install_deps.sh uses -- has the
# bytes the pin promises. Without this pair the plugin can install a
# binary and the pane can refuse to trust it on the same day.
set -euo pipefail

fail() { echo "FAIL: $1" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN="$ROOT/skills"
MANIFEST="$PLUGIN/plugin.toml"

[[ -f "$MANIFEST" ]] || fail "manifest missing"

# Mandatory manifest keys. The plugin block is what the catalogue reads;
# anything missing here is invisible to aphotic plugin list.
for key in name display_name description version author category capabilities; do
    rg -q "^[[:space:]]*$key" "$MANIFEST" || fail "manifest missing $key"
done

# Capabilities must include the four the manifest then exercises: a
# settings pane, a workspace surface, the headless action and the
# cli/keybind pair. A capability declared but never used is fine; a
# capability used but never declared is a silent second way in.
for cap in ui-surface action cli keybind; do
    rg -q "\"$cap\"" "$MANIFEST" || fail "capability '$cap' not declared"
done

# Every section the plugin claims. The surfaces are what get a host
# window and a rail slot; the action is what command palette/IPC/keybind
# all run; the cli is the terminal; the owns block is what tells the
# uninstaller which paths it touched.
rg -q '^\[plugin\]' "$MANIFEST"             || fail "missing [plugin]"
rg -q '^\[requires\]' "$MANIFEST"           || fail "missing [requires]"
rg -q '^\[ui\.workspace\]' "$MANIFEST"      || fail "missing [ui.workspace]"
rg -q '^\[ui\.settings_pane\]' "$MANIFEST"  || fail "missing [ui.settings_pane]"
rg -q '^\[action\]' "$MANIFEST"             || fail "missing [action]"
rg -q '^\[cli\]' "$MANIFEST"                || fail "missing [cli]"
rg -q '^\[keybind\]' "$MANIFEST"            || fail "missing [keybind]"
rg -q '^\[owns\]' "$MANIFEST"               || fail "missing [owns]"

# `installed via AUR is not the right answer' -- there's no package by
# that name, so the manifest must point core at our own downloader.
rg -q 'install_script = "hooks/install-deps.sh"' "$MANIFEST" \
    || fail "requires.install_script must point at hooks/install-deps.sh"

# The settings pane docks under an existing category. A new parent
# would be a second way in; an empty one would put the pane on the rail.
rg -q 'parent = "ai"' "$MANIFEST" \
    || fail "settings pane must dock under the AI category"

# A plugin keeps one compartment. Top-level `skills` is what the
# command line shell sees; no subcommand, because there is no core
# command with that name to resolve under.
rg -q 'command = "skills"' "$MANIFEST" \
    || fail "[cli] must own the top-level 'skills' command"
if rg -q '^[[:space:]]*subcommand' "$MANIFEST"; then
    fail "[cli] must not declare a subcommand (only resolves when core ships the cmd)"
fi

# The keybind's action id must exist as an action id in the same
# manifest, otherwise it would be a second path to invoke a workspace
# the rest of the plugin never opens. Read the id from the [keybind]
# section, then look for an id of that name in any [action] section.
keybind_action="$(awk '/^\[keybind\]/{k=1; next} /^\[/ && !/^\[keybind\]/{k=0} k && /^[[:space:]]*action[[:space:]]*=/{gsub(/.*=[[:space:]]*"|".*/,""); print; exit}' "$MANIFEST")"
[[ -n "$keybind_action" ]] || fail "no [keybind].action declared"

awk -v target="$keybind_action" '
    /^\[action\]/ { in_action=1; next }
    /^\[/ && !/^\[action\]/ { in_action=0 }
    in_action && /^[[:space:]]*id[[:space:]]*=/ {
        line=$0
        sub(/^[[:space:]]*id[[:space:]]*=[[:space:]]*"/, "", line)
        sub(/"[[:space:]]*$/, "", line)
        if (line == target) found=1
    }
    END { exit (found ? 0 : 1) }
' "$MANIFEST" || fail "[keybind].action '$keybind_action' is not declared under [action]"

# The pin agreement: lib/skillscli.sh holds the sha256, the hook calls
# the same function, so by construction they share the value. Belt:
# the lib defines skillscli_pin_sha256. Braces: the hook calls it.
rg -q '^skillscli_pin_sha256' "$PLUGIN/lib/skillscli.sh" \
    || fail "lib/skillscli.sh does not define skillscli_pin_sha256"
rg -q 'skillscli_pin_sha256' "$PLUGIN/hooks/install-deps.sh" \
    || fail "hooks/install-deps.sh does not call skillscli_pin_sha256"

# When a real file URL is supplied (the same override the install
# test uses), the bytes must hash to the pin. We recompute it here so
# anyone pinning a new release sees the assertion fail rather than
# ship a downloader that hides a mismatch.
url="${APHOTIC_SKILLS_CLI_URL:-}"
sha_override="${APHOTIC_SKILLS_CLI_SHA256:-}"
if [[ -n "$url" && -n "$sha_override" ]]; then
    cache="$PLUGIN/tests/fixtures/skills-manager-cli"
    expected="$(APHOTIC_SKILLS_CLI_SHA256="$sha_override" bash "$PLUGIN/lib/skillscli.sh" pin_sha256)"
    actual=""
    if command -v sha256sum >/dev/null 2>&1; then
        actual="$(sha256sum "$cache" | cut -d' ' -f1)"
    elif command -v shasum >/dev/null 2>&1; then
        actual="$(shasum -a 256 "$cache" | cut -d' ' -f1)"
    fi
    [[ -n "$actual" ]] || fail "no sha256sum on the test machine"
    [[ "$actual" == "$expected" ]] \
        || fail "fixture hash mismatch: expected $expected, got $actual"
fi

# Every QML component the manifest names must exist. A renamed file
# that still parses is invisible to the surface host.
for component in \
        qml/SkillsWorkspace.qml \
        qml/SkillsSettings.qml \
        qml/SkillRow.qml \
        qml/AgentChip.qml \
        qml/SkillPreview.qml \
        qml/SkillsService.qml \
        qml/actions/OpenSkills.qml; do
    [[ -f "$PLUGIN/$component" ]] || fail "missing component $component"
done

# qmldir: the module name has to be the one the shell imports
# (qs.modules.plugins.skills); every QML file the pane imports has to
# be registered, and the service is the only singleton.
[[ -f "$PLUGIN/qml/qmldir" ]] || fail "qmldir missing"
rg -q '^module qs\.modules\.plugins\.skills$' "$PLUGIN/qml/qmldir" \
    || fail "qmldir module path changed (expected qs.modules.plugins.skills)"
for component in SkillsService SkillsWorkspace SkillRow AgentChip SkillPreview SkillsSettings; do
    if ! awk -v c="$component" 'index($0, c) == 1 || index($0, " " c " ") > 0 {found=1} END{exit (found?0:1)}' "$PLUGIN/qml/qmldir"; then
        fail "qmldir does not register $component"
    fi
done
rg -q '^singleton SkillsService' "$PLUGIN/qml/qmldir" \
    || fail "SkillsService must be declared as a singleton in qmldir"

# Surfaces must not be singletons; the hosts instantiate them.
for surface in SkillsWorkspace SkillsSettings SkillRow AgentChip SkillPreview; do
    if rg -q 'pragma Singleton' "$PLUGIN/qml/$surface.qml"; then
        fail "$surface must not be a singleton"
    fi
done

# SkillRow, AgentChip, SkillPreview, SkillsWorkspace and SkillsSettings
# all hold state on the singleton. Without these references the service
# never builds and the surfaces see a pane-shaped hole.
rg -q 'pragma Singleton' "$PLUGIN/qml/SkillsService.qml" \
    || fail "SkillsService must be a singleton"
for surface in SkillsWorkspace SkillsSettings SkillRow AgentChip SkillPreview; do
    rg -q 'SkillsService' "$PLUGIN/qml/$surface.qml" \
        || fail "$surface.qml never references SkillsService; the service would never construct"
done

# `raw` is what every write goes through in SkillsService._mutate; the
# wrapper must implement it. Without it, deploy/undeploy/tag/preset
# all hit the service, hit the wrapper, and stop. Verify in the cli
# script rather than re-reading the service.
rg -q '\braw\)' "$PLUGIN/cli/skills.sh" || fail "cli/skills.sh does not implement 'raw'"

# The lib is plain shell (no core aphotic_* calls) because the QML
# service runs it as a child process with no shell library loaded.
if rg -q 'aphotic_err\|aphotic_log\|aphotic_warn\|aphotic_require' "$PLUGIN/lib/skillscli.sh"; then
    fail "lib/skillscli.sh calls into core's shell library; the QML service runs it as a plain child process"
fi

# Tokens over raw spacing, palette over literal color names -- the
# surfaces read these paths every time they paint, and a typo in a
# Spacing.medium bound to a literal 8 reads as magic spacing somewhere
# else.
rg -q 'Tokens\.' "$PLUGIN/qml/SkillsWorkspace.qml" \
    || fail "SkillsWorkspace does not reference Tokens"
rg -q 'Colours\.palette' "$PLUGIN/qml/SkillsWorkspace.qml" \
    || fail "SkillsWorkspace colors must resolve through Colours.palette"

# No Timer{} in plugin QML. Constructing the service fires one read;
# every further refresh comes from a user click or a write the service
# itself issued. A timer would poll forever, which violates the
# no-polling rule that game-launcher's contract test enforces too.
if rg -q '\bTimer\s*\{' "$PLUGIN/qml/" --glob '*.qml'; then
    fail "no Timer may exist in plugin QML; refresh is explicit"
fi

# No hardcoded colors anywhere in the QML: theme hooks must be able
# to recolour without editing plugin source.
if rg -q '#[0-9A-Fa-f]{6,8}|Qt\.rgba\(' "$PLUGIN/qml/" --glob '*.qml'; then
    fail "hardcoded color found; resolve it through Colours.palette"
fi

# Catalogue: the index entry and the root README keep the plugin
# discoverable in the built-in browser. The new skills row asserts
# every shape the entry hands the remote browser.
python3 "$ROOT/tools/build_index.py" --check

python3 - "$ROOT/index.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
entry = next((p for p in data["plugins"] if p["name"] == "skills"), None)
assert entry, "skills missing from index.json"
assert entry["category"] == "ai", f"category: {entry['category']}"
assert "ui-surface" in entry["capabilities"], entry["capabilities"]
surfaces = {s["surface"]: s for s in entry.get("ui", {}).get("surfaces", [])}
for kind in ("workspace", "settings"):
    assert kind in surfaces, f"missing {kind} surface: {surfaces}"
assert surfaces["workspace"]["component"] == "qml/SkillsWorkspace.qml"
assert surfaces["settings"]["component"] == "qml/SkillsSettings.qml"
assert surfaces["settings"]["parent"] == "ai"
PYEOF

rg -q '\[`skills`\]\(skills/\)' "$ROOT/README.md" || fail "root README does not list skills/"

# skills/README.md describes the plugin from the user's side. Its
# presence matters because one of the surfaces links to a tear-off
# help path and the wiki's Browse tab picks it up.
[[ -f "$PLUGIN/README.md" ]] || fail "skills/README.md missing"

echo "PASS: skills contract"
