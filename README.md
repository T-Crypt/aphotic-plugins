# aphotic-plugins

Official plugins for [Aphotic-Hypr](https://github.com/T-Crypt/aphotic-hypr).
See that repo's [`docs/PLUGIN_SYSTEM.md`](https://github.com/T-Crypt/aphotic-hypr/blob/test/docs/PLUGIN_SYSTEM.md)
for the plugin contract, manifest format, and how installation works.

## Available plugins

| Plugin | What it does |
|---|---|
| [`openrgb`](openrgb/) | Syncs the active theme's accent color to RGB PC lighting via OpenRGB |

## Installing a plugin

```sh
git clone https://github.com/T-Crypt/aphotic-plugins ~/aphotic-plugins
aphotic plugin install <name>
```

Or browse and install straight from Settings → Plugins in the shell
itself.

## Writing a plugin

A plugin is a directory with a `plugin.toml` manifest — copy `openrgb/`
as a starting point. Add an entry to `index.json` at the repo root so it
shows up in `aphotic plugin list --remote` and in Settings → Plugins'
"Browse available" list. Open a PR — this repo follows the same
contribution conventions as the main `aphotic-hypr` repo.

## License

GPL-3.0 — see [LICENSE](LICENSE).
