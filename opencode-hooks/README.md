# OpenCode Agent Hooks

Wires [OpenCode](https://opencode.ai) into
[Aphotic-Hypr](https://github.com/T-Crypt/aphotic-hypr)'s agent-hook
contract — the same contract [`claude-hooks`](../claude-hooks/) uses, so
OpenCode sessions land in the bar's agent popout and the
[Agent Graph](../agent-graph/) dashboard tab alongside Claude Code ones.

## Requires

- `opencode` on `PATH` (declared in the manifest).
- `jq` and `python3`.

## What it does

OpenCode has no hooks config file. Instead it auto-loads any `.js`/`.ts`
file dropped in `~/.config/opencode/plugins/`, so this plugin symlinks
its own `hook/opencode_hook.js` there and that script subscribes to
OpenCode's plugin API directly:

| OpenCode event | Sent as |
|---|---|
| `session.created` | `SessionStart` |
| `chat.params` (first resolve, or model change) | follow-up `SessionStart` carrying the model |
| `tool.execute.before` | `PreToolUse` |
| `tool.execute.after` | `PostToolUse`, with `duration_ms` |
| `session.idle` | `Stop` |
| `session.deleted` / `dispose` | `SessionEnd` |

`session.created` fires before the model is known, hence the follow-up
`SessionStart` once `chat.params` resolves one — otherwise the graph
label would stay stuck on the session id. Because the plugin is a
long-lived process rather than one process per event, it is the only one
of the three that can time tool calls itself, so `PostToolUse` carries a
real `duration_ms`. Tool names are normalized to the graph's vocabulary
(`bash` → `Bash`, `patch` → `Edit`, and so on); anything unrecognized is
just capitalized. Each event is handed to core's `agent_hook.py` as a
short-lived spawn tagged `harness = "opencode"`.

Since OpenCode's plugin loader passes no arguments, the script can't
derive where core's `agent_hook.py` lives from its own location the way
`codex-hooks` can. `wire.sh` therefore writes a small
`.aphotic-hook-config.json` next to the symlink recording that path.

## What it touches

Two files in `~/.config/opencode/plugins/`, both created by `wire.sh`
and both removed on disable/remove — never any other plugin you keep
there:

- `aphotic_opencode_hook.js` — a symlink, not a copy, so this repo stays
  the only place the logic is ever edited.
- `.aphotic-hook-config.json` — the resolved `agent_hook.py` path.

## Install

```sh
git clone https://github.com/T-Crypt/aphotic-plugins ~/aphotic-plugins
aphotic plugin install opencode-hooks
```

Or for plugin development (edits take effect without reinstalling):

```sh
aphotic plugin install opencode-hooks --link
```
