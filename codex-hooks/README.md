# Codex Agent Hooks

Wires [Codex](https://developers.openai.com/codex) into
[Aphotic-Hypr](https://github.com/T-Crypt/aphotic-hypr)'s v2
agent-hook contract — the same contract [`claude-hooks`](../claude-hooks/)
and [`opencode-hooks`](../opencode-hooks/) use, so Codex sessions land
in the bar's agent popout, the
[Agent Graph](../agent-graph/) dashboard tab and the agent audit
alongside Claude Code ones, with the same stats: model, tokens and
rate-limit windows.

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

Codex's payload already carries Claude Code's field names
(`session_id`, `tool_use_id`, `tool_name`, `transcript_path`), so the
adapter mostly translates: it builds v2-contract records
(`harness = "codex"`, contract event kinds and statuses,
`SessionEnd`'s `reason` as the v2 `endReason` field) and hands core's
`agent_hook.py` the finished record — one writer for every harness.
Tool aliases still get normalized to the graph's vocabulary —
`shell` → `Bash`, `apply_patch` → `Edit`, `spawn_agent` → `Agent`;
MCP and function names like `mcp__filesystem__read_file` pass through
untouched.

Two things Codex does not say on the hook payload come off the
session log the payload points at:

- **tokens and rate limits.** Codex writes a `token_count` record
  after every model response. On `PostToolUse`, `Stop` and
  `SessionEnd` the adapter reads the newest one and adds a `usage`
  record (per-response input/output/cache tokens) and, when windows
  are present, a `quota` record (primary/secondary `usedPercent` and
  `resetsAt`). Each `token_count` is counted once per session, so
  summing the records gives the session total.
- **the provider.** The log's first line names the `model_provider`
  that served the session, so a Codex session on a local provider is
  labelled with it rather than `openai`.

The translation lives here, at the harness's own adapter boundary,
rather than teaching core's `agent_hook.py` a second input shape.

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
