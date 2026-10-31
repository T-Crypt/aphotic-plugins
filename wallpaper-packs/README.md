# Wallpaper Packs

Theme-matched wallpapers for every core theme, downloaded only when you ask.

```sh
aphotic plugin install wallpaper-packs
aphotic wallpaper fetch          # the active theme
aphotic wallpaper fetch --all    # every installed theme
aphotic wallpaper packs          # what each pack covers
```

Files land in the theme's own folder under `~/.config/awww/<theme>/`, so the
picker, the cycle and `aphotic wallpaper -f` see them with no extra step. A
file is kept only when its sha256 matches the pack. Running fetch again skips
what is already there.

## Packs

- `classic` holds the wallpapers Aphotic shipped in its theme folders before
  they moved here. It downloads from the Aphotic repo at a pinned commit.
- `community` holds picks from an MIT-labelled community collection, linked in
  `packs/community.toml`. Credit belongs to the original artists; the
  collection names none per image. Open an issue to have an image removed.

## How the community picks were made

`tools/sort_pack.py` scores every image against each theme's palette in Lab
space. `tools/curation.toml` holds that ranking after a pass by eye that
removed mismatches and franchise art. `tools/build_packs.py` writes the pack
files from pinned commits and leaves out anything smaller than 1880x1000.

On a 21:9 screen Aphotic prefers the ultrawide images in a theme when it picks,
cycles or randomizes.
