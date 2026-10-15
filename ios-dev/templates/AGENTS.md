# iOS app

This is an iPhone app built on Linux. It reaches a real device over USB
through `xtool`, which builds the package, signs it and installs it.

- Bundle ID: @BUNDLE_ID@
- Run it: `aphotic ios run` from this directory, or SUPER + ALT + I
- Debug it: `aphotic ios debug`
- Stop a running session: `aphotic ios stop`

## What not to change

- `xtool.yml` holds the bundle ID and the app icon path. Edit the bundle
  ID if you rename the app, and leave `version` at 1.
- `Package.swift` keeps exactly one library product, which is the app.
  A second product makes the build ambiguous.
- `.build/` and `xtool/` are build output. Both are gitignored.
- `.vscode/` is generated. The tasks call `aphotic ios`, so the command
  that installs the app lives in one place rather than in a recipe here.

## What the toolchain needs

iOS refuses to replace a running app, so a run closes the app first. The
first debug run on a new iOS version copies the phone's symbol cache and
takes a few minutes. Keep the phone unlocked with the app in front for
anything that touches the UI.

If a build fails with "this SDK is not supported by the compiler", the
Swift toolchain and the installed SDK do not match. Run
`aphotic ios toolchain` to see both versions.

Settings for this project (bundle prefix, where new apps are created)
live in ~/.config/aphotic/plugins/ios-dev/config.
