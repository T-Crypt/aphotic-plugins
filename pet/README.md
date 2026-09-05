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

So a pet is exactly two files: one PNG sprite sheet and one JSON
manifest describing how to cut it up.

### 1. Make the folder

Put your pet in `~/.config/aphotic/pets/<name>/`. The folder name is what
you select it by, so keep it lowercase and free of spaces, slashes and
dots:

```
~/.config/aphotic/pets/nautilus/
  pet.json
  sheet.png
```

A folder called `default` is picked up with no config file at all. Any
other name has to be selected in `~/.config/aphotic/plugins/pet/pet.json`:

```json
{ "pet": "nautilus" }
```

### 2. Draw the sheet

The sheet is one PNG laid out as a strict grid. Every cell is the same
size, the grid starts at the top-left pixel, and there is no padding,
margin or gutter anywhere -- the plugin finds a frame by multiplying, so
a one-pixel border shifts every frame after the first.

Each state owns a **row**. Each frame of that state is a **cell across
it**, starting at column 0. Rows may be shorter than each other, and two
states may share a row.

```
        col 0     col 1     col 2     col 3     col 4     col 5
row 0  [ idle 0 ][ idle 1 ][ idle 2 ][ idle 3 ]
row 1  [ walk 0 ][ walk 1 ][ walk 2 ][ walk 3 ][ walk 4 ][ walk 5 ]
row 2  [ react0 ][ react1 ][ react2 ][ react3 ][ react4 ]
row 3  [ sleep0 ]
```

Four rules the drawing itself has to follow:

- **Face right.** The pet is mirrored about the cell's centre when it
  walks left, so draw one direction only.
- **Stand on the bottom edge of the cell.** The pet is placed 8 px above
  the bottom of the surface by the cell's bottom edge, not by its
  pixels. Empty rows at the bottom of a cell make the pet hover over the
  wallpaper.
- **Keep the cell tight.** The cell is also the click target and the
  window's input mask, so transparent padding around the pet is desktop
  you can no longer click through.
- **Keep the pet horizontally centred in the cell**, or it will appear to
  jump sideways when it turns around.

### 3. Write `pet.json`

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
| `format` | Must be the number `1`. Anything else, `"1"` included, is rejected. |
| `name` | The pet's name. Read but not yet displayed anywhere. |
| `sheet` | The image beside `pet.json`. A bare filename: no slash, no leading dot, no traversal. |
| `frame.width` / `frame.height` | One cell of the sheet, in source pixels. Both must be above zero. |
| `scale` | Draw scale. Use a whole number for pixel art. Defaults to `1`. |
| `fps` | Default playback rate for every state. Clamped to 1-12, the clock's own rate. Defaults to `8`. |
| `smooth` | Filter the image when scaling. Leave it `false` for pixel art. |
| `states` | One entry per state. `idle` is required; the other three fall back to it. |

Each state takes `row` (which row of the sheet, counting from 0),
`frames` (how many cells across, starting at column 0), and an optional
`fps` of its own. Neither is checked against the size of the image: name
more frames than a row holds and the pet flickers through whatever is to
the right of it, or through nothing.

### How each state is played

- **`idle` frame 0 is the still picture.** It is what the pet shows
  between beats, which is nearly all of the time. No timer runs and the
  window submits no frames.
- **The rest of the `idle` row is the fidget**, played once through when
  a beat picks one and whenever the cursor enters the pet. It runs for
  `frames / fps` seconds or 0.62, whichever is longer, holds on the last
  frame for any remainder, then snaps back to frame 0. Draw the last
  `idle` frame close to frame 0 -- a blink that ends with the eye open --
  or that snap shows.
- **`walk` loops** while the pet crosses its patch, and is cut off at
  whatever frame it has reached when the pet arrives. Make it a seamless
  cycle that survives being interrupted anywhere. The pet moves 34 px per
  second across the surface, so each walk frame covers
  `34 / (scale * fps)` source pixels -- about 2 px at `scale: 2`,
  `fps: 8`. Move the feet by roughly that much per frame and they will
  not skate.
- **`react` plays once** when you click, over `frames / fps` seconds or
  0.9, whichever is longer, then snaps back to idle frame 0. The pet also
  hops up to 16 px during it, which the plugin does for you -- do not
  draw the hop into the frames.
- **`sleep` frame 0 is the still picture** while the pet naps, after six
  quiet minutes. It never animates, so extra `sleep` frames are never
  drawn.

### Sizing

The surface is 240x160 and core never resizes it, so the drawn size --
`frame.width * scale` by `frame.height * scale` -- has to live inside it:

| | Hard limit | Recommended |
|---|---|---|
| `frame.width * scale` | under 224, or the pet never walks | 80-120, to leave a patch worth roaming |
| `frame.height * scale` | 152, or the top is clipped | up to 136, so the click hop has headroom |

The room the pet roams is 240 minus its drawn width, so a wide pet is a
pet that barely moves.

### When your pet does not show up

Every failure falls back to the built-in pet, silently and with nothing
in the shell log: a missing folder, a manifest that will not parse, a
manifest that parses but fails validation, an image that will not decode.
The surface is never blank, which also means a blank-looking anglerfish
is your only error message. Work down this list:

1. **Is the JSON valid?** `python -m json.tool ~/.config/aphotic/pets/<name>/pet.json`. A trailing comma or a `//` comment is enough.
2. **Is `format` the number `1`?** Not `"1"`, not `1.0` in a form that survives as a string.
3. **Is `states.idle` present?** The other three states are optional; `idle` is not.
4. **Are `frame.width` and `frame.height` both above zero**, and numbers rather than strings?
5. **Is `sheet` a bare filename** sitting beside `pet.json`? A path with a `/`, a `\` or a leading `.` is rejected outright.
6. **Does the folder name match** the `pet` key in `~/.config/aphotic/plugins/pet/pet.json`, and does that file itself parse?
7. **Does the PNG actually decode?** `file sheet.png` should say PNG. Qt loads it asynchronously, so the built-in pet also shows for the moment before a large sheet is ready.

Both files are watched, so once a pet is loading, edits to either take
effect without restarting the shell. Creating the folder for the first
time is the exception -- there was no file there to watch, so reload the
shell after adding a new pet.

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
