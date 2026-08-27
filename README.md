# aphotic-plugins

Official plugins for [Aphotic-Hypr](https://github.com/T-Crypt/aphotic-hypr).
See that repo's [`docs/PLUGIN_SYSTEM.md`](https://github.com/T-Crypt/aphotic-hypr/blob/test/docs/PLUGIN_SYSTEM.md)
for the plugin contract, manifest format, and how installation works.

## Available plugins

| Plugin | Category | What it does |
|---|---|---|
| [`openrgb`](openrgb/) | theming | Syncs the active theme's accent color to RGB PC lighting via OpenRGB |
| [`direnv`](direnv/) | dev | Notifies you when a project opened from the launcher has an `.envrc` |
| [`workspace-session-log`](workspace-session-log/) | productivity | Keeps a local, timestamped log of Workspace Profile launches |

## Installing a plugin

```sh
git clone https://github.com/T-Crypt/aphotic-plugins ~/aphotic-plugins
aphotic plugin install <name>
```

Or browse and install straight from Settings → Plugins in the shell
itself.

## Writing a plugin

A plugin is a directory with a `plugin.toml` manifest — copy `openrgb/`
(a theme-hook example), `direnv/` (a project-hook example), or
`workspace-session-log/` (a workspace-hook example) as a starting
point. Set `category` (dev/security/mobile/ai/theming/productivity) and
declare whichever `capabilities` your plugin actually implements
(`theme-hook`/`project-hook`/`workspace-hook`, each paired with the
matching `[hooks]` key) — see `docs/PLUGIN_SYSTEM.md` in the main repo
for the full contract. Add an entry to `index.json` at the repo root
(including `category`) so it shows up in `aphotic plugin list --remote`
and in Settings → Plugins' "Browse available" list, filterable by
category there. Open a PR — this repo follows the same contribution
conventions as the main `aphotic-hypr` repo.

## License

GPL-3.0 — see [LICENSE](LICENSE).
