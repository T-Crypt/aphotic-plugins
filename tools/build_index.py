#!/usr/bin/env python3
"""Rebuild index.json from every plugin.toml in this repo.

The catalogue is what `aphotic plugin list` reads before anything is
installed, so a hand-typed index is a second copy of every manifest and
it has drifted twice. This derives it instead.

The TOML reading here is not a TOML parser. It is the same flat,
single-section-match, no-arrays-of-tables reader the shell itself uses
(`aphotic_toml_get` in globalcontrol.sh), so the index says exactly what
the installed shell will read off the manifest, quirks included.

Run it before tagging a release, and check the diff in.
"""

import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent

# Section name to the surface kind the registry knows it by, in the order
# `_aphotic_plugin_ui_json` emits them (cmd_plugin.sh).
SURFACE_SECTIONS = [
    ("ui.dashboard_tab", "dashboard"),
    ("ui.notch_tile", "notch"),
    ("ui.pet_action", "pet_action"),
    ("ui.pet_action_2", "pet_action"),
    ("ui.pet_action_3", "pet_action"),
    ("ui.settings_pane", "settings"),
    ("ui.workspace", "workspace"),
    ("ui.overlay", "overlay"),
    ("ui.fullscreen-overlay", "fullscreen-overlay"),
]


def read_key(text: str, section: str, key: str) -> str:
    in_section = False
    pattern = re.compile(r"^\s*" + re.escape(key) + r"\s*=")
    for line in text.splitlines():
        if line == f"[{section}]":
            in_section = True
            continue
        if line.startswith("["):
            in_section = False
        if in_section and pattern.match(line):
            value = line.split("=", 1)[1].strip()
            return value.strip('"')
    return ""


def read_array(text: str, section: str, key: str) -> list:
    raw = read_key(text, section, key)
    if not raw.startswith("["):
        return []
    return [item.strip().strip('"') for item in raw.strip("[]").split(",") if item.strip()]


def read_int(text: str, section: str, key: str) -> int:
    raw = read_key(text, section, key)
    try:
        return int(raw)
    except ValueError:
        return 0


def surface(text: str, section: str, kind: str):
    component = read_key(text, section, "component")
    if not component:
        return None
    return {
        "surface": kind,
        "id": read_key(text, section, "id"),
        "icon": read_key(text, section, "icon"),
        "label": read_key(text, section, "label"),
        "component": component,
        "requires_layer": read_key(text, section, "requires_layer"),
        "requires_data": read_key(text, section, "requires_data"),
        "parent": read_key(text, section, "parent"),
        "anchor": read_key(text, section, "anchor"),
        "width": read_int(text, section, "width"),
        "height": read_int(text, section, "height"),
        "trigger": read_key(text, section, "trigger"),
    }


def entry(manifest: pathlib.Path) -> dict:
    text = manifest.read_text()
    plugin = {
        "name": read_key(text, "plugin", "name"),
        "display_name": read_key(text, "plugin", "display_name"),
        "description": read_key(text, "plugin", "description"),
        "version": read_key(text, "plugin", "version"),
        "category": read_key(text, "plugin", "category"),
        "capabilities": read_array(text, "plugin", "capabilities"),
    }
    surfaces = [s for s in (surface(text, sec, kind) for sec, kind in SURFACE_SECTIONS) if s]
    if surfaces:
        plugin["ui"] = {"surfaces": surfaces}
    return plugin


def build() -> dict:
    manifests = sorted(REPO.glob("*/plugin.toml"))
    return {"plugins": [entry(m) for m in manifests]}


def main() -> int:
    index = REPO / "index.json"
    built = json.dumps(build(), indent=2) + "\n"
    if "--check" in sys.argv:
        if index.read_text() != built:
            print("index.json is out of date; run tools/build_index.py", file=sys.stderr)
            return 1
        print("index.json matches every plugin.toml")
        return 0
    index.write_text(built)
    print(f"wrote {index}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
