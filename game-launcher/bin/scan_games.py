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


# ── Lutris ──────────────────────────────────────────────────────────────

def scan_lutris(lutris_command):
    games = []
    if not lutris_command:
        return games
    db = home() / ".local/share/lutris/pga.db"
    if not db.is_file():
        return games
    try:
        import sqlite3
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        rows = con.execute(
            "SELECT slug, name, lastplayed FROM games "
            "WHERE installed = 1 AND name IS NOT NULL AND name != ''"
        ).fetchall()
        con.close()
    except Exception as exc:  # a corrupt DB degrades to no lutris games
        warn(f"lutris: {exc}")
        return games
    coverart = home() / ".local/share/lutris/coverart"
    for slug, name, lastplayed in rows:
        cover = ""
        for ext in ("jpg", "jpeg", "png"):
            candidate = coverart / f"{slug}.{ext}"
            if candidate.is_file():
                cover = str(candidate)
                break
        games.append({
            "name": name,
            "source": "lutris",
            "exec": f"{lutris_command} play {slug}",
            "cover": cover,
            "last_played": int(lastplayed or 0),
            "playtime_hours": 0,
            "appid": slug or "",
        })
    return games


# ── Heroic ──────────────────────────────────────────────────────────────

HEROIC_STORES = (("legendary", "epic"), ("gog_store", "gog"), ("nile_config", "amazon"))


def _heroic_store(base, store_dir, runner, heroic_command):
    games = []
    library = base / "store_cache" / store_dir / "library.json"
    if not library.is_file():
        return games
    try:
        data = json.loads(library.read_text())
    except (OSError, ValueError) as exc:
        warn(f"heroic: {store_dir} unreadable: {exc}")
        return games
    installed = None
    installed_file = base / "store_cache" / store_dir / "installed.json"
    if installed_file.is_file():
        try:
            installed = {g.get("app_name") for g in json.loads(installed_file.read_text()).get("installed", [])}
        except (OSError, ValueError) as exc:
            warn(f"heroic: {store_dir} installed.json unreadable: {exc}")
            installed = None  # unknown, so trust the library
    for game in data.get("library", []):
        app = game.get("app_name") or game.get("name") or ""
        title = game.get("title") or game.get("name") or app
        if not app or not title:
            continue
        if installed is not None and app not in installed:
            continue
        games.append({
            "name": title,
            "source": "heroic",
            "exec": f"{heroic_command} --no-gui heroic://launch/{runner}/{app}",
            "cover": game.get("art_cover") or game.get("art_square") or "",
            "last_played": 0,
            "playtime_hours": 0,
            "appid": app,
        })
    return games


def scan_heroic(heroic_command):
    games = []
    if not heroic_command:
        return games
    base = home() / ".config/heroic"
    if not base.is_dir():
        return games
    for store_dir, runner in HEROIC_STORES:
        games.extend(_heroic_store(base, store_dir, runner, heroic_command))
    sideload = base / "sideload_apps" / "library.json"
    if sideload.is_file():
        try:
            data = json.loads(sideload.read_text())
        except (OSError, ValueError) as exc:
            warn(f"heroic: sideload unreadable: {exc}")
            data = {}
        for game in data.get("games", []):
            if not game.get("is_installed"):
                continue
            app = game.get("app_name") or ""
            title = game.get("title") or app
            if not app or not title:
                continue
            games.append({
                "name": title,
                "source": "heroic",
                "exec": f"{heroic_command} --no-gui heroic://launch/sideload/{app}",
                "cover": game.get("art_cover") or game.get("art_square") or "",
                "last_played": 0,
                "playtime_hours": 0,
                "appid": app,
            })
    return games


# ── Cartridges ──────────────────────────────────────────────────────────

def _cartridges_dirs():
    h = home()
    return (
        h / ".local/share/cartridges",
        h / ".var/app/page.kramo.cartridges/data/cartridges",
    )


def scan_cartridges(cartridges_command):
    games = []
    for data_dir in _cartridges_dirs():
        games_dir = data_dir / "games"
        covers_dir = data_dir / "covers"
        if not games_dir.is_dir():
            continue
        for path in sorted(games_dir.glob("*.json")):
            try:
                data = json.loads(path.read_text())
            except (OSError, ValueError) as exc:
                warn(f"cartridges: {path.name} unreadable: {exc}")
                continue
            if not isinstance(data, dict):
                continue
            if data.get("hidden") or data.get("blacklisted") or data.get("removed"):
                continue
            name = (data.get("name") or "").strip()
            if not name:
                continue
            executable = data.get("executable") or ""
            if isinstance(executable, list):  # the app joins list forms
                executable = " ".join(shlex.quote(part) for part in executable)
            if not executable:
                if not cartridges_command:
                    continue  # unlaunchable: no own command, no client
                executable = cartridges_command
            cover = ""
            game_id = data.get("game_id") or path.stem
            for ext in ("gif", "tiff"):  # gif first: Qt animates it, tiff not
                candidate = covers_dir / f"{game_id}.{ext}"
                if candidate.is_file():
                    cover = str(candidate)
                    break
            games.append({
                "name": name,
                "source": "cartridges",
                "exec": executable,
                "cover": cover,
                "last_played": int(data.get("last_played") or 0),
                "playtime_hours": 0,
                "appid": game_id,
            })
    return games


# ── Desktop entries ─────────────────────────────────────────────────────

def scan_desktop():
    games = []
    desktop = home() / "Desktop"
    if not desktop.is_dir():
        return games
    for path in sorted(desktop.glob("*.desktop")):
        try:
            text = path.read_text(errors="replace")
        except OSError:
            continue
        values = {}
        for line in text.splitlines():
            match = re.match(r"^\s*([A-Za-z][A-Za-z0-9]*)=(.*)$", line)
            if match:
                values[match.group(1)] = match.group(2).strip()
        name = values.get("Name") or path.stem
        if any(k in name.lower() for k in EXCLUDE_KEYWORDS):
            continue
        exec_ = values.get("Exec", "")
        if not exec_:
            continue
        exec_ = re.sub(r"%[A-Za-z]", "", exec_).strip()  # drop .desktop format args
        icon = values.get("Icon", "")
        cover = icon if icon and Path(icon).is_file() else ""
        games.append({
            "name": name,
            "source": "desktop",
            "exec": exec_,
            "cover": cover,
            "last_played": 0,
            "playtime_hours": 0,
            "appid": path.stem,
        })
    return games


# ── Manual list ─────────────────────────────────────────────────────────

def load_manual(path_str):
    if not path_str:
        return []
    try:
        data = json.loads(Path(path_str).read_text())
    except (OSError, ValueError) as exc:
        warn(f"manual list unreadable ({exc})")
        return []
    games = []
    for entry in data if isinstance(data, list) else []:
        name = (entry.get("name") or "").strip()
        exec_ = (entry.get("exec") or "").strip()
        if not name or not exec_:
            continue
        games.append({
            "name": name,
            "source": "manual",
            "exec": exec_,
            "cover": entry.get("cover") or "",
            "last_played": 0,
            "playtime_hours": 0,
            "appid": "",
        })
    return games


# ── Merge ───────────────────────────────────────────────────────────────

def merge_games(all_games, settings):
    """Filter, dedupe by name (source priority), apply box art and
    favorites, sort."""
    box_dir = settings.get("box_art_dir") or ""
    favorites = set(settings.get("favorites") or [])

    def box_art(name):
        if not box_dir:
            return ""
        base = Path(box_dir).expanduser()
        if not base.is_dir():
            return ""
        for ext in ("webp", "jpg", "jpeg", "png"):
            candidate = base / f"{name}.{ext}"
            if candidate.is_file():
                return str(candidate)
        return ""

    best = {}
    for game in all_games:
        key = game["name"].strip().lower()
        if not key:
            continue
        current = best.get(key)
        if current is None or SOURCE_PRIORITY.get(game["source"], 0) > SOURCE_PRIORITY.get(current["source"], 0):
            best[key] = game
        elif SOURCE_PRIORITY.get(game["source"], 0) == SOURCE_PRIORITY.get(current["source"], 0):
            for field in ("cover", "last_played", "playtime_hours", "appid"):
                if not current.get(field) and game.get(field):
                    current[field] = game[field]

    merged = []
    for game in best.values():
        if not game.get("cover"):
            game["cover"] = box_art(game["name"])
        game["favorite"] = f"{game['name']}:{game['source']}" in favorites
        merged.append(game)

    if settings.get("sort_by", "recent") == "name":
        merged.sort(key=lambda g: g["name"].lower())
    else:
        merged.sort(key=lambda g: (g.get("last_played") or 0, g.get("playtime_hours") or 0), reverse=True)
    if settings.get("favorites_first", True):
        merged.sort(key=lambda g: 0 if g["favorite"] else 1)
    return merged


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
    sources = settings.get("sources") or {}
    def enabled(name, default=True):
        return sources.get(name, default)

    all_games = []
    all_games.extend(load_manual(args.manual))
    if enabled("steam"):
        all_games.extend(scan_steam(clients["steam"]))
    if enabled("lutris"):
        all_games.extend(scan_lutris(clients["lutris"]))
    if enabled("heroic"):
        all_games.extend(scan_heroic(clients["heroic"]))
    if enabled("cartridges"):
        all_games.extend(scan_cartridges(clients["cartridges"]))
    if enabled("desktop"):
        all_games.extend(scan_desktop())

    result = {
        "clients": clients,
        "big_picture": bool(clients["steam"]),
        "games": merge_games(all_games, settings),
    }
    print(json.dumps(result))
    warn(f"scanned {len(result['games'])} games in {time.time() - started:.2f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
