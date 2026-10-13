# Remote Desktop (xfreerdp)

An RDP session into a Windows machine, driven by one profile.

A pane in **Settings → Network**, two command-palette actions and an
`aphotic xfreerdp` command, all reading the same settings file. The
session is a normal tiled window: it tiles, it moves, `SUPER + SHIFT + F`
fullscreens it, and wheel-over-window workspace flipping keeps working
because nothing about it is special-cased.

- **One profile, not an argument list.** The host, the user, the security
  mode, the audio devices, the camera, the starting resolution and the
  window class live in a settings file the pane writes. `aphotic xfreerdp
  connect` builds the argv from it, and `aphotic xfreerdp connect
  --dry-run` prints that argv without connecting, so you can see exactly
  what would run.
- **The Windows key gets through.** `-grab-keyboard` is on by default, so
  the remote session sees `SUPER` instead of the compositor eating it.
  Turn it off in the pane if you would rather keep `SUPER` local.
- **Microphone and camera.** The session carries your local microphone and
  requests the remote camera channel, which is the reason this is
  `xfreerdp3` and not a Remmina profile: Remmina's RDP plugin cannot ask
  for `rdpecam`.
- **Press once to focus, twice to reconnect.** A press focuses a session
  that is already open and starts one only if it is not, the same
  behaviour the hand-written launcher had.
- **No password anywhere.** The session prompts for it through a
  `zenity` dialog pointed at by `FREERDP_ASKPASS`. Nothing is stored, and
  nothing reaches the command line where `ps` would show it: a password
  flag in the extra arguments is refused, with the reason.

## The settings file

`~/.config/aphotic/plugins/xfreerdp/settings.json`, written by the pane
and read by `aphotic xfreerdp`. A missing file, or a file with only some
of these keys, behaves exactly like the defaults below:

```json
{
  "host": "",
  "port": 3389,
  "user": "",
  "sec": "nla",
  "cert": "ignore",
  "mic": { "enabled": true, "device": "" },
  "speaker": { "device": "" },
  "camera": { "enabled": true },
  "resolution": { "mode": "dynamic", "width": 1920, "height": 1080 },
  "window": {
    "class": "work-rdp",
    "grab_keyboard": true,
    "auto_reconnect": true,
    "gfx": "AVC420",
    "workspace": "none",
    "fullscreen": false
  },
  "extra": ""
}
```

Worth knowing:

- `user` is `DOMAIN\user` as the machine expects it. Leave it empty and
  the session asks.
- `sec` is `nla`, or `aad` for an Entra-joined machine that refuses NTLM
  and sends you to a browser sign-in instead.
- `resolution.width`/`height` are the **starting** size and are always
  passed. `mode` is `dynamic` (the session follows the tiled window) or
  `fixed`.
- `window.class` is what window rules match on. The default is the class
  the hand-written launcher used, so existing rules keep working.
- `window.workspace` pins the session to a workspace id or to
  `special:rdp`. `none` leaves the window where it opens, which is what
  keeps workspace flipping normal.
- `window.fullscreen` is off by default so `SUPER + SHIFT + F` stays the
  manual entry.
- `extra` is appended to the argv as typed, split on spaces. A flag that
  carries a password is refused with an error instead of being passed on:
  `/p:`, `-p:`, `+p:`, `/pth:`, `/assistance:`, and a credential inside a
  `/gateway:` or `/proxy:` argument. The session asks for the password, so
  it never turns up in `ps`.

## The keybind

The manifest declares `SUPER + ALT + P` as a `[keybind]` for the connect
action. **On Aphotic 2.0.8 and earlier there is no host for that
capability**: the plugin installs with a warning, the keybind stays dark,
and everything else (the pane, both actions, the command) works. The
combo appears in `hyprctl binds -j` from Aphotic 2.0.9 on, and only while
this plugin is installed, enabled and past its gate.

Until you have updated, point your own config at the command instead. In
`~/.config/hypr/custom.lua`:

```lua
hl.bind("SUPER + ALT + P", hl.dsp.exec_cmd("aphotic xfreerdp connect"), { description = "Toggle RDP" })
```

The second argument has to be a dispatcher (`hl.dsp.exec_cmd(...)`), not a
bare command string: Hyprland wants an `HL.Dispatcher` there, and the same
form is what the shell generates for its own binds.

That is one bind replacing the window-find-and-launch block, and it is
local to your machine: nothing here writes to a compositor config.

## Requirements

- `xfreerdp3`, from the `freerdp` package, and `zenity` for the password
  dialog. Both are declared in the manifest, so `aphotic plugin install`
  installs what is missing.
- A Hyprland session, for the window behaviour. `aphotic xfreerdp
  connect --dry-run` works without one, and the pane reports the session
  state as unknown rather than guessing.

## Install

```sh
aphotic plugin install xfreerdp
```

## Commands

```sh
aphotic xfreerdp connect [--dry-run]   # start it, or focus it if it is up
aphotic xfreerdp status                # running, not-running or unknown
aphotic xfreerdp disconnect            # close the window
```
