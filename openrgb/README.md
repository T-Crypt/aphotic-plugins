# OpenRGB Sync

Syncs [Aphotic-Hypr](https://github.com/T-Crypt/aphotic-hypr)'s active
theme accent color to your RGB PC lighting via
[OpenRGB](https://openrgb.org/).

## Requires

- `openrgb` on `PATH` (the CLI, not just the GUI — install via your
  distro's package or the OpenRGB AppImage).
- `jq`.

## What it does

On every theme or wallpaper change, sets every OpenRGB-detected device to
a flat, static color matching the theme's accent (`color4` in the
resolved palette — the same slot Aphotic-Hypr's own Quickshell shell
maps to its `m3primary` role).

This is v1: one flat color across every device. Per-device zone mapping
(a different color per RAM stick vs. case fan header, keyboard zones,
etc.) is real, useful follow-up work, not done here yet.

## Install

```sh
git clone https://github.com/T-Crypt/aphotic-plugins ~/aphotic-plugins
aphotic plugin install openrgb
```

Or for plugin development (edits take effect without reinstalling):

```sh
aphotic plugin install openrgb --link
```
