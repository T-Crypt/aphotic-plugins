#!/usr/bin/env python3
"""Find installed games and store clients, print one JSON document.

Event-driven by contract: the shell runs this once when the plugin's
service constructs (shell start) and again on an explicit Rescan from
the UI. It reads local files and exits. It never watches or polls, and
the default path never touches the network: SteamGridDB is the only
network and it runs only when the settings file enables it.
"""

import argparse
import json
import os
import re
import shlex
import shutil
import sys
import time
from pathlib import Path

# Steam library entries that are tooling rather than games.
EXCLUDE_KEYWORDS = (
    "launcher", "manager", "runtime", "proton", "steamtools", "tool",
    "mod manager", "nexus", "vortex", "portproton", "protonup",
    "goverlay", "piper", "parsec", "moonlight", "millennium",
)

# Dedupe order when the same title comes from several sources.
SOURCE_PRIORITY = {
    "manual": 5,
    "steam": 4,
    "heroic": 3,
    "lutris": 2,
    "cartridges": 1,
    "desktop": 0,
}


def warn(message):
    print(f"[scan_games] {message}", file=sys.stderr)


def home():
    return Path(os.environ.get("HOME", str(Path.home())))


# ── Store clients ───────────────────────────────────────────────────────

def _appimage(name_glob, dirs):
    for directory in dirs:
        if not directory.is_dir():
            continue
        for candidate in directory.glob(name_glob):
            if ".Trash" in str(candidate):
                continue
            if os.access(str(candidate), os.X_OK):
                return str(candidate)
    return ""


def _flatpak(flatpak_id):
    for base in ("/var/lib/flatpak/app", str(home() / ".local/share/flatpak/app")):
        if (Path(base) / flatpak_id).is_dir():
            return f"flatpak run {flatpak_id}"
    return ""


def detect_clients():
    """One launch command per store client, empty string when absent."""
    h = home()
    appimage_dirs = (h / "Applications", h / "Downloads", h / ".local/bin", Path("/opt"), h)

    steam = shutil.which("steam") or _appimage("*team*.AppImage", appimage_dirs)
    lutris = shutil.which("lutris") or _flatpak("org.lutris.Lutris")
    heroic = (
        shutil.which("heroic")
        or _appimage("*eroic*.AppImage", appimage_dirs)
        or _flatpak("com.heroicgameslauncher.hgl")
    )
    cartridges = shutil.which("cartridges") or _flatpak("page.kramo.cartridges")

    return {
        "steam": steam or "",
        "lutris": lutris or "",
        "heroic": heroic or "",
        "cartridges": cartridges or "",
    }


# ── VDF (tolerant) ──────────────────────────────────────────────────────

def parse_vdf_pairs(text):
    """Flat key -> value scan of a VDF file; the State table as raw text.

    Enough for appmanifest files: one level of string pairs.
    """
    values = {}
    for match in re.finditer(r'^\s*(?:"([^"]+)"|([A-Za-z_]\w*))\s+"(.*)"\s*$', text, re.M):
        values[match.group(1) or match.group(2)] = match.group(3)
    state = re.search(r'"State"\s*\{(.*?)\}', text, re.S)
    if state:
        values["State"] = state.group(1)
    return values


def parse_shortcuts(text):
    """shortcuts.vdf: one dict per shortcut (name, exe, startdir, appid).

    Tolerant of both VDF shapes: the table name and its brace on one
    line, or the brace on the following line.
    """
    lines = text.splitlines()
    shortcuts = []
    current = None
    depth = 0
    in_shortcuts = False
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        i += 1
        if line == "}":
            depth = max(0, depth - 1)
            if depth == 1:
                current = None  # closed a shortcut entry
            if depth == 0:
                in_shortcuts = False
            continue
        table = re.match(r'^"?([^"{}]+)"\s*$', line)
        if table and i < len(lines) and lines[i].strip() == "{":
            i += 1
            depth += 1
            name = table.group(1)
            if depth == 1 and name == "Shortcuts":
                in_shortcuts = True
            elif in_shortcuts and depth == 2:
                current = {"name": name, "exe": "", "startdir": "", "appid": ""}
                shortcuts.append(current)
            continue
        if current is None:
            continue
        pair = re.match(r'^(?:"([^"]+)"|([A-Za-z_]\w*))\s+"(.*)"\s*$', line)
        if not pair:
            continue
        key = (pair.group(1) or pair.group(2)).lower()
        value = pair.group(3)
        if key == "exe":
            current["exe"] = value
        elif key == "startdir":
            current["startdir"] = value
        elif key in ("appid", "steamappid"):
            current["appid"] = value
    return shortcuts


# ── Steam ───────────────────────────────────────────────────────────────

def _steam_playtime():
    path = home() / ".config/steam/config/localconfig.vdf"
    if not path.is_file():
        return {}
    text = path.read_text(errors="replace")
    playtime = {}
    for block in re.finditer(r"app(\d+)\s*\{(.*?)\}", text, re.S):
        hours = re.search(r'HoursPlayed "(\d+(?:\.\d+)?)', block.group(2))
        if hours:
            playtime[block.group(1)] = int(float(hours.group(1)))
    return playtime


def scan_steam(steam_command):
    games = []
    if not steam_command:
        return games
    acf_dir = home() / ".local/share/Steam/steamapps"
    if not acf_dir.is_dir():
        return games
    playtime = _steam_playtime()

    for acf in sorted(acf_dir.glob("appmanifest_*.acf")):
        try:
            data = parse_vdf_pairs(acf.read_text(errors="replace"))
        except OSError as exc:
            warn(f"steam: unreadable manifest {acf.name}: {exc}")
            continue
        appid = data.get("appid", "")
        name = (data.get("name") or data.get("Name") or "").strip()
        if not appid or not name or appid == "0":
            continue
        state = data.get("State", "")
        if "UnpackComplete" not in state and "Installed" not in state:
            continue  # in the library but not installed
        if any(k in name.lower() for k in EXCLUDE_KEYWORDS):
            continue
        games.append({
            "name": name,
            "source": "steam",
            "exec": f"{steam_command} -silent steam://rungameid/{appid}",
            "cover": f"https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/header.jpg",
            "last_played": 0,
            "playtime_hours": playtime.get(appid, 0),
            "appid": appid,
        })

    shortcuts_path = acf_dir / "shortcuts.vdf"
    if shortcuts_path.is_file():
        try:
            text = shortcuts_path.read_text(errors="replace")
        except OSError:
            text = ""
        for shortcut in parse_shortcuts(text):
            name = shortcut["name"].strip()
            if not name:
                continue
            if any(k in name.lower() for k in EXCLUDE_KEYWORDS):
                continue
            if shortcut["appid"].isdigit() and shortcut["appid"] != "0":
                exec_ = f"{steam_command} -silent steam://rungameid/{shortcut['appid']}"
            elif shortcut["exe"]:
                exec_ = shlex.quote(shortcut["exe"])
                if shortcut["startdir"]:
                    # StartDir is where the game wants to run from,
                    # absolute or not: always cd into it first.
                    exec_ = "cd {} && {}".format(shlex.quote(shortcut["startdir"]), exec_)
            else:
                continue
            games.append({
                "name": name,
                "source": "steam",
                "exec": exec_,
                "cover": "",
                "last_played": 0,
                "playtime_hours": 0,
                "appid": shortcut["appid"],
            })
    return games


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clients-only", action="store_true")
    parser.add_argument("--settings", default="")
    parser.add_argument("--manual", default="")
    args = parser.parse_args()

    settings = {}
    if args.settings:
        try:
            settings = json.loads(Path(args.settings).read_text())
        except (OSError, ValueError) as exc:
            warn(f"settings unreadable ({exc}); using defaults")

    clients = detect_clients()
    if args.clients_only:
        print(json.dumps({"clients": clients,
                          "big_picture": bool(clients["steam"]),
                          "games": []}))
        return 0

    started = time.time()
    games = []
    # Task 2 appends the lutris / heroic / cartridges / desktop / manual
    # sources here and then runs the merge below.
    games.extend(scan_steam(clients["steam"]))

    result = {
        "clients": clients,
        "big_picture": bool(clients["steam"]),
        "games": games,
    }
    print(json.dumps(result))
    warn(f"scanned {len(result['games'])} games in {time.time() - started:.2f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
