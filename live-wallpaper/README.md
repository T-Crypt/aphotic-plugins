# Live Wallpapers

Plays video wallpapers on the Aphotic desktop.

Aphotic's base shell already lists video files in the wallpaper picker and
applies them: it extracts one frame with ffmpeg, shows that still, and
derives the palette from it. This plugin adds the motion on top, drawing a
looping video over that same still through the `background` surface kind
(manifest v3.8).

That split is deliberate. Video decode runs for as long as your desktop is
visible, which is the one genuinely expensive thing in this plugin, so it
stays opt-in. Remove the plugin and your video wallpapers keep working as
stills rather than disappearing.

## Requirements

- `ffmpeg`, for the poster frame and the picker thumbnail. Aphotic's base
  profile already installs it.
- `qt6-multimedia`, for playback.

## Supported formats

`.mp4`, `.webm`, `.mov`, `.mkv`, `.m4v`. Drop one into any theme directory
under `~/.config/awww/<theme>/` and it shows up in the picker with a video
badge.

## Playback policy

Both defaults exist to keep the cost near zero when you would not see the
result anyway:

- **Pause on battery** (default on).
- **Pause when covered** (default on) stops playback whenever any window
  sits on the focused workspace. A live wallpaper you cannot see is pure
  cost, and this is what makes the plugin cheap during normal work.
- **Mute** (default on).

All three live under Settings > Appearance > Live Wallpapers.
