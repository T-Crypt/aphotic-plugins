# iOS Development

Build and run iPhone apps from this machine. The toolchain compiles a Swift
package into an iOS app, signs it, installs it on a phone over USB and
launches it, all from the shell: a command, a workspace plane, a notch tile,
and one keybind.

Gated on the `dev` layer. Without that layer the plugin is not offered at
all, and with it the plugin is still an explicit install.

## What you get

| Action | How |
|---|---|
| Report every prerequisite and how to fix it | `aphotic ios doctor` |
| Install the toolchain, one confirmed step at a time | `aphotic ios setup` |
| Scaffold an app that is ready to run | `aphotic ios new MyApp` |
| Build, install and launch on a connected phone | `aphotic ios run`, or SUPER + ALT + I |
| Stop a detached run | `aphotic ios stop` |
| List connected phones | `aphotic ios devices` |
| Show the installed versions and the Xcode they need | `aphotic ios toolchain` |
| See the toolchain, devices and session in one place | the Workspace plane |
| See the phone and session at a glance | the iOS notch tile |

## The two installs

`aphotic ios setup` installs four things and stops before the fifth.

It installs, each after asking:

- `usbmuxd`, which talks to the phone over USB.
- `inotify-tools`, which the file-watching half of a later phase needs.
- `xtool`, downloaded as a prebuilt release archive and verified against a
  pinned sha256 before anything is extracted. Extracted rather than
  mounted, because a mounted AppImage needs FUSE and a host with no
  squashfs support cannot mount one.
- `swift-bin` from the AUR, which is about 1 GB.

It never runs sudo, and it never runs without a terminal. Where a package
manager needs privileges, the package manager asks for them and you see it
coming. Without a terminal, setup prints what it would do and stops.

Then it stops, because the fifth thing is not a command. Apple ships the
iOS SDK only inside Xcode, and that download needs a signed-in browser.
`setup` names the Xcode version your Swift needs and tells you what to run
once you have the file:

```
xtool sdk install ~/Downloads/Xcode_27.xip
```

The version pairing is the whole trap. Swift 6.4 needs Xcode 27 and Swift
6.3 needs Xcode 26. A mismatch fails every build with "this SDK is not
supported by the compiler". `aphotic ios toolchain` prints both versions
and the Xcode they need.

## What this phase does not do

Hot reload, the debugger attach with breakpoints and stepping, log
streaming, and shipping an ipa to TestFlight each need the device bridge
that a later phase adds. There is no simulator, no SwiftUI previews, no
Interface Builder and no Instruments, because none of those exist for
Linux.

`xtool dev run` plans, compiles, signs, installs and launches inside one
process, and it reports no phase boundaries. This phase therefore records
a session as running, idle or failed, and does not invent a building phase
it cannot observe.

## Cost at idle

Nothing. The notch tile reads the state file through a `FileView` with
`watchChanges`, which is one inotify watch on one file and no process. The
workspace plane's Loader destroys the pane when its tab is not selected,
which stops its five-second timer for free.

## Files it writes

| Path | Written by |
|---|---|
| `~/.local/share/aphotic/plugins/ios-dev/tools/` | setup, for xtool |
| `~/.local/bin/xtool` | setup, only after it asks |
| `~/.config/aphotic/plugins/ios-dev/config` | setup, and you |
| `~/.config/aphotic/plugins/ios-dev/state.json` | every CLI command |

No shell setting is read or written, so `aphotic plugin remove` leaves
nothing behind in settings.json.
