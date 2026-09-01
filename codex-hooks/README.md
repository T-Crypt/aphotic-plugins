# Codex Agent Hooks

Wires [Codex](https://developers.openai.com/codex) into
[Aphotic-Hypr](https://github.com/T-Crypt/aphotic-hypr)'s agent-hook
contract — the same contract [`claude-hooks`](../claude-hooks/) uses, so
Codex sessions land in the bar's agent popout and the
[Agent Graph](../agent-graph/) dashboard tab alongside Claude Code ones.

## Requires

- `codex` on `PATH` (declared in the manifest).
- `jq` and `python3`.

## What it does

Adds one command hook per event to `~/.codex/hooks.json`, Codex's
dedicated user-level hooks source:

| Event | Timeout | Async |
|---|---|---|
| `SessionStart` | 5s | no |
| `PreToolUse` / `PostToolUse` | 10s | yes |
| `SubagentStop` | 5s | no |
| `Stop` | 5s | no |
| `SessionEnd` | 3s | no |

The two tool events run async because Codex executes them
synchronously — a blocking hook there would stall the session's own tool
call. `SessionEnd` is capped at 3 seconds by Codex itself.

`PostToolUseFailure` and `Notification` have no equivalent in Codex's
hook schema, so this plugin wires six events where `claude-hooks` wires
eight.

Unlike Claude Code, Codex's payload needs a small translation first, so
hooks point at this plugin's own `hook/codex_hook.sh` rather than core's
`agent_hook.sh`. `hook/codex_hook.py` tags the record `harness =
"codex"` (otherwise every session would be mislabeled `claude`), renames
`SessionEnd`'s `reason` to the `end_reason` core reads, and normalizes
Codex's tool aliases to the graph's vocabulary — `shell` → `Bash`,
`apply_patch` → `Edit`, `spawn_agent` → `Agent`. MCP and function names
like `mcp__filesystem__read_file` pass through untouched. Everything else
already carries the right field names. The translation lives here, at
the harness's own adapter boundary, rather than teaching core's
`agent_hook.py` a second input shape.

## What it touches

Only `~/.codex/hooks.json` — deliberately **not** `config.toml`, so your
provider, auth, and MCP settings there are never involved. As with
`claude-hooks`, wiring is an idempotent `jq` merge that preserves other
tools' hooks, matching on this plugin's own `codex_hook.sh` path so a
reinstall at a different clone path replaces its entry instead of
orphaning it. Invalid JSON aborts wiring rather than overwriting.

## Install

```sh
git clone https://github.com/T-Crypt/aphotic-plugins ~/aphotic-plugins
aphotic plugin install codex-hooks
```

Or for plugin development (edits take effect without reinstalling):

```sh
aphotic plugin install codex-hooks --link
```
