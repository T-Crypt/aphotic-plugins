#!/usr/bin/env bash
# Flatpak-only stores: the client is found by its exact app id, and the
# library is read from ~/.var/app/<app id>, which keeps the id's case.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCAN="$ROOT/game-launcher/bin/scan_games.py"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home"
export PATH="/usr/bin:/bin"

mkdir -p "$HOME/.local/share/flatpak/app/net.lutris.Lutris" \
         "$HOME/.local/share/flatpak/app/page.kramo.Cartridges"

LDATA="$HOME/.var/app/net.lutris.Lutris/data/lutris"
mkdir -p "$LDATA/coverart"
python3 - "$LDATA/pga.db" <<'EOF'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE games (id INTEGER PRIMARY KEY, slug TEXT, name TEXT, runner TEXT, lastplayed INTEGER, installed INTEGER)")
con.execute("INSERT INTO games VALUES (1, 'celeste', 'Celeste', 'linux', 0, 1)")
con.commit()
EOF
printf 'fakecover' > "$LDATA/coverart/celeste.jpg"

CDATA="$HOME/.var/app/page.kramo.Cartridges/data/cartridges"
mkdir -p "$CDATA/games" "$CDATA/covers"
cat > "$CDATA/games/gid0001.json" <<'EOF'
{"added": 1, "executable": "/usr/bin/doom", "game_id": "gid0001",
 "source": "desktop_custom", "hidden": false, "last_played": 0,
 "name": "Doom", "removed": false, "blacklisted": false, "version": 1}
EOF

echo '[]' > "$FIX/manual.json"
cat > "$FIX/settings.json" <<'EOF'
{"sources": {"steam": false, "lutris": true, "heroic": false, "cartridges": true, "desktop": false},
 "box_art_dir": "", "sgdb": {"enabled": false, "api_key": "", "animated": false},
 "sort_by": "recent", "favorites_first": true, "close_on_launch": true,
 "tile_enabled": true, "favorites": []}
EOF

OUT="$(python3 "$SCAN" --settings "$FIX/settings.json" --manual "$FIX/manual.json" 2>"$FIX/err.log")"

echo "$OUT" | jq -e '.clients.lutris == "flatpak run net.lutris.Lutris"' >/dev/null \
  || fail "lutris flatpak client not found by its app id"
echo "$OUT" | jq -e '.clients.cartridges == "flatpak run page.kramo.Cartridges"' >/dev/null \
  || fail "cartridges flatpak client not found by its app id"
echo "$OUT" | jq -e '[.games[] | select(.source == "lutris" and .name == "Celeste")] | length == 1' >/dev/null \
  || fail "lutris games under ~/.var/app were not read"
echo "$OUT" | jq -e '[.games[] | select(.source == "lutris" and .name == "Celeste")][0].cover | endswith("celeste.jpg")' >/dev/null \
  || fail "lutris cover under ~/.var/app was not found"
echo "$OUT" | jq -e '[.games[] | select(.source == "cartridges" and .name == "Doom")] | length == 1' >/dev/null \
  || fail "cartridges games under ~/.var/app were not read"

echo "PASS: scan_games (flatpak-only stores)"
