# Writing a plugin

A plugin is a directory with a `plugin.toml` manifest — copy the
example closest to what you're building: `openrgb/` (a theme hook),
`direnv/` (a project hook), `workspace-session-log/` (a workspace hook),
`claude-hooks/` (a harness hook that wires an external tool's config),
`agent-graph/` (a UI surface that adds a dashboard tab),
`agent-notch-tile/` (a UI surface that adds a notch tile), or
`agent-audit/` (a UI surface that claims the Workspace plane). Set
`category` (dev/security/mobile/ai/theming/productivity) and declare
whichever `capabilities` your plugin actually implements:

- `theme-hook`, `project-hook`, `workspace-hook` — each paired with the
  matching `[hooks]` key (`on_theme_change`, `on_project_open`,
  `on_workspace_launch`).
- `harness-hook` — paired with `[harness]` `wire`/`unwire` scripts, plus
  an `[owns] external_config` list naming the files outside the install
  directory that wiring touches.
- `ui-surface` — paired with one or more surface blocks pointing at a QML
  component, plus `[owns] config_keys` for any shell settings it reads.
  The blocks are `[ui.dashboard_tab]`, `[ui.notch_tile]`,
  `[ui.settings_pane]`, `[ui.overlay]`, `[ui.fullscreen-overlay]`,
  `[ui.workspace]`, and numbered `[ui.pet_action]` sections.
  Any block may carry `requires_layer` (`ai`/`dev`/`gaming`/`security`)
  and `requires_data` (`harness`), the surface's activation gate — the
  shell evaluates those without knowing which plugin declared them. Omit
  both and the surface is available on every install. A gate may
  never name another plugin; plugins under the same layer are siblings
  and every install permutation has to stand on its own — someone can
  run any one of them with all the others absent.
- Top-level `shelter = "unload"` lets a profile unload a plugin's UI
  surfaces while that profile needs the frame budget. Core restores the
  surfaces when the shelter receipt is released.
- `[ui.overlay]` is a surface that gets a window rather than a
  slot inside one core already owns. It also takes `anchor`
  (`top`/`bottom`/`left`/`right`) and `width`/`height`, the surface
  budget core sizes that window from once and never renegotiates. The
  window is masked to your item, so the declared box is also the region
  that stops taking the desktop's clicks: ask for what you draw in.
  `pet/` is the worked example. Two optional properties on your root
  item go further: `maskRegion`, a `Region` of your own with child
  regions, replaces the single-item mask so a surface that draws several
  separate things keeps the gaps between them clickable; `wantsKeyboard`,
  while true, lets the window take keyboard focus for a text field.
  `widgets/` uses both.
- `[ui.workspace]` is the near-full-screen plane, for a tool that needs
  room to work rather than a corner of a surface core already owns. Takes
  an `id`, a `label`, an `icon` and a `component`; there is no geometry
  to declare, because the plane is one size and the shell owns it. More
  than one plugin may register, and the plane lists them down its left
  edge in label order, so write a label that reads as a tool name.
  The plane exists only while at least one such plugin is enabled: with
  none there is no window, and `SUPER+SHIFT+W` is not bound at all.
  `agent-audit/` is the worked example.
- `profile` — paired with a `[profile]` block naming a headless QML
  component that registers a profile with the shell's Profile Engine
  (detection, lifecycle, resource claims). `gaming/` is the worked
  example. Resource claims and snapshot parts are declared by the
  component itself, never a second time in the manifest.
- `keybind` - paired with a `[keybind]` block: a combo the shell binds in
  the running compositor session while the plugin is installed, enabled
  and past its gate. No config file is edited, and the bind is released
  the moment the plugin is disabled, gated off or removed.

## Declaring dependencies

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

## `[cli]` — the `cli` capability

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

## `[keybind]` - a combo the plugin owns while it is enabled

```toml
capabilities = ["keybind"]

[keybind]
combo = "SUPER + ALT + P"     # required. Canonical Lua form, " + "-separated, key last
action = "connect"            # required. An action id this manifest declares
description = "Toggle RDP"    # optional. The cheatsheet label
requires_layer = "gaming"     # optional. Same gate vocabulary as a surface
requires_data = "harness"
```

The combo runs that action through the same path the command palette and
`aphotic` IPC use, so a keybind never registers a second way to do the thing.
Sections are `[keybind]` through `[keybind_5]`, flat and single valued like
every other block. One combo per plugin is the intent today; a second is the
trigger to grow the reader, the same reasoning `[action]`'s numbering follows.

The shell binds through the compositor's runtime IPC, so nothing the plugin
declares ever lands in a config file, and the user's own binds are left alone.
A combo already taken by another plugin cannot be detected in advance: the
last registration wins and the shell logs the conflict. Pick something the
shell does not already use.

Declaring `keybind` on a shell with no host for it does not block the install:
the plugin is reported as partially hosted and that one part stays dark until
Aphotic is updated.

Then rebuild the catalogue:

```sh
python3 tools/build_index.py
```

`index.json` at the repo root is what `aphotic plugin list --remote` and
Settings → Plugins' "Browse available" list read before anything is
installed. It is derived from every `plugin.toml`, so write the manifest
and let the script write the entry. `--check` says whether the checked-in
file still matches, which is what to run before tagging a release.

Commit the regenerated file with your change and open a PR. This repo
follows the same contribution conventions as the main `aphotic-hypr`
repo.
