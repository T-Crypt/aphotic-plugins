# aphotic-plugins

Plugins add features to [Aphotic](https://github.com/T-Crypt/aphotic-hypr). The desktop works
without any of them. Install the ones you want, and remove them any time without touching the
rest of your setup.

## Install a plugin

The easy way: open **Settings > Plugins**, pick one from **Browse available**, and switch it on.

From a terminal:

```sh
aphotic plugin list --remote      # what you can install
aphotic plugin install pet        # install one
aphotic plugin disable pet        # turn it off, keep it installed
aphotic plugin enable pet         # turn it back on
aphotic plugin remove pet         # uninstall it
```

If a plugin needs a program you don't have, installing the plugin installs that program too.

## The plugins

### Look and feel

| Plugin | What you get |
|---|---|
| [`pet`](pet/) | A small creature on your desktop. Drag it anywhere; it wanders nearby and wears your theme colours. Bring your own sprite sheet if you like. |
| [`visualizer`](visualizer/) | An audio spectrum drawn on your wallpaper in your theme colour. It sleeps when nothing plays. |
| [`live-wallpaper`](live-wallpaper/) | Video wallpapers. Your theme colours still come from a still frame. |
| [`deep-signal`](deep-signal/) | A screensaver: the Aphotic mark rises out of static over drifting particles. |
| [`openrgb`](openrgb/) | Your PC's RGB lighting follows your theme colour, and reacts when you game or an AI agent works. |

### AI and coding agents

| Plugin | What you get |
|---|---|
| [`claude-hooks`](claude-hooks/), [`codex-hooks`](codex-hooks/), [`opencode-hooks`](opencode-hooks/) | Connect a coding agent so the bar and Command Center can show its sessions live. Install the one for the agent you use. |
| [`agent-notch-tile`](agent-notch-tile/) | A notch tile that shows which agent runs, what it is doing, and when it waits for you. |
| [`agent-graph`](agent-graph/) | A Command Center tab that draws every tool call as your agent makes it, with replay. |
| [`agent-audit`](agent-audit/) | A full-screen view to step through past and live agent runs, with tool and failure counts. |
| [`llama-swap`](llama-swap/) | A notch tile for your local model server: loaded models, GPU memory, speed, and an unload button. |
| [`llm-fit`](llm-fit/) | A Settings pane that suggests local models your GPU can run, with one-click download. |

### Development

| Plugin | What you get |
|---|---|
| [`dev-notch-tile`](dev-notch-tile/) | A notch tile for your open project and what stage it is in. |
| [`dev-ports`](dev-ports/) | A full-screen list of the dev servers running on your machine. Click one to open it. |
| [`direnv`](direnv/) | A heads-up when a project you open has an `.envrc` to review. |

### Gaming and everyday

| Plugin | What you get |
|---|---|
| [`gaming`](gaming/) | Spots a running game, turns on Do Not Disturb, and gives the game first claim on the GPU. |
| [`workspace-session-log`](workspace-session-log/) | A local log of when you launch each Workspace Profile. |

Some plugins only work with the matching install layer (AI, Dev or Gaming) from the Aphotic
installer.

## Build your own

A plugin is a folder with a `plugin.toml` file that says what it adds. Start by copying the
plugin closest to your idea, then read [WRITING-PLUGINS.md](WRITING-PLUGINS.md) for every
manifest option. `aphotic plugin validate <folder>` checks your plugin before you install it,
and `aphotic plugin api` lists what a plugin can call.

To share it, open a pull request here. Run `python3 tools/build_index.py` first so the plugin
shows up in **Browse available**.

## License

GPL-3.0. See [LICENSE](LICENSE).
