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

Two files in `~/.config/opencode/plugins/`, both created by `wire.sh`
and both removed on disable/remove. Never any other plugin you keep
there:

- `aphotic_opencode_hook.js`, a symlink (not a copy), so this repo stays
  the only place the logic is ever edited. `wire.sh` also removes a
  leftover pre-plugin-era `opencode_hook.js` symlink: OpenCode loads
  every `.js` in this directory, so a duplicate would double-report.
- `.aphotic-hook-config.json`, the resolved `agent_hook.py` path.
  OpenCode's loader passes no arguments, so the script cannot derive
  that path from its own location the way `codex-hooks` can.

## Install

```sh
git clone https://github.com/T-Crypt/aphotic-plugins ~/aphotic-plugins
aphotic plugin install opencode-hooks
```

Or for plugin development (edits take effect without reinstalling):

```sh
aphotic plugin install opencode-hooks --link
```
