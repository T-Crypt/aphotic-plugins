# OpenCode Agent Hooks

Wires [OpenCode](https://opencode.ai) into Aphotic's v2 agent-hook
contract, the same contract [`claude-hooks`](../claude-hooks/) speaks, so
OpenCode sessions land in the agents notch tile, the bar's agent popout,
and the [Agent Graph](../agent-graph/) alongside Claude Code ones.

## Requires

- `opencode` >= 2.0.14 on `PATH` (declared in the manifest). The hook is
  built on OpenCode's v2 plugin API (default-export plugins,
  `ctx.event.subscribe`, the `session.*` event set) and gates itself off
  at runtime below that floor.
- `python3` (every record is handed to core's `agent_hook.py`) and `jq`
  (wire-time only).

## What it reports

The plugin registers through OpenCode's v2 plugin API (a default export
with `id` and `setup(ctx)`) and translates OpenCode's event stream into
the contract's record kinds:

| OpenCode | Record |
|---|---|
| `session.created` | `session_start` with `cwd`, model on first sight |
| `session.model.selected` | model change, rides the next record |
| `session.step.started` / `session.step.ended` | `turn` running / idle |
| `session.step.ended` | `usage` with that step's token delta and cost |
| `session.idle` | `turn` idle |
| `tool.execute.before` / `tool.execute.after` | `tool_call` running / completed, with real `durationMs` |
| `session.tool.success` / `session.tool.failed` | `tool_call` fallbacks for the same phases |
| `permission.asked` / `permission.replied` | `turn` waiting / running |
| `session.compaction.started` / `ended` / `failed` | `turn` compacting / running, plus `error` on failure |
| `session.error` | `error` |
| `session.deleted` | `session_end` with `endReason` |

Token counts include reasoning and cache read/write where OpenCode
reports them, and `cost` is the contract's `{amount, currency}` object.
Nested sessions (subagents) carry `agentId` / `agentType` on every
record, and the spawn tool's completed call carries `spawnedAgentId` so
the graph can draw the parent link. Tool names are normalized to the
graph's vocabulary (`bash` to `Bash`, `patch` to `Edit`, and so on);
anything unrecognized is just capitalized.

## What it touches

One symlink and one config file, both created by `wire.sh` and both removed
on disable/remove. Never any other plugin you keep in that directory:

- `~/.config/opencode/plugins/aphotic_opencode_hook.js`, a symlink (not a
  copy), so this repo stays the only place the logic is ever edited.
- `~/.local/state/aphotic/opencode-hook.json` (or `$XDG_STATE_HOME`), the
  resolved `agent_hook.py` path. OpenCode's loader passes no arguments and
  the script cannot derive the path from its own location, because Node
  and Bun both resolve `import.meta.url` to the symlink's realpath: the
  module's directory is this repo, not the config directory. That is why
  the config lives in the shell's own state dir instead of beside the
  symlink. A hook with no config reports that once and stays silent rather
  than spawning a path that does not exist.

`wire.sh` and `unwire.sh` also clear the two names this plugin has had
before, `aphotic-opencode-hook.js` and `opencode_hook.js`. OpenCode loads
every `.js` in its plugins directory, so a survivor of either name is a
second copy of this hook: sessions get reported twice and every token
count doubles.

## Install

```sh
git clone https://github.com/T-Crypt/aphotic-plugins ~/aphotic-plugins
aphotic plugin install opencode-hooks
```

Or for plugin development (edits take effect without reinstalling):

```sh
aphotic plugin install opencode-hooks --link
```
