# Deep Signal Screensaver

An idle screensaver. The wordmark resolves out of noise like a signal
surfacing from deep water, over a sparse drift of bioluminescent
particles, in whatever colours the current theme is using.

## Requires

A shell that hosts the `fullscreen-overlay` surface (manifest v3.5). On
an older shell `aphotic plugin install` reports the surface as unhosted
rather than installing it to nothing.

## What it costs

Nothing when it is not showing. The surface is built when the idle
timeout fires and destroyed on the first key or pointer event, so an
active desktop carries no screensaver window at all.

While it is showing, one 12 Hz timer drives everything. Nothing animates
a property, so the surface repaints twelve times a second rather than at
the display rate, not the 60 to 165 a QML animation would hold it at. The
mark never stops breathing while it is up -- a screensaver that settles
into a still logo is not a screensaver -- so the timer runs for as long as
the surface exists and stops dead when it is torn down.

Depth effects off (Settings > Appearance) drops the particles and leaves
the mark, which is the cheapest way to run it.

## Setting the timeout

Settings > Power & Security > Screensaver when idle. The screensaver
timeout is separate from the lock timeout; dismissing the screensaver is
real input, so it resets the lock countdown too.

## Changing what it shows

```sh
aphotic screensaver text "STATION 7"     # spell out something else
aphotic screensaver import photo.png     # render an image as ASCII
aphotic screensaver import photo.png 120 # ... at 120 columns
aphotic screensaver show                 # print what it shows now
aphotic screensaver reset                # back to the wordmark
```

All of these write `~/.config/aphotic/branding/screensaver.txt`, which the
shell watches. Nothing needs restarting.

Text with a line break in it is treated as art: no letter spacing, sized
to fit its widest line. Everything else is treated as a wordmark and set
on one wide line.

## Removing it

`aphotic plugin remove deep-signal` takes the surface, the command and the
QML module with it. The branding file is left alone, because you wrote it.
