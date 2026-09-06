# Desktop Pet

A small creature that lives on the desktop, above the wallpaper and below
every shell surface. Drag it anywhere you like. It stands still most of
the time, wanders around wherever you dropped it every so often, blinks
when you put the cursor on it, and hops when you click it. After six
quiet minutes it falls asleep until you touch it again.

Four pets ship with it, all drawn in vector off the live palette so they
wear whatever theme you are running. Custom pets are sprite sheets you
drop in a folder.

## Install

```sh
aphotic plugin install pet
```

No layer required. This plugin declares no `requires_layer` and no
`requires_data`, so it works on every install, minimal or full.

## The pets

| Pet | What it is |
|---|---|
| **Miko** | A shrine girl. The default. Hair takes the primary accent, hakama and ribbon the tertiary. |
| **Aphotid** | The anglerfish. Front-heavy, toothed, lit by its own lure. |
| **Clip** | A bent paperclip with eyebrows. |
| **Claude** | An eleven-ray starburst that blinks and rolls a little as it walks. |

Pick one in **Settings → Appearance → Desktop Pet**. The picker draws the
real pets rather than icons of them, because the point of a built-in is
that it wears the current theme.

Skin and robe on Miko are the two colours not taken from a palette role.
A role that lands on grey or green stops reading as a person, and a robe
taken from whatever contrasts with the hair goes black under half the
themes, which on a dark wallpaper leaves a head and a skirt with nothing
between them. Both are fixed warm tones with a little of the accent
tinted through.

## Moving it

Press and drag. Release drops it, and where you dropped it is saved as
normalised coordinates, so the same spot lands in the same place if you
change resolution or plug in a different monitor.

Press and release without moving is still a click, so poking the pet has
not gone anywhere. **Lock in place** in the settings pane stops the drag
without stopping the click. **Wandering** sets how far it strays from
where you put it, and **Stay put** pins it there.

The pet is on the bottom layer, so a window covers it. That is the point:
an ambient thing does not sit over your work.

## What it costs

Nothing while the pet is standing still, which is where it spends almost
all of its life.

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
the clock stop. Between beats the scene graph is untouched and the window
submits no frames. Dragging drives no clock at all; the position comes
straight off the pointer events.

The one cost that is not zero at idle is the surface itself. This plugin
declares `anchor = "free"`, which asks core for the whole usable output
instead of a box on an edge, because the pet is dragged around it and a
fixed box would be the thing being dragged. That is a screen-sized
transparent layer surface for the compositor to blend. It draws nothing
and takes no input outside the pet, but it is there.

## Clicking it

The window is masked to the creature, so everywhere the pet is not is
still the desktop's to click. That mask is what makes a screen-sized
surface tolerable: without it, a free overlay would swallow every click
on the wallpaper.

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

The folder shows up in the settings picker as soon as it exists. You can
also name it directly in `~/.config/aphotic/plugins/pet/pet.json`:

```json
{ "pet": "nautilus" }
```

Both files are watched, so an edit takes effect without restarting the
shell. A folder sharing a name with a built-in never wins; rename it.

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

Nothing clips a big pet any more now that the surface is the whole
screen, but a creature much over 200 pixels tall stops reading as a pet
and starts reading as a window.

### How the states are used

- `idle` frame 0 is the still picture between beats. The remaining
  `idle` frames play once through as the pet's blink or fidget, and are
  also what it shows while you are holding it.
- `walk` loops while the pet crosses its patch.
- `react` plays once when you click.
- `sleep` frame 0 is the still picture while the pet naps.

Anything the manifest gets wrong falls back to a built-in: a missing
folder, a rejected manifest, an image that will not decode. The surface
is never blank.

## Configuration

`~/.config/aphotic/plugins/pet/pet.json`. The settings pane writes it;
you can too.

| Key | Meaning |
|---|---|
| `pet` | A built-in id (`miko`, `angler`, `clip`, `claude`) or a folder name under `~/.config/aphotic/pets/`. `default` means whichever built-in ships as the default. |
| `x` / `y` | Where the pet sits, as a fraction of the screen from 0 to 1. The centre of the creature, not its corner. |
| `roam` | How far it wanders either side of that, in pixels. `0` pins it. |
| `locked` | Stops the drag. Clicking still works. |
