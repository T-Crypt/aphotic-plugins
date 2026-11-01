# aphotic-plugins

Plugins add features to [Aphotic](https://github.com/T-Crypt/aphotic-hypr). The desktop works
without any of them. Install the ones you want, and remove them any time without touching the
rest of your setup.

## Install a plugin

The easy route is **Settings > Plugins**. It is one searchable list of everything installed and
installable, with a filter for each.

From a terminal:

```sh
aphotic plugin list --remote       # what you can install
aphotic plugin install pet         # install one
aphotic plugin install --link pet  # symlink a local checkout, for development
aphotic plugin update pet          # refresh its files from the repo checkout
aphotic plugin disable pet         # turn it off, keep it installed
aphotic plugin enable pet          # turn it back on
aphotic plugin remove pet          # uninstall it
```

`aphotic plugin --help` lists every subcommand, and `aphotic plugin list --category <name>`
filters the catalogue by category. Security-category plugins live in a separate index and stay
hidden until you opt in with `aphotic plugin trust-security-index`.

If a plugin needs a program you don't have, installing the plugin installs that program too.

## The plugins

Each section is one category, the same value `plugin.toml` declares and `--category` filters on.

### AI (`ai`)

| Plugin | What you get |
|---|---|
| [`claude-hooks`](claude-hooks/) | Wires Claude Code into the agent-hook contract so its live sessions show up in the bar and the Command Center. |
| [`codex-hooks`](codex-hooks/) | Wires Codex into the same contract, reading model, per-response tokens and rate-limit windows from its session logs. |
| [`opencode-hooks`](opencode-hooks/) | Wires OpenCode into the same contract. Needs OpenCode 2.0.14 or newer. |
| [`pi-hooks`](pi-hooks/) | Wires Pi and Oh My Pi into the same contract, plus context-window fill and provider rate-limit windows. |
| [`agent-notch-tile`](agent-notch-tile/) | A notch tile for coding agents, with a chip per live session that brings its window forward, waiting-for-input rows, quota bars and the local provider's GPU memory claim. |
| [`agent-graph`](agent-graph/) | A Command Center tab that graphs every tool call as an agent makes it, with run replay. |
| [`agent-audit`](agent-audit/) | A workspace plane for inspecting local agent run evidence, live activity and replay timelines. |
| [`agent-memory`](agent-memory/) | Folds local agent session events into a durable memory, with per-project tool stats, recurring failures as resolve/reopen issues, notes and an injectable context digest. |
| [`llama-swap`](llama-swap/) | A notch tile for every local inference engine, showing which one is in use, its loaded models and measured GPU memory, plus llama-swap's live generation stats and unload controls. |
| [`llm-fit`](llm-fit/) | A Settings pane that recommends local models your hardware can run, with one-click download for the tags it confirms are real. |
| [`skills`](skills/) | One library of agent skills deployed to every coding agent on the machine, with Settings and workspace panes and its own CLI. |

### Development (`dev`)

| Plugin | What you get |
|---|---|
| [`dev-notch-tile`](dev-notch-tile/) | A notch tile showing the open project, its lifecycle phase, its resource claims, and a badge when a lockfile has fallen behind its manifest. |
| [`docker`](docker/) | A notch tile for Docker, covering daemon state, containers grouped by compose project with live CPU and memory, start, stop and restart, logs and a shell in a terminal, and a prune behind a second confirming click. |
| [`dev-ports`](dev-ports/) | Lists local HTTP dev servers found on listening loopback ports, with online or cached status and one click to open. |
| [`direnv`](direnv/) | Notifies you when a project opened from the launcher has an `.envrc` to review. |
| [`ios-dev`](ios-dev/) | Turns this machine into an iPhone development box, with a toolchain doctor, one key to build and run on the device, and a workspace plane for connected devices and session state. |

### Theming (`theming`)

| Plugin | What you get |
|---|---|
| [`widgets`](widgets/) | Transparent desktop widgets for clocks, calendars, media, system meters, weather, timers, notes and more, each draggable, resizable and configurable, or press SUPER+ALT+W to edit. |
| [`pet`](pet/) | A creature that lives on the desktop, goes wherever you drag it, wanders its own patch, wears the theme and reacts when you click it. |
| [`live-wallpaper`](live-wallpaper/) | Plays video wallpapers on the desktop background, with the still frame the theme palette comes from underneath. |
| [`deep-signal`](deep-signal/) | An idle screensaver where the wordmark resolves out of noise over a sparse particle drift, tinted by whatever theme is active. |
| [`openrgb`](openrgb/) | Syncs the theme accent to RGB PC lighting over the OpenRGB SDK, and reacts to the Gaming profile and live AI-agent sessions. |
| [`wallpaper-packs`](wallpaper-packs/) | Theme-matched wallpaper collections fetched on request with `aphotic wallpaper fetch` and checked against each file's sha256. |

### Gaming (`gaming`)

| Plugin | What you get |
|---|---|
| [`gaming`](gaming/) | Coordinates the desktop shell around a running game, with gamemode detection, do-not-disturb while you play, and a foreground GPU claim so a local model yields the memory. |
| [`game-launcher`](game-launcher/) | A visual game library on the workspace plane that finds your installed games, launches each with its own command, and gets out of the way while you play. |

### Productivity (`productivity`)

| Plugin | What you get |
|---|---|
| [`xfreerdp`](xfreerdp/) | RDP sessions into Windows machines through xfreerdp3, with microphone, camera, resolution and workspace pinning, one saved profile, a section in Network settings, and `aphotic xfreerdp connect`. |
| [`workspace-session-log`](workspace-session-log/) | Keeps a local, timestamped log of when each Workspace Profile launches. |

### Security (`security`)

| Plugin | What you get |
|---|---|
| [`security-notch-tile`](security-notch-tile/) | A notch tile for the Security layer covering posture, exposure, VPN, firewall, sessions, advisories and engagement control. |

### Core (`core`)

| Plugin | What you get |
|---|---|
| [`visualizer`](visualizer/) | An audio spectrum that sits on the wallpaper, painted in the live theme accent and asleep whenever nothing is playing. |

Some plugins light up only with the matching install layer (AI, Dev, Gaming or Security) from
the Aphotic installer.

## Build your own

A plugin is a folder with a `plugin.toml` file that says what it adds. Start by copying the
plugin closest to your idea, then read [WRITING-PLUGINS.md](WRITING-PLUGINS.md) for every
manifest option. `aphotic plugin validate <folder>` checks your plugin before you install it,
and `aphotic plugin api` lists the shell runtime API version and every call a plugin can declare.

To share it, open a pull request here. Run `python3 tools/build_index.py` first so the plugin
shows up in **Settings > Plugins**.

## License

GPL-3.0. See [LICENSE](LICENSE).
