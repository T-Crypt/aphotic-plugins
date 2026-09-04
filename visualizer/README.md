# Spectrum

Inspired by [quickshell-visualizer](https://github.com/coderPriyanshu007/quickshell-visualizer)
by [coderPriyanshu007](https://github.com/coderPriyanshu007), rewritten
from scratch for Aphotic's plugin contract.

An audio spectrum that sits on the wallpaper, under every shell surface,
painted in whatever accent the current theme resolves to. It draws while
sound is playing and it draws nothing at all the rest of the time.

## What it does

Registers one `overlay` surface (manifest v3.4): a 1920x120 layer-shell
window anchored to the bottom of each screen, on `WlrLayer.Bottom`, so
it can never cover the bar, the notch or a popout. 96 frequency bands
run left to right, low to high, with the bar colour crossfading from the
theme's primary accent to its tertiary. Nothing here is configurable
from Settings, and nothing here is gated: no `requires_layer`, no
`requires_data`, so it is available on every install.

The host masks its window to whatever the plugin names in `maskItem`,
and that region is the part that stops taking desktop clicks. This one
names a zero-sized item, so the region is empty and the strip along the
bottom of the screen passes every click through to the desktop. There is
nothing in a spectrum to click. Masking to the bars would give you a
dead zone that grows and shrinks with the music.

`cava` does the FFT. It runs as a subprocess writing one line of ASCII
bar values per frame, which the shell reads through `Process` +
`SplitParser`, the same way it talks to every other line-emitting tool.

## Idling, which is most of the point

An overlay is always on screen, so an always-on overlay is an always-on
repaint. Aphotic already paid for that once: a single infinite opacity
animation held four shell windows at the display refresh rate forever
and cost around nine points of idle GPU (`DepthFx.qml` carries the
measurements). This plugin has no unconditional animation and no timer
that runs when there is nothing to show.

Four gates, coarsest first:

| Gate | Condition | What stops |
|---|---|---|
| Mounted | A surface holds a `SpectrumWatch` | Everything. No process, no timer, no frame |
| Reachable | Session unlocked, sink unmuted, and either a PipeWire playback stream exists or a player reports playing | The cava process |
| Quiet | 900 ms with every band under the noise floor | Drawing. The bars fade out and `visible` goes false, so the scene graph has no nodes to update |
| Dozing | 12 s quiet | The cava process again, this time mid-playback. It comes back for 1.5 s in every 7.5 s to check |

Waking never waits on a poll. The first frame above the noise floor
clears both the quiet and the dozing state on the spot, and a new
PipeWire playback stream or an MPRIS player entering Playing pulls the
plugin out of a doze before its next sample window.

That stream test counts only nodes whose `media.class` says Output, and
the reason is cava. cava is a PipeWire client, so its capture node joins
the same node list the plugin watches. Count it and you get a loop:
stopping cava changes the list, the change reads as news, the news
starts cava, and starting it changes the list again. The visualiser
wakes itself out of every doze it enters, and cava cycles for as long as
the session runs. The filtered count does not move when cava does, which
is what breaks the loop.

Under all of it sits one 500 ms clock, borrowed from `DepthFx`'s shared
low-rate pulse, and it runs only while a spectrum is wanted.

`cava` carries its own version of the same idea: `sleep_timer = 3` in
`config/cava.conf` makes it stop sampling and stop writing frames when
its input goes idle, which is what a suspended PipeWire sink looks like.
The plugin gating sits on top of that, not instead of it.

### Measured

A real layer-shell surface on a real screen, `QSG_RENDER_TIMING=1`
counting renderer passes, silence for 25 s and then an 8 s tone:

| Phase | Renderer passes per second |
|---|---|
| First second, initial paint | 3 |
| Silence, seconds 2-25 | 0 |
| Tone playing | 57-59 |
| Silence resumes | 0, from the next second on |

571 passes over the whole 40 s run, and all but three of them were
frames that had a new spectrum to draw.

The `cava` side, sampled off `/proc`:

| State | Cost |
|---|---|
| `cava` reading a live but silent source | 0.45% of one core, continuously |
| Nothing playing, no playback stream at all | no process, no timer, nothing to measure |
| A playback stream sitting idle | `cava` for 1.5 s in every 7.5 s, so a fifth of the above |

The shell process itself measured below the 10 ms clock resolution over
a 60 s window in every state, matching an empty `PanelWindow` of the
same geometry.

## Rendering

96 plain `Rectangle`s, one per band, bottom anchored, geometry-only per
frame.

A `Canvas` would rasterise the whole 1920x120 strip on the CPU and
re-upload it as a texture 60 times a second, which is the expensive way
to draw 96 rectangles. A `ShaderEffect` would be cheaper still, but Qt 6
wants a `.qsb` built ahead of time and a plugin loaded from a `file://`
URL has no build step to produce one. Scene-graph nodes it is, and they
stop changing the moment the source goes quiet.

## Requirements

`cava`. Aphotic ships it in the base profile, so a normal install
already has it; `aphotic plugin list` reports it as a missing binary if
yours does not.

## Install

```sh
aphotic plugin install visualizer
```

Or from Settings, Plugins.

## Configuration

`config/cava.conf` is a stock cava config and everything in it is
cava's own vocabulary. Two values are load-bearing for the plugin:

- `bars = 96` has to match `CavaSpectrum.barCount`
- `ascii_max_range = 1000` is the divisor the parser normalises against

`sleep_timer`, `noise_reduction`, `framerate` and the cutoff
frequencies are yours to change.

## Removing it

```sh
aphotic plugin remove visualizer
```

It owns no config keys and writes nothing outside its own install
directory, so removing it leaves nothing behind.
