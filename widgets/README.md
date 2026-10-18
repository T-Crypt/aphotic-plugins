# Desktop Widgets

Transparent widgets on the desktop, drawn in the Signal style: dark glass,
hairline borders and one accent colour from your theme.

## Use

- **SUPER+ALT+W** (or the command palette, or Settings > Appearance >
  Desktop Widgets) turns edit mode on and off.
- In edit mode, **Add widget** opens the catalog. Drag a widget to move it,
  drag its corner to resize it, and use the tune button (or a double-click)
  to open its settings. Escape or **Done** leaves edit mode.
- Every widget can have glass, a hairline or no background, its own glass
  opacity and its own accent.

The empty desktop between widgets still takes your clicks and its menu.
Widgets on a screen with a fullscreen window stop drawing and updating
until it leaves; turn that off in the settings pane.

## Catalog

| Category | Widgets |
|---|---|
| Clocks | Digital, analog, word clock, world clock, ring clock, stacked, binary, progress of the day |
| Date | Date stack, date banner, month calendar, week strip, countdown |
| Media | Now playing, media pill, album cover, spinning disc |
| System | CPU, memory, GPU, disks, network, resources, battery, host, top processes |
| Weather | Weather, forecast, weather pill |
| Productivity | Timer, stopwatch, Pomodoro, note, to-do, daily counter, quote |
| Utility | Launcher, quick toggles, Bluetooth devices, photo, greeting |
| Aphotic | Agent sessions, local AI engines, signal line |

## Files

Layout, settings and what you typed into notes and lists live in
`~/.config/aphotic/plugins/widgets/layout.json`. Removing the plugin
leaves that file; delete it to start over.

## Needs

Core's overlay `maskRegion` and `wantsKeyboard` support. On an older shell
the widgets still draw, but the mask covers their bounding area and notes
cannot take typing.
