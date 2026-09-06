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

Everything you need is one image and one small JSON file:

```
~/.config/aphotic/pets/nautilus/
  pet.json
  sheet.png
```

The picker in **Settings → Appearance → Desktop Pet** lists that folder
whenever the pane opens, so a pet you add while Settings is already up
wants one trip out of the pane and back. Both files are watched, so
editing a pet you have already selected takes effect without restarting
the shell. A folder sharing a name with a built-in never wins; rename
it.

That `pet.json` is a pet's own manifest. It is not the same file as
`~/.config/aphotic/plugins/pet/settings.json`, which is this plugin's own
config and says which pet is selected and where you dragged it. Two
different files, one directory apart.

Five ways to get that image, fastest first.

### A note on WebP

PNG, JPEG, GIF and SVG are all Qt reads on its own, and the two sources
below both export WebP. Aphotic installs `qt6-imageformats` for exactly
that reason, so on a current install a WebP sheet works with nothing to
do.

On an install predating that package, WebP fails with `Unsupported image
format`, the pet falls back to a built-in, and nothing else is logged.
Two ways out. Add the decoder:

```sh
sudo pacman -S qt6-imageformats
```

Or convert the sheet once and point `sheet` at the result:

```sh
ffmpeg -i spritesheet.webp -pix_fmt rgba spritesheet.png
```

Keep `-pix_fmt rgba` there, or you lose the transparent background and
your pet arrives in a white box.

### 1. Take one from Petdex

[Petdex](https://petdex.dev/) is a public gallery of a few thousand
animated pets people have drawn for coding agents. Pulling one down needs
Node's `npx`, which Aphotic does not install:

```sh
npx petdex install boba
```

It lands in `~/.codex/pets/boba/`. Copy the folder across, and that is
the whole job:

```sh
cp -r ~/.codex/pets/boba ~/.config/aphotic/pets/boba
```

Nothing to edit. Petdex writes its own manifest, with `id`,
`displayName` and `spritesheetPath` in it rather than the keys below, and
this plugin reads that shape directly. The cell size is divided out of
the image rather than assumed, so a sheet exported at another resolution
works too, and the drawn height is set near the built-in pets.

You only need a manifest of your own to override that, which is worth
doing when a pet's own poses suit the four states better than the
defaults. The sheets are a fixed shape: cells in an 8 by 9 grid, and the
nine rows run:

| Row | State | Frames |
|---|---|---|
| 0 | idle | 6 |
| 1 | running-right | 8 |
| 2 | running-left | 8 |
| 3 | waving | 4 |
| 4 | jumping | 5 |
| 5 | failed | 8 |
| 6 | waiting | 6 |
| 7 | running | 6 |
| 8 | review | 6 |

Four of those nine are what this plugin plays. Writing them out by hand
gets you the same result as leaving the folder alone:

```json
{
  "format": 1,
  "name": "Boba",
  "sheet": "spritesheet.png",
  "frame": { "width": 192, "height": 208 },
  "scale": 0.4,
  "fps": 8,
  "smooth": true,
  "states": {
    "idle":  { "row": 0, "frames": 6 },
    "walk":  { "row": 1, "frames": 8 },
    "react": { "row": 3, "frames": 4 },
    "sleep": { "row": 5, "frames": 1 }
  }
}
```

Row 2 goes unused, because this plugin mirrors row 1 when the pet walks
left. Row 4 is a hop if you would rather a click made your pet jump than
wave. Nothing in that format is a sleeping pose, so `sleep` borrows one:
row 5 is the pet's failure pose, which usually droops with its eyes half
shut and reads as asleep. Row 6 is the alternative where it does not, and
some pets have neither, which is the main reason to write the manifest
out yourself.

`scale` is the other reason. A 192 by 208 cell drawn at full size is a
small window, not a pet, so left alone this plugin scales the art to
about 96 pixels tall. Set `scale` to pick your own size. Painted art
wants `smooth: true`; leave it `false` only for pixel art.

Petdex sheets are usually `spritesheet.webp`, which a current Aphotic
decodes. See the WebP note above if yours does not.

### 2. Generate one in ChatGPT

Petdex's own pets come from the **Hatch Pet** skill in the ChatGPT
desktop app. Install it from the Skills menu, type `/pet`, and describe
what you want. It draws all nine states and writes them to
`~/.codex/pets/<name>/`, at which point you are back at step 1: copy the
folder and replace the `pet.json`.

Be specific in the description. A silhouette, a colour, a material and a
mood get you much further than a noun.

### 3. Ask any image model for a sheet

You do not need either of those. Any model that draws will do it if you
tell it the grid, and asking for this plugin's own four rows saves you
the mapping:

> A sprite sheet for a desktop pet, PNG with a fully transparent
> background. Grid: 8 columns by 4 rows, every cell exactly 96 by 96
> pixels, final image 768 by 384. One frame per cell, no padding, no
> gutters, no grid lines, no captions, nothing drawn outside a cell.
>
> Row 0, 6 frames: standing still, breathing, blinking on the last two.
> Row 1, 8 frames: a walk cycle travelling right that loops cleanly.
> Row 2, 5 frames: a happy hop, played once and returning to standing.
> Row 3, 1 frame: asleep, eyes closed, the rest of the row empty.
>
> The character faces right in every frame, keeps the same size, and
> stands on the same baseline throughout. Subject: a small brass
> deep-sea diving helmet with stubby legs.

Then:

```json
{
  "format": 1,
  "name": "Helmet",
  "sheet": "sheet.png",
  "frame": { "width": 96, "height": 96 },
  "scale": 1,
  "fps": 8,
  "smooth": true,
  "states": {
    "idle":  { "row": 0, "frames": 6 },
    "walk":  { "row": 1, "frames": 8 },
    "react": { "row": 2, "frames": 5 },
    "sleep": { "row": 3, "frames": 1 }
  }
}
```

Image models are bad at exact grids. Open the result, measure one cell,
and set `frame` to what you actually got rather than what you asked for.
If the character drifts in size between frames it will bounce as it
walks, which is worth one more attempt at the prompt.

Most models will not give you a transparent background on the first try.
Ask again, or key the background out afterwards.

### 4. Start from a ripped game sheet

[The Spriters Resource](https://www.spriters-resource.com/) archives
sprite sheets ripped from thousands of games, already PNG with
transparent backgrounds, so nothing needs converting. Search for a
character, open its sheet, save the PNG.

What you will not get is a grid. Rips are packed however the game packed
them: mixed cell sizes, irregular gutters, animations running down a
column instead of across a row. So there is a step between download and
`pet.json`, in whatever editor you have:

1. Find one animation you want as `idle` and one as `walk`. Four to eight
   frames each is plenty.
2. Decide one cell size big enough for the largest frame in either.
3. Paste each frame into a fresh transparent image on that grid, one
   state per row, packed from column 0, no gutters.
4. Add a `react` row and a single `sleep` frame if the rip has anything
   that suits. Both fall back to `idle` if you skip them.

Keep every frame of a row on the same baseline while you paste, or the
pet bobs as it walks. The layout rules below are the same ones a
hand-drawn sheet follows.

These are ripped game assets. Keep them to your own desktop.

The same goes for packs that ship one sheet per animation, like the CC0
AutoSprite library: a folder of `<name>-idle.png`, `<name>-walk.png` and
a JSON of frame rectangles beside each. This plugin reads one sheet per
pet, with a state on each row, so those need combining into a single
image before any of it applies. The picker draws a folder it cannot read
as a broken image rather than leaving you to find out on the desktop.

### 5. Draw it yourself

The layout is the same whether you draw it, paste it or prompt for it.
One image laid out as a strict grid: every cell the same size, the grid
starting at the top-left pixel, no padding, margin or gutter anywhere.
The plugin finds a frame by multiplying, so a one-pixel border shifts
every frame after the first.

Each state owns a row. Each frame of that state is a cell across it,
starting at column 0. Rows may be shorter than each other, and two states
may share a row.

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
- **Stand on the same line in every frame**, measured from the cell's
  bottom edge rather than from your pixels. A frame that sits two pixels
  higher than its neighbours makes the pet bob as it walks.
- **Keep the cell tight.** The cell is also the click target and the
  window's input mask, so transparent padding around the pet is desktop
  you can no longer click through.
- **Keep the pet horizontally centred in the cell**, or it appears to
  jump sideways when it turns around.

Aseprite, Libresprite and Piskel all export a sheet like this directly.

Sizing: this plugin draws one cell at a time and the surface is the whole
screen, so nothing clips a big pet. A creature much over 200 pixels tall
stops reading as a pet and starts reading as a window.

Pixel art wants an integer `scale` and `smooth: false`, or the shell
blurs it back into mush. A sheet you are scaling *down*, like the 192 by
208 cells the two routes above produce, wants `smooth: true` instead;
nearest-neighbour on a downscale eats whole pixel rows.

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
| `format` | Must be `1`. A manifest without it is read as a generator's if it has a `spritesheetPath`, and rejected otherwise. |
| `name` | Shown as the pet's name. |
| `sheet` | The image beside `pet.json`. A bare filename: no slash, no leading dot, no traversal. PNG, JPEG, GIF, SVG, and WebP where the decoder is installed. |
| `frame.width` / `frame.height` | One cell of the sheet, in source pixels. Both must be above zero. |
| `scale` | Draw scale. Use an integer for pixel art. Defaults to `1`. |
| `fps` | Default playback rate for every state. Capped at 12, the clock's own rate. Defaults to `8`. |
| `smooth` | Filter the image when scaling. Leave it `false` for pixel art. |
| `states` | One entry per state. `idle` is required; the rest fall back to it. |

Each state takes `row` (which row of the sheet, counting from 0),
`frames` (how many cells across, starting at column 0), and an optional
`fps` of its own.

The plugin draws one cell at a time by offsetting the image behind a
clipping viewport, so switching frames costs two coordinate writes and no
decode.

The pet faces right in the sheet. It is mirrored when it walks left, so
draw one direction only.

### How the states are used

- `idle` frame 0 is the still picture between beats. The remaining
  `idle` frames play once through as the pet's blink or fidget, and are
  also what it shows while you are holding it.
- `walk` loops while the pet crosses its patch.
- `react` plays once when you click.
- `sleep` frame 0 is the still picture while the pet naps.

### When your pet does not show up

A built-in draws instead. That fallback is unconditional and silent, so
work down this list:

| Symptom | Cause |
|---|---|
| A built-in, not your pet | `pet.json` was rejected. Check `format` is the number `1`, `states.idle` exists, and `frame.width` and `frame.height` are both above zero. |
| A built-in, manifest looks fine | The image did not decode. Check `sheet` names the file exactly, with no path in front of it. A WebP on an install older than `qt6-imageformats` lands here. |
| A broken-image tile in the picker | The manifest is neither this plugin's shape nor a generator's. A pack with one sheet per animation lands here; it needs combining into one image first. |
| The folder is missing from the picker | It is not directly under `~/.config/aphotic/pets/`, or its name starts with a dot. |
| Right pet, wrong frames | `frame.width` or `frame.height` does not match the real cell. Measure the sheet and divide by the column and row count. |
| Bits of the next frame at the edges | The sheet has padding or gutters between cells. This plugin assumes none. Re-export without them. |
| A blurry pet | `smooth: true` on pixel art, or a fractional `scale`. |
| A pet that jitters as it walks | The character is not on the same baseline in every frame of `walk`. |
| Nothing at all, anywhere | The plugin is disabled, or safe mode is on. |

## Configuration

`~/.config/aphotic/plugins/pet/settings.json`, which is this plugin's own
config and nothing to do with the `pet.json` inside a pet's folder. The
settings pane writes it; you can too.

It was called `pet.json` until 1.2.1, which put two files of that name
one directory apart. An old one is read once, written back under the new
name, and then ignored. Delete it when you see the new file appear.

| Key | Meaning |
|---|---|
| `pet` | A built-in id (`miko`, `angler`, `clip`, `claude`) or a folder name under `~/.config/aphotic/pets/`. `default` means whichever built-in ships as the default. |
| `x` / `y` | Where the pet sits, as a fraction of the screen from 0 to 1. The centre of the creature, not its corner. |
| `roam` | How far it wanders either side of that, in pixels. `0` pins it. |
| `locked` | Stops the drag. Clicking still works. |
