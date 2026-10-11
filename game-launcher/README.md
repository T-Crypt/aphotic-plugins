# Game Launcher

> **Category:** Gaming

A visual game library on the Aphotic workspace plane. It finds the games you
already have, launches each one with its own command, and gets out of the way
while you play.

## What it does

- Opens on the workspace plane with the other workspace tools
  (SUPER+SHIFT+W): a grid of your games, source tabs, search, favorites,
  and a big picture mode with keyboard walk (F to enter, arrows to walk,
  Enter to launch, Esc to leave).
- Finds installed games automatically: Steam (library and shortcuts),
  Lutris, Heroic (Epic, GOG, Amazon and sideloaded), Cartridges, .desktop
  files on the Desktop, and a manual list you keep in Settings.
- Launches each game with its own command, detached from the shell.
- Shows a Games tile in the notch with one quick-launch button per
  installed store client.
- A Settings section under Power and Security: per-source toggles,
  the manual game list, cover options (a box-art directory; SteamGridDB
  is opt-in and the only network this plugin makes), sort order,
  favorites-first, close-on-launch, and the notch tile.

## Install

From the built-in plugin browser (Settings → Plugins → Browse), or from a
checkout of this repository:

    aphotic plugin install game-launcher/
    # or, for a live checkout,
    aphotic plugin install game-launcher/ --link

The Gaming opt-in (the `gaming` layer) must be on for any of the surfaces
to appear; they all register together and disappear together when the
plugin is disabled or removed.

## Usage

- Open the workspace plane (SUPER+SHIFT+W) and select the Games tab.
- Click a game (or Enter on the focused card) to launch it; the plane
  closes if close-on-launch is on.
- Press F inside the plane for big picture mode.
- Rescan from the plane header or the Settings section whenever you
  install or uninstall something: the scan runs once at shell start and
  only on those explicit triggers, never on a timer.
- The notch tile's buttons open the store clients themselves.

While a game runs, the Gaming profile takes the plugin's surfaces off
screen as part of its frame shelter; they come back when the game exits.

## Remove

    aphotic plugin remove game-launcher

This removes the registry entry, the workspace tab, the settings section,
the notch tile and the module link. Your settings, favorites and manual
list remain in `~/.config/aphotic/plugins/game-launcher/`; delete that
directory to clear them.

## Idle cost

One small notch tile (when the tile is enabled and the gaming layer is
on) and one completed scan in memory. No timers, no file watches on
external data, no network unless the SteamGridDB opt-in is enabled and
a rescan runs. While a game runs, the plugin's surfaces are sheltered
away entirely.
