#!/usr/bin/env python3
"""Fail on an icon name the Material Symbols font does not have.

A name the font lacks renders as its literal text, so a typo shows up on
screen as "memory_off" instead of a glyph. Checks string literals given
to `text:` inside a MaterialIcon block, every `icon:` in QML and JS, and
every `icon =` in plugin.toml. tools/material_symbols.txt lists the
font's ligature names; regenerate it after a font update.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAMES = set((ROOT / "tools" / "material_symbols.txt").read_text().split())
NAME = r'"([a-z][a-z0-9_]*)"'


def qml_names(text: str):
    depth_at_icon = []
    depth = 0
    for lineno, line in enumerate(text.splitlines(), 1):
        if re.search(r"\bMaterialIcon\s*\{", line):
            depth_at_icon.append(depth)
        if re.search(r"\bicon\s*:", line):
            for name in re.findall(r"\bicon\s*:\s*" + NAME, line):
                yield lineno, name
        elif depth_at_icon and re.search(r"^\s*text\s*:", line):
            for name in re.findall(NAME, line):
                yield lineno, name
        depth += line.count("{") - line.count("}")
        while depth_at_icon and depth <= depth_at_icon[-1]:
            depth_at_icon.pop()


def main() -> int:
    bad = []
    for path in sorted(ROOT.rglob("*")):
        if ".git" in path.parts or not path.is_file():
            continue
        rel = path.relative_to(ROOT)
        if path.suffix in (".qml", ".js"):
            found = qml_names(path.read_text(encoding="utf-8"))
        elif path.name == "plugin.toml":
            found = ((n, m) for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
                     for m in re.findall(r'^\s*icon\s*=\s*' + NAME, line))
        else:
            continue
        bad.extend(f"{rel}:{n}: {name}" for n, name in found if name not in NAMES)
    for line in bad:
        print(f"unknown icon {line}")
    if bad:
        return 1
    print("PASS: every icon name is in the Material Symbols font")
    return 0


if __name__ == "__main__":
    sys.exit(main())
