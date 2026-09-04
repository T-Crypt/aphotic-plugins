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
| [`agent-graph`](agent-graph/) | ai | Adds a dashboard tab with a live tool-call graph and run replay, plus its own Settings pane |
| [`agent-notch-tile`](agent-notch-tile/) | ai | Adds a notch tile: waiting-for-input badge, active harness and phase, local provider VRAM |
| [`dev-notch-tile`](dev-notch-tile/) | dev | Adds a notch tile for the Dev profile: open project, phase, resource claims |
| [`llm-fit`](llm-fit/) | ai | Adds a Settings pane recommending local models your GPU can run, with one-click pull |
| [`gaming`](gaming/) | gaming | Registers the Gaming profile: gamemode detection, DND while you play, foreground GPU VRAM claim |
| [`pet`](pet/) | theming | Adds a desktop pet at the bottom of the screen, with sprite-sheet imports for your own |
| [`claude-hooks`](claude-hooks/) | ai | Wires Claude Code into the agent-hook contract for live per-session tracking |
| [`codex-hooks`](codex-hooks/) | ai | Wires Codex into the agent-hook contract, same contract as Claude Code |
| [`opencode-hooks`](opencode-hooks/) | ai | Wires OpenCode into the agent-hook contract, same contract as Claude Code |

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
`agent-graph/` (a UI surface that adds a dashboard tab), or
`agent-notch-tile/` (a UI surface that adds a notch tile). Set
`category` (dev/security/mobile/ai/theming/productivity) and declare
whichever `capabilities` your plugin actually implements:

- `theme-hook`, `project-hook`, `workspace-hook` — each paired with the
  matching `[hooks]` key (`on_theme_change`, `on_project_open`,
  `on_workspace_launch`).
- `harness-hook` — paired with `[harness]` `wire`/`unwire` scripts, plus
  an `[owns] external_config` list naming the files outside the install
  directory that wiring touches.
- `ui-surface` — paired with a `[ui.dashboard_tab]`, `[ui.notch_tile]`,
  `[ui.settings_pane]` and/or `[ui.overlay]` block pointing at a QML
  component, plus `[owns] config_keys` for any shell settings it reads.
  Any block may carry `requires_layer` (`ai`/`dev`/`gaming`/`security`)
  and `requires_data` (`harness`), the surface's activation gate — the
  shell evaluates those without knowing which plugin declared them. Omit
  both and the surface is available on every install. A gate may
  never name another plugin; plugins under the same layer are siblings
  and every install permutation has to stand on its own — someone can
  run any one of them with all the others absent.
- `[ui.overlay]` is the one surface that gets a window rather than a
  slot inside one core already owns. It also takes `anchor`
  (`top`/`bottom`/`left`/`right`) and `width`/`height`, the surface
  budget core sizes that window from once and never renegotiates. The
  window is masked to your item, so the declared box is also the region
  that stops taking the desktop's clicks: ask for what you draw in.
  `pet/` is the worked example.
- `profile` — paired with a `[profile]` block naming a headless QML
  component that registers a profile with the shell's Profile Engine
  (detection, lifecycle, resource claims). `gaming/` is the worked
  example. Resource claims and snapshot parts are declared by the
  component itself, never a second time in the manifest.

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

### `[cli]` — the `cli` capability

A plugin can contribute a command to the `aphotic` CLI, either top-level
(`aphotic foo`) or as a subcommand of an existing core one
(`aphotic ai fit`):

```toml
capabilities = ["cli"]

[cli]
command = "ai"
subcommand = "fit"        # omit for a top-level command
script = "cli/ai_fit.sh"
summary = "one line, shown in that command's --help"
```

Core resolves this by declaration — it asks which plugin provides
`ai fit`, never whether your plugin is installed — so the command appears
and disappears with the plugin and no core file names it. Core commands
are tried first, so a plugin cannot shadow a built-in.

The script is **sourced, not executed**, in a subshell: `aphotic_err`,
`aphotic_warn`, `aphotic_log`, `aphotic_require` and the XDG paths are
already in scope exactly as they are for a core command, and `$@` is the
command's arguments. Use `return`, not `exit`. `llm-fit/cli/ai_fit.sh` is
the worked example — it was core's `aphotic ai fit` until this capability
existed.

Add
an entry to `index.json` at the repo root (including `category`, and the
`ui` block for a UI surface) so it shows up in `aphotic plugin list
--remote` and in Settings → Plugins' "Browse available" list, filterable
by category there. Open a PR — this repo follows the same contribution
conventions as the main `aphotic-hypr` repo.

## License

GPL-3.0 — see [LICENSE](LICENSE).
