# Desktop Pet

A small creature that lives at the bottom of the desktop, above the
wallpaper and below every shell surface. It stands still most of the
time, wanders its own patch every so often, blinks when you put the
cursor on it, and hops when you click it. After six quiet minutes it
falls asleep until you touch it again.

Ships with a built-in pet, so it does something the moment you install
it. Custom pets are sprite sheets you drop in a folder.

## Install

```sh
aphotic plugin install pet
```

No layer required. This plugin declares no `requires_layer` and no
`requires_data`, so it works on every install, minimal or full.

## What it costs

Nothing while the pet is standing still, which is where it spends
almost all of its life.

The shell's idle-GPU regression (`E2-08`) came from infinite QML
animations. An animation ticks once per frame, so a window holding a
running one repaints at the display rate forever whether or not the
picture changed. This plugin runs no animation on a property. Motion is
integrated from one shared 12 Hz timer, `PetClock`, that:

- is a singleton, so two monitors share one timer rather than one each,
- runs only while at least one pet has something to move, and stops the
  moment the last one settles,
- stops while the session is locked.

A beat timer wakes each pet every 9 to 24 seconds and picks a short walk
or one blink. Both take a couple of seconds of 12 Hz ticks and then let
the clock stop. Between beats the scene graph is untouched and the
window submits no frames.

## Clicking it

The window is masked to the surface the manifest declares, so the
declared box is also the part of the desktop that stops taking clicks.
It is kept close to the pet for that reason: 240x160, of which the pet
itself is about 86x78. The click handler covers the pet, not the box.

## Custom pets

A pet is data, never code. There is no way to import QML here, on
purpose: third-party QML would run inside the shell's own process with
the shell's own reach, and that trust question is open.

Put your pet in `~/.config/aphotic/pets/<name>/`:

```
~/.config/aphotic/pets/nautilus/
  pet.json
  sheet.png
```

Then name it in `~/.config/aphotic/plugins/pet/pet.json`:

```json
{ "pet": "nautilus" }
```

Both files are watched, so an edit takes effect without restarting the
shell. A folder called `default` is picked up with no config file at
all.

### `pet.json`

```json
{
  "format": 1,
  "name": "Nautilus",
  "sheet": "sheet.png",
  "frame": { "width": 48, "height": 40 },
  "scale": 2,
  "fps": 8,
  "smooth": false,
  "states": {
    "idle":  { "row": 0, "frames": 4 },
    "walk":  { "row": 1, "frames": 6 },
    "react": { "row": 2, "frames": 5 },
    "sleep": { "row": 3, "frames": 1 }
  }
}
```

| Key | Meaning |
|---|---|
| `format` | Must be `1`. Anything else is rejected. |
| `name` | Shown as the pet's name. |
| `sheet` | The image beside `pet.json`. A bare filename: no slash, no leading dot, no traversal. |
| `frame.width` / `frame.height` | One cell of the sheet, in source pixels. Both must be above zero. |
| `scale` | Draw scale. Use an integer for pixel art. Defaults to `1`. |
| `fps` | Default playback rate for every state. Capped at 12, the clock's own rate. Defaults to `8`. |
| `smooth` | Filter the image when scaling. Leave it `false` for pixel art. |
| `states` | One entry per state. `idle` is required; the rest fall back to it. |

Each state takes `row` (which row of the sheet, counting from 0),
`frames` (how many cells across, starting at column 0), and an optional
`fps` of its own.

The sheet is one image laid out as a grid: each state owns a row, each
frame of that state is a cell across it. The plugin draws one cell at a
time by offsetting the image behind a clipping viewport, so switching
frames costs two coordinate writes and no decode.

The pet faces right in the sheet. It is mirrored when it walks left, so
draw one direction only.

The surface is 240x160 and core never resizes it, so a frame larger than
that gets clipped by the window. Keep `frame.width` times `scale` under
about 120 to leave the pet room to walk, and `frame.height` times `scale`
under about 130.

### How the states are used

- `idle` frame 0 is the still picture between beats. The remaining
  `idle` frames play once through as the pet's blink or fidget.
- `walk` loops while the pet crosses its patch.
- `react` plays once when you click.
- `sleep` frame 0 is the still picture while the pet naps.

Anything the manifest gets wrong falls back to the built-in pet: a
missing folder, a rejected manifest, an image that will not decode. The
surface is never blank.

## Configuration

`~/.config/aphotic/plugins/pet/pet.json`

| Key | Meaning |
|---|---|
| `pet` | Folder name under `~/.config/aphotic/pets/`. Defaults to `default`, which falls back to the built-in pet when that folder is absent. |

## The built-in pet

An anglerfish, drawn as vector paths off the live palette rather than
shipped as an image, so it retints with the theme. Its body takes the
primary accent, its fins the tertiary, and its illicium glows brighter
for a moment when you click it. Front-heavy silhouette, a toothed
mouth and a few spiny dorsal rays are what read as anglerfish rather
than a generic fish at this size -- the previous version had the lure
and still looked like a regular fish.
