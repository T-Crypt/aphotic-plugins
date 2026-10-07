# Pi Agent Hooks

Wires [Pi](https://github.com/earendil-works/pi) and
[Oh My Pi (OMP)](https://github.com/can1357/oh-my-pi) into
[Aphotic-Hypr](https://github.com/T-Crypt/aphotic-hypr)'s v2
agent-hook contract — the same contract
[`codex-hooks`](../codex-hooks/) and
[`opencode-hooks`](../opencode-hooks/) use, so Pi and OMP sessions land
in the bar's agent popout, the notch tile's agent stats, the
[Agent Graph](../agent-graph/) dashboard tab and the agent audit
alongside Claude Code and Codex ones, with the same stats: model,
tokens and rate-limit windows.

## Requires

- `pi` and/or `omp` on `PATH`. The plugin enables with either one
  present; `wire.sh` wires each discovery dir that belongs to an
  installed harness and refuses outright when neither is present.
- `jq` and `python3`.
- Verified against Pi 1.0.0 and OMP 18.5.1. Older runtimes are not
  wired (the extension event surface this adapter uses is not
  guaranteed there).

## What it does

Pi and OMP are the same pi-mono lineage: both load TypeScript/JavaScript
extensions through one `pi.on(...)` API, so one adapter file serves
both. `wire.sh` installs `hook/pi_omp_hook.js` into whichever discovery
dirs belong to an installed harness — `~/.pi/agent/extensions/` for Pi
and `~/.omp/agent/hooks/pre/` for OMP — and records core's
`agent_hook.py` path in `~/.local/state/aphotic/pi-hook.json`. Pi
follows a symlink, so it gets one; OMP's discovery scan ignores
symlinks, so it gets a two-line re-export shim that loads the same
file. Either way the plugin's repo is the only place the logic lives.

The extension maps its runtime events onto the v2 contract and hands
core's `agent_hook.py` the finished record — one writer for every
harness:

| Runtime event | v2 record |
|---|---|
| `session_start` | `session_start`, then a `quota` record |
| `before_agent_start`, `turn_start` | `turn` running |
| `tool_call` / `tool_result` | `tool_call` running / completed / errored |
| `assistant_message` (OMP) / `message_end` (Pi) | `usage` — per-response input, output, reasoning and cache tokens, model, provider, cost when priced |
| `turn_end`, stop boundaries | `quota` — context-window fill from the live context, plus provider windows on OMP |
| `tool_approval_requested` | `turn` waiting |
| `session_stop` (OMP) / `agent_settled` (Pi) | `turn` idle |
| `auto_compaction_start` / `auto_compaction_end` | `turn` compacting / running |
| `session_shutdown` | `session_end` |

Subagent sessions (OMP's task tool) carry `agentId`/`agentType` on
every record, so the graph and tile count them the way Claude Code's
subagents are counted. Pi has no subagent surface, so its records never
carry that.

Exactly one usage source per runtime: OMP fires both
`assistant_message` and `message_end` for one response, Pi fires
`message_end` only. The adapter picks per runtime, or OMP would count
every response twice.

## Provider windows

The context-window fill is live on both runtimes. Provider rate-limit
windows additionally exist on OMP: the runtime caches provider usage
reports in `~/.omp/agent/agent.db`, and the adapter reads the newest
rows for the session's own provider (a session on a local provider
never shows another provider's windows) and maps them to the contract's
window keys — "5 Hour" → `fiveHour`, "7 Day" → `sevenDay`. Rows older
than an hour are dropped, and Pi reports provider windows only if its
own runtime ever gains a usage cache.

## Safety

The hook spawns core's writer fire-and-forget: it never blocks a
harness event, never throws into the session, and reports a missing
wiring once to the harness console instead of failing the plugin load.
Unwiring removes the installed link and shim plus the config; a
restart of a running harness drops the module it already loaded.
