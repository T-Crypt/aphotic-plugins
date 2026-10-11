#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN="$ROOT/game-launcher"
MANIFEST="$PLUGIN/plugin.toml"

[[ -f "$MANIFEST" ]] || fail "manifest missing"

# The shelter contract lives at the top level, before any section: it
# is how the Gaming profile takes this plugin's surfaces away while a
# game runs, and a sectioned [shelter] table is silently ignored by
# the core.
rg -q '^shelter = "unload"' "$MANIFEST" || fail "shelter = unload not declared at the top level"
line_shelter=$(rg -n '^shelter = "unload"' "$MANIFEST" | head -1 | cut -d: -f1)
first_section=$(rg -n '^\[' "$MANIFEST" | head -1 | cut -d: -f1)
[[ "$line_shelter" -lt "$first_section" ]] || fail "shelter line must precede the first section"


for key in name display_name description version author category capabilities; do
  rg -q "^[[:space:]]*$key" "$MANIFEST" || fail "manifest missing $key"
done

rg -q '^\[ui\.workspace\]' "$MANIFEST" || fail "manifest missing [ui.workspace]"
rg -q '^\[ui\.settings_pane\]' "$MANIFEST" || fail "manifest missing [ui.settings_pane]"
rg -q '^\[ui\.notch_tile\]' "$MANIFEST" || fail "manifest missing [ui.notch_tile]"

# The gaming gate on every surface: nothing appears without the
# gaming opt-in, and nothing may name another plugin.
[[ $(rg -c 'requires_layer = "gaming"' "$MANIFEST") -eq 3 ]] || fail "every surface must require the gaming layer"

[[ -f "$PLUGIN/bin/scan_games.py" ]] || fail "scanner missing"
[[ -f "$PLUGIN/qml/qmldir" ]] || fail "qmldir missing"
rg -q '^module qs\.modules\.plugins\.gameLauncher' "$PLUGIN/qml/qmldir" || fail "module path changed"
rg -q 'GameLauncherService' "$PLUGIN/qml/qmldir" || fail "service not registered in the module"

# The surfaces must not be singletons: the hosts instantiate them.
for surface in GameLauncherWorkspace GamesPane GamesNotchTile; do
  [[ -f "$PLUGIN/qml/$surface.qml" ]] || fail "$surface.qml missing"
  rg -q 'pragma Singleton' "$PLUGIN/qml/$surface.qml" && fail "$surface must not be a singleton"
done

# The service is the one singleton, and it is named by the surfaces
# (that reference is its construction site; without it the scanner
# never runs).
[[ -f "$PLUGIN/qml/GameLauncherService.qml" ]] || fail "service missing"
rg -q 'pragma Singleton' "$PLUGIN/qml/GameLauncherService.qml" || fail "service must be a singleton"
for surface in GameLauncherWorkspace GamesPane GamesNotchTile; do
  rg -q 'GameLauncherService' "$PLUGIN/qml/$surface.qml" || fail "$surface never references GameLauncherService; the service would never construct"
done

# No polling: the no-timer rule of the plugin, and the only FileView
# in the plugin is the one on its own settings file.
if rg -q '\bTimer\b' "$PLUGIN/qml/" --glob '*.qml'; then
  rg -n '\bTimer\b' "$PLUGIN/qml/" --glob '*.qml'
  fail "no Timer may exist in the plugin: the scanner runs on construction and on explicit Rescan only"
fi

# No hardcoded colors: every colour resolves through the palette.
if rg -q '#[0-9A-Fa-f]{6,8}|Qt\.rgba\(' "$PLUGIN/qml/" --glob '*.qml'; then
  rg -n '#[0-9A-Fa-f]{6,8}|Qt\.rgba\(' "$PLUGIN/qml/" --glob '*.qml'
  fail "hardcoded color found; resolve it through Colours.palette"
fi

# Tokens over raw spacing, palette over literal color names.
rg -q 'Tokens\.' "$PLUGIN/qml/GameLauncherWorkspace.qml" || fail "workspace does not use Tokens"
rg -q 'Colours\.palette' "$PLUGIN/qml/GameLauncherWorkspace.qml" || fail "workspace colors must resolve through Colours.palette"

# The settings pane docks under an existing category and never invents
# a rail entry.
rg -q 'parent = "power"' "$MANIFEST" || fail "settings pane must dock under power"

# python3 is the only external binary the scanner needs.
rg -q 'binaries = \["python3"\]' "$MANIFEST" || fail "requires must declare exactly python3"

# The scanner must be stdlib-only: an import of anything else would
# break a minimal install and the no-network contract.
python3 - "$PLUGIN/bin/scan_games.py" <<'EOF' || fail "scanner imports a non-stdlib module"
import sys
allowed = {"json", "os", "re", "shutil", "sqlite3", "sys", "time", "argparse", "shlex", "pathlib"}
bad = []
for line in open(sys.argv[1]):
    line = line.strip()
    if line.startswith("import "):
        mod = line.split()[1].split(".")[0]
        if mod not in allowed:
            bad.append(line)
    elif line.startswith("from ") and line.rstrip().endswith(" import"):
        mod = line.split()[1].split(".")[0]
        if mod not in allowed:
            bad.append(line)
if bad:
    print("\n".join(bad))
    sys.exit(1)
EOF

# Catalogue: the index entry and the root README keep the plugin
# discoverable in the built-in browser.
python3 "$ROOT/tools/build_index.py" --check
python3 - "$ROOT/index.json" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
entry = next((p for p in data["plugins"] if p["name"] == "game-launcher"), None)
assert entry, "game-launcher missing from index.json"
surfaces = {s["surface"] for s in entry.get("ui", {}).get("surfaces", [])}
assert {"workspace", "settings", "notch"} <= surfaces, f"surfaces incomplete: {surfaces}"
EOF
rg -q 'game-launcher/' "$ROOT/README.md" || fail "root README does not list game-launcher"

echo "PASS: game-launcher contract"
