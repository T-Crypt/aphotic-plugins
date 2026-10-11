#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCAN="$ROOT/game-launcher/bin/scan_games.py"

[[ -f "$SCAN" ]] || fail "scanner missing"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home"
mkdir -p "$HOME/.local/share/Steam/steamapps" "$HOME/.config/steam/config" "$FIX/bin"

# A fake store client on PATH.
printf '#!/bin/sh\nexit 0\n' > "$FIX/bin/steam"
chmod +x "$FIX/bin/steam"
export PATH="$FIX/bin:$PATH"

# One installed game, one not installed, one excluded tool.
cat > "$HOME/.local/share/Steam/steamapps/appmanifest_730.acf" <<'EOF'
"SteamApp"
{
	"appid" "730"
	"Universe" "2"
	"name" "Counter-Strike 2"
	"stateflags" "4"
	"installdir" "Counter-Strike 2"
	"lastupdate" "1700000000"
	"SizeOnDisk" "0"
	"buildid" "0"
	"shaBase" ""
	"Extended"
	{
	}
	"LastRequiredBuildID"
	{
	}
	"InstalledDepots"
	{
	}
	"SharedDepots"
	{
	}
	"ManifestItems"
	{
	}
	"State"
	{
		"unpacked" "1"
		"UnpackComplete" "1"
	}
}
EOF
cat > "$HOME/.local/share/Steam/steamapps/appmanifest_550.acf" <<'EOF'
"SteamApp"
{
	"appid" "550"
	"Universe" "2"
	"name" "Left 4 Dead 2"
	"State"
	{
		"UnpackComplete" "1"
	}
}
EOF
cat > "$HOME/.local/share/Steam/steamapps/appmanifest_240.acf" <<'EOF'
"SteamApp"
{
	"appid" "240"
	"Universe" "2"
	"name" "Team Fortress 2"
	"State"
	{
		"Downloading" "1"
	}
}
EOF
cat > "$HOME/.local/share/Steam/steamapps/appmanifest_912130.acf" <<'EOF'
"SteamApp"
{
	"appid" "912130"
	"Universe" "2"
	"name" "Proton"
	"State"
	{
		"UnpackComplete" "1"
	}
}
EOF

# No-State-block manifests (as some Steam builds write them): a real
# install is found, an empty placeholder is not.
cat > "$HOME/.local/share/Steam/steamapps/appmanifest_3164500.acf" <<'EOF'
"AppState"
{
	"appid" "3164500"
	"Universe" "1"
	"name" "Schedule I"
	"installdir" "Schedule I"
	"SizeOnDisk" "7417849141"
}
EOF
cat > "$HOME/.local/share/Steam/steamapps/appmanifest_999999.acf" <<'EOF'
"AppState"
{
	"appid" "999999"
	"Universe" "1"
	"name" "Ghost App"
	"installdir" ""
	"SizeOnDisk" "0"
}
EOF

# A second Steam library named in libraryfolders.vdf must be scanned too.
mkdir -p "$HOME/libraries/games/steamapps"
cat > "$HOME/.local/share/Steam/steamapps/libraryfolders.vdf" <<EOF
"libraryfolders"
{
	"0"
	{
		"path"		"$HOME/.local/share/Steam"
	}
	"1"
	{
		"path"		"$HOME/libraries/games"
	}
}
EOF
cat > "$HOME/libraries/games/steamapps/appmanifest_400.acf" <<'EOF'
"AppState"
{
	"appid" "400"
	"Universe" "1"
	"name" "Portal"
	"State"
	{
		"UnpackComplete" "1"
	}
}
EOF

# Playtime feed.
cat > "$HOME/.config/steam/config/localconfig.vdf" <<'EOF'
"UserLocal"
{
	"User"
	{
		"76561198000000000"
		{
			"Games"
			{
				app730
				{
					HoursPlayed "120",
				}
			}
		}
	}
}
EOF

# Shortcuts: one own-exe shortcut, one Steam-app shortcut.
cat > "$HOME/.local/share/Steam/steamapps/shortcuts.vdf" <<'EOF'
"Shortcuts"
{
	"MyGame"
	{
		"Exe" "/opt/mygame/mygame"
		"StartDir" "/opt/mygame"
		"SteamAppId" "0"
		"LaunchType" "0"
	}
	"Retro"
	{
		"Exe" ""
		"StartDir" ""
		"SteamAppId" "4361"
	}
}
EOF

# Lutris: the read-only games database plus a coverart directory.
mkdir -p "$HOME/.local/share/lutris" "$HOME/.local/share/lutris/coverart"
python3 - "$HOME/.local/share/lutris/pga.db" <<'EOF'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE games (id INTEGER PRIMARY KEY, slug TEXT, name TEXT, runner TEXT, lastplayed INTEGER, installed INTEGER)")
con.execute("INSERT INTO games VALUES (1, 'baldurs-gate-3', 'Baldur''s Gate 3', 'heroic', 1700000000, 1)")
con.execute("INSERT INTO games VALUES (2, 'half-life-2', 'Half-Life 2', 'source', 0, 1)")
con.execute("INSERT INTO games VALUES (3, 'uninstalled-game', 'Gone Game', 'flatpak', 0, 0)")
con.commit()
EOF
printf 'fakecover' > "$HOME/.local/share/lutris/coverart/baldurs-gate-3.jpg"

# A lutris client on PATH so the games are launchable.
printf '#!/bin/sh\nexit 0\n' > "$FIX/bin/lutris"
chmod +x "$FIX/bin/lutris"

# Heroic: one store with installed games, one library without installed.json.
mkdir -p "$HOME/.config/heroic/store_cache/legendary" "$HOME/.config/heroic/store_cache/gog_store" "$HOME/.config/heroic/sideload_apps"
cat > "$HOME/.config/heroic/store_cache/legendary/library.json" <<'EOF'
{"library": [
  {"app_name": "c9233194-671a-439c-b1ac-e1d284e53942", "title": "Hades", "art_cover": "https://cdn1.epicgames.com/offer.jpg", "art_square": ""},
  {"app_name": "deadbeef-1234-5678-9abc-def012345678", "title": "Cuphead", "art_cover": "", "art_square": ""},
  {"app_name": "a1b2c3d4-e5f6-7890-abcd-ef1234567890", "title": "Not Downloaded", "art_cover": ""}
]}
EOF
cat > "$HOME/.config/heroic/store_cache/legendary/installed.json" <<'EOF'
{"installed": [{"app_name": "c9233194-671a-439c-b1ac-e1d284e53942"}, {"app_name": "deadbeef-1234-5678-9abc-def012345678"}]}
EOF
# gog_store has a library but no installed.json: everything in it is
# listed (no way to know what is installed, so trust the library).
cat > "$HOME/.config/heroic/store_cache/gog_store/library.json" <<'EOF'
{"library": [{"app_name": "12345", "name": "GOG Game", "art_cover": "", "art_square": ""}]}
EOF
cat > "$HOME/.config/heroic/sideload_apps/library.json" <<'EOF'
{"games": [
  {"app_name": "sideloaded-rom", "title": "Sideloaded ROM", "is_installed": true, "art_cover": ""},
  {"app_name": "other-rom", "title": "Not Installed ROM", "is_installed": false}
]}
EOF
printf '#!/bin/sh\nexit 0\n' > "$FIX/bin/heroic"
chmod +x "$FIX/bin/heroic"

# Cartridges: per-game JSON plus a gif cover (its native animated cover).
mkdir -p "$HOME/.local/share/cartridges/games" "$HOME/.local/share/cartridges/covers"
cat > "$HOME/.local/share/cartridges/games/gid0001.json" <<'EOF'
{"added": 1, "executable": "/usr/bin/doom", "game_id": "gid0001",
 "source": "desktop_custom", "hidden": false, "last_played": 1710000000,
 "name": "Doom", "removed": false, "blacklisted": false, "version": 1}
EOF
cat > "$HOME/.local/share/cartridges/games/gid0002.json" <<'EOF'
{"added": 1, "executable": "", "game_id": "gid0002",
 "source": "steam_60", "hidden": true, "last_played": 0,
 "name": "Hidden One", "removed": false, "blacklisted": false, "version": 1}
EOF
printf 'fakegif' > "$HOME/.local/share/cartridges/covers/gid0001.gif"

# Desktop entries: one game, one tool (excluded).
mkdir -p "$HOME/Desktop"
cat > "$HOME/Desktop/my-game.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=My Desktop Game
Exec=/usr/games/my-game %u
Icon=/home/user/Pictures/boxart/my-game.jpg
EOF
cat > "$HOME/Desktop/steam-tool.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Steam Runtime Tools
Exec=/opt/steam/runtime
EOF

# Manual games file, as the service writes it.
cat > "$FIX/manual.json" <<'EOF'
[{"name": "Hades", "exec": "lutris play heroic-hades", "cover": ""}]
EOF
cat > "$FIX/settings.json" <<'EOF'
{"sources": {"steam": true, "lutris": true, "heroic": true, "cartridges": true, "desktop": true},
 "box_art_dir": "", "sgdb": {"enabled": false, "api_key": "", "animated": false},
 "sort_by": "recent", "favorites_first": true, "close_on_launch": true,
 "tile_enabled": true, "favorites": ["Doom:cartridges"]}
EOF

OUT="$(python3 "$SCAN" --settings "$FIX/settings.json" --manual "$FIX/manual.json" 2>"$FIX/err.log")"


# Clients: steam, lutris and heroic stubs are on PATH; cartridges absent.
echo "$OUT" | jq -e '.clients.steam != ""' >/dev/null || fail "steam client not detected"
echo "$OUT" | jq -e '.clients.lutris != ""' >/dev/null || fail "lutris client not detected"
echo "$OUT" | jq -e '.clients.heroic != ""' >/dev/null || fail "heroic client not detected"
echo "$OUT" | jq -e '.clients.cartridges == ""' >/dev/null || fail "cartridges must be empty"
echo "$OUT" | jq -e '.big_picture == true' >/dev/null || fail "big_picture follows the steam client"


# Installed games only, tools excluded, playtime attached.
echo "$OUT" | jq -e '[.games[] | select(.appid == "730" or .appid == "550")] | map(.name) | sort == ["Counter-Strike 2", "Left 4 Dead 2"]' >/dev/null || fail "steam library list wrong: $OUT"
echo "$OUT" | jq -e '.games[] | select(.appid == "730") | .playtime_hours == 120' >/dev/null || fail "playtime not read from localconfig"
echo "$OUT" | jq -e '[.games[] | select(.appid == "730") | .exec] == [(.clients.steam + " -silent steam://rungameid/730")]' >/dev/null || fail "steam exec wrong"

# An install with no State block (some Steam builds write it that way) is
# found by its on-disk footprint; an empty placeholder manifest is not.
echo "$OUT" | jq -e '[.games[] | select(.appid == "3164500") | {name, source, exec}] == [{name: "Schedule I", source: "steam", exec: (.clients.steam + " -silent steam://rungameid/3164500")}]' >/dev/null || fail "no-State install missed"
echo "$OUT" | jq -e '[.games[] | select(.appid == "999999")] | length == 0' >/dev/null || fail "empty placeholder manifest leaked in"
# A second Steam library named in libraryfolders.vdf is scanned too.
echo "$OUT" | jq -e '.games[] | select(.appid == "400") | .name == "Portal" and .source == "steam"' >/dev/null || fail "second library folder not scanned"

# Own-exe shortcut: cd into StartDir and run the binary.
echo "$OUT" | jq -e '.games[] | select(.name == "MyGame") | .exec == "cd /opt/mygame && /opt/mygame/mygame"' >/dev/null || fail "own-exe shortcut exec wrong"
# Steam-app shortcut: launches through the client.
echo "$OUT" | jq -e '[.games[] | select(.name == "Retro") | .exec] == [(.clients.steam + " -silent steam://rungameid/4361")]' >/dev/null || fail "steam-app shortcut exec wrong"

# Lutris: installed only, the real lastplayed, the local cover.
echo "$OUT" | jq -e '[.games[] | select(.appid == "baldurs-gate-3") | {exec, last_played, cover}] == [{exec: (.clients.lutris + " play baldurs-gate-3"), last_played: 1700000000, cover: (env.HOME + "/.local/share/lutris/coverart/baldurs-gate-3.jpg")}]' >/dev/null || fail "lutris entry wrong"
echo "$OUT" | jq -e '[.games[] | select(.name == "Gone Game")] | length == 0' >/dev/null || fail "uninstalled lutris game leaked in"

# Heroic: installed epic game launches through the client; the uninstalled
# one is out; the store without installed.json lists its library; the
# installed sideloaded rom is in.
echo "$OUT" | jq -e '[.games[] | select(.name == "Cuphead" and .source == "heroic") | .exec] == [(.clients.heroic + " --no-gui heroic://launch/epic/deadbeef-1234-5678-9abc-def012345678")]' >/dev/null || fail "heroic epic entry wrong"
echo "$OUT" | jq -e '[.games[] | select(.name == "Not Downloaded")] | length == 0' >/dev/null || fail "uninstalled heroic game leaked in"
echo "$OUT" | jq -e '.games[] | select(.name == "GOG Game") | .source == "heroic"' >/dev/null || fail "heroic gog store missing"
echo "$OUT" | jq -e '[.games[] | select(.name == "Sideloaded ROM") | .exec] == [(.clients.heroic + " --no-gui heroic://launch/sideload/sideloaded-rom")]' >/dev/null || fail "heroic sideload entry wrong"

# Cartridges: hidden games out, the gif cover in, real last_played.
echo "$OUT" | jq -e '.games[] | select(.name == "Doom" and .source == "cartridges") | .exec == "/usr/bin/doom" and .cover == (env.HOME + "/.local/share/cartridges/covers/gid0001.gif") and .last_played == 1710000000' >/dev/null || fail "cartridges entry wrong"
echo "$OUT" | jq -e '[.games[] | select(.name == "Hidden One")] | length == 0' >/dev/null || fail "hidden cartridges game leaked in"

# Desktop: the game in, the tool out, format args stripped.
echo "$OUT" | jq -e '.games[] | select(.name == "My Desktop Game") | .exec == "/usr/games/my-game"' >/dev/null || fail "desktop entry wrong"
echo "$OUT" | jq -e '[.games[] | select(.name == "Steam Runtime Tools")] | length == 0' >/dev/null || fail "desktop tool leaked in"

# Dedupe: the manual Hades wins over the heroic one, and the manual's
# exec is the one that survives.
echo "$OUT" | jq -e '[.games[] | select(.name == "Hades")] | length == 1' >/dev/null || fail "dedupe by name failed"
echo "$OUT" | jq -e '.games[] | select(.name == "Hades") | .source == "manual" and .exec == "lutris play heroic-hades"' >/dev/null || fail "dedupe priority wrong"

# Favorites come from the settings file.
echo "$OUT" | jq -e '.games[] | select(.name == "Doom") | .favorite == true' >/dev/null || fail "favorite not applied"

# A half-installed store must not break the rest: break the heroic
# library and re-scan; everything else still comes back.
rm -rf "$HOME/.config/heroic"
OUT2="$(python3 "$SCAN" --settings "$FIX/settings.json" --manual "$FIX/manual.json" 2>"$FIX/err2.log")"
echo "$OUT2" | jq -e '[.games[].source] | unique | index("steam") and index("lutris")' >/dev/null || fail "a dead store emptied the other sources"
echo "$OUT2" | jq -e '[.games[] | select(.source == "heroic")] | length == 0' >/dev/null || fail "heroic games must vanish with their store"

# Big library: 1200 ACFs still scan in bounded time.
ACFDIR="$HOME/.local/share/Steam/steamapps"
for i in $(seq 10000 11200); do
  printf '"SteamApp"\n{\n\t"appid" "%s"\n\t"Universe" "2"\n\t"name" "Bulk Game %s"\n\t"State"\n\t{\n\t\t"UnpackComplete" "1"\n\t}\n}\n' "$i" "$i" > "$ACFDIR/appmanifest_${i}.acf"
done
START=$(date +%s)
python3 "$SCAN" --settings "$FIX/settings.json" --manual "$FIX/manual.json" >/dev/null 2>&1
DUR=$(( $(date +%s) - START ))
[[ $DUR -lt 10 ]] || fail "scan took ${DUR}s over a 1200-game library"

echo "PASS: scan_games (sources)"
echo "PASS: scan_games (all sources)"
