# Workspace Session Log

Keeps a local, timestamped log of when each
[Aphotic-Hypr](https://github.com/T-Crypt/aphotic-hypr) Workspace
Profile is launched -- a quiet way to see which profiles you actually
use and how often, without any tracking or telemetry leaving your
machine.

## Requires

Nothing beyond coreutils (`date`, `mkdir`) -- already present on any
system that can run Aphotic-Hypr at all.

## What it does

Every time a Workspace Profile is launched (Settings → Workspace
Profiles, or however else `launchProfile()` gets called), appends one
tab-separated line to:

```
~/.local/share/aphotic-plugins/workspace-session-log/launches.log
```

Format: `<ISO-8601 timestamp>\tlaunched\t<profile name>`. Plain text,
`grep`/`awk`/`cut`-friendly on purpose -- no database, no JSON, nothing
to parse but a tab.

## Install

```sh
git clone https://github.com/T-Crypt/aphotic-plugins ~/aphotic-plugins
aphotic plugin install workspace-session-log
```

Or for plugin development (edits take effect without reinstalling):

```sh
aphotic plugin install workspace-session-log --link
```
