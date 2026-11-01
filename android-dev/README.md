# Android Development

Turn this machine into an Android development box. One command installs a
pinned Android SDK under the plugin's own data directory, one reports
every prerequisite and how to fix what is missing, and one builds the app
in the current directory, installs it and starts it on a connected device.

This is the first slice, so the plugin ships a CLI only. The UI planes
come later.

## Install

```
aphotic plugin install android-dev
```

## Commands

| Do this | With |
|---|---|
| Report every prerequisite and how to fix it | `aphotic android doctor` |
| Download and install the SDK pack | `aphotic android setup` |
| List connected devices | `aphotic android devices` |
| Build, install and launch the app here | `aphotic android run [dir]` |
| Print the SDK state in one line | `aphotic android status` |
| Print every path the plugin uses | `aphotic android paths` |

## How setup works

`setup` reads `pack.toml`, which pins one download and one package list.

It downloads the command-line tools build named in the pack, verifies the
zip against a pinned sha256 and deletes it on a mismatch, then unpacks it
to the plugin's SDK root. It then runs `sdkmanager --licenses`, but only
when a terminal is attached, because the SDK terms are something a person
should read. Without a terminal it stops before that point and prints the
exact command to run. Re-running setup with everything installed changes
nothing and says so.

The licenses step and the pack install use `sdkmanager`, so those steps
also need `java` (17 or newer) and `unzip`, which the plugin declares as
its dependencies. Everything arrives under the plugin's own paths, setup
never runs sudo, and nothing is written outside the paths the manifest
owns.

## USB access

adb sees a phone only when a udev rule or a group membership says so.
`doctor` reports whether it can find such a rule and whether you are in a
group that grants it, and changes nothing, because the rule and the group
are your call.

## Cost at idle

Nothing. No daemon, no poller, no window. The only process anywhere is
adb's own server, and it starts only when a command asks for devices.
