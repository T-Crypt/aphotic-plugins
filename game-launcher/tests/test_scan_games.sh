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

OUT="$(python3 "$SCAN" 2>"$FIX/err.log")"

# Clients: only steam exists in this fixture (which() returns full paths).
echo "$OUT" | jq -e '.clients.steam != ""' >/dev/null || fail "steam client not detected"
echo "$OUT" | jq -e '.clients.lutris == ""' >/dev/null || fail "lutris must be empty"
echo "$OUT" | jq -e '.big_picture == true' >/dev/null || fail "big_picture follows the steam client"

# Installed games only, tools excluded, playtime attached.
echo "$OUT" | jq -e '[.games[] | select(.appid == "730" or .appid == "550")] | map(.name) | sort == ["Counter-Strike 2", "Left 4 Dead 2"]' >/dev/null || fail "steam library list wrong: $OUT"
echo "$OUT" | jq -e '.games[] | select(.appid == "730") | .playtime_hours == 120' >/dev/null || fail "playtime not read from localconfig"
echo "$OUT" | jq -e '[.games[] | select(.appid == "730") | .exec] == [(.clients.steam + " -silent steam://rungameid/730")]' >/dev/null || fail "steam exec wrong"

# Own-exe shortcut: cd into StartDir and run the binary.
echo "$OUT" | jq -e '.games[] | select(.name == "MyGame") | .exec == "cd /opt/mygame && /opt/mygame/mygame"' >/dev/null || fail "own-exe shortcut exec wrong"
# Steam-app shortcut: launches through the client.
echo "$OUT" | jq -e '[.games[] | select(.name == "Retro") | .exec] == [(.clients.steam + " -silent steam://rungameid/4361")]' >/dev/null || fail "steam-app shortcut exec wrong"

echo "PASS: scan_games (core)"
