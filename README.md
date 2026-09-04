# aphotic-plugins

Official plugins for [Aphotic-Hypr](https://github.com/T-Crypt/aphotic-hypr).
See that repo's [Plugin System](https://github.com/T-Crypt/aphotic-hypr#plugin-system)
section and the [Plugin System wiki page](https://github.com/T-Crypt/aphotic-hypr/wiki/Plugin-System)
for the plugin contract, manifest format, and how installation works.

## Available plugins

| Plugin | Category | What it does |
|---|---|---|
| [`openrgb`](openrgb/) | theming | Syncs the theme accent to RGB PC lighting over OpenRGB's SDK, plus Gaming-profile and AI-agent states |
| [`direnv`](direnv/) | dev | Notifies you when a project opened from the launcher has an `.envrc` |
| [`workspace-session-log`](workspace-session-log/) | productivity | Keeps a local, timestamped log of Workspace Profile launches |
| [`agent-graph`](agent-graph/) | ai | Adds a dashboard tab with a live tool-call graph and run replay for AI coding harnesses |
| [`claude-hooks`](claude-hooks/) | ai | Wires Claude Code into the agent-hook contract for live per-session tracking |
| [`codex-hooks`](codex-hooks/) | ai | Wires Codex into the agent-hook contract, same contract as Claude Code |
| [`opencode-hooks`](opencode-hooks/) | ai | Wires OpenCode into the agent-hook contract, same contract as Claude Code |
| [`visualizer`](visualizer/) | core | Draws an audio spectrum on the wallpaper, in the live theme accent, asleep when nothing is playing |

## Installing a plugin

```sh
git clone https://github.com/T-Crypt/aphotic-plugins ~/aphotic-plugins
aphotic plugin install <name>
```

Or browse and install straight from Settings → Plugins in the shell
itself.

## Writing a plugin

A plugin is a directory with a `plugin.toml` manifest — copy the
example closest to what you're building: `openrgb/` (a theme hook),
`direnv/` (a project hook), `workspace-session-log/` (a workspace hook),
`claude-hooks/` (a harness hook that wires an external tool's config),
or `agent-graph/` (a UI surface that adds a dashboard tab). Set
`category` (dev/security/mobile/ai/theming/productivity) and declare
whichever `capabilities` your plugin actually implements:

- `theme-hook`, `project-hook`, `workspace-hook` — each paired with the
  matching `[hooks]` key (`on_theme_change`, `on_project_open`,
  `on_workspace_launch`).
- `harness-hook` — paired with `[harness]` `wire`/`unwire` scripts, plus
  an `[owns] external_config` list naming the files outside the install
  directory that wiring touches.
- `ui-surface` — paired with a `[ui.dashboard_tab]` block pointing at a
  QML component, plus `[owns] config_keys` for any shell settings it
  reads.

### Declaring dependencies

`[requires] binaries = [...]` lists the binaries your plugin shells out
to. Anything missing from `PATH` is installed with `yay`/`paru`, using the
binary's own name as the package name — right for the common case
(`openrgb` the binary really does come from a package called `openrgb`).
Two escape hatches for when it isn't:

- `[requires] packages = [...]` — the package name simply differs from
  the binary name (a `foo` binary shipping in `foo-bin`).
- `[requires] install_script = "hooks/install-deps.sh"` — no AUR package
  is the right answer at all. Core runs your script instead of the
  helper, same trust model as `[harness]` wire/unwire. `codex-hooks/` is
  the worked example: no AUR package is named `codex`, and the fallback
  resolves that name to an unrelated Electron app that drags in a
  multi-GB chromium build, so the plugin installs the upstream CLI
  itself. A script that runs something irreversible should confirm first
  and no-op when stdin is not a terminal.

Add
an entry to `index.json` at the repo root (including `category`, and the
`ui` block for a UI surface) so it shows up in `aphotic plugin list
--remote` and in Settings → Plugins' "Browse available" list, filterable
by category there. Open a PR — this repo follows the same contribution
conventions as the main `aphotic-hypr` repo.

## License

GPL-3.0 — see [LICENSE](LICENSE).
