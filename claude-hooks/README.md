# Claude Code Agent Hooks

Wires [Claude Code](https://claude.com/claude-code) into
[Aphotic-Hypr](https://github.com/T-Crypt/aphotic-hypr)'s agent-hook
contract, so live per-session activity shows up in the bar's agent
popout and the [Agent Graph](../agent-graph/) dashboard tab.

## Requires

- Claude Code, obviously — but it is not declared as a required binary,
  so this installs cleanly ahead of it and starts working the moment
  Claude Code is present.
- `jq` (guaranteed present — both install profiles' prep stage installs
  it).
- `python3`, for the shell's own `agent_hook.py` translator.

## What it does

Adds one command hook per event to `~/.claude/settings.json`, each
pointing at the shell's own `agent_hook.sh`:

| Event | Timeout | Why |
|---|---|---|
| `SessionStart` | 10s | Registers the session (model, cwd, source) |
| `PreToolUse` / `PostToolUse` | 30s | Opens and closes each tool-call node |
| `PostToolUseFailure` | 30s | Marks a tool call as failed rather than done |
| `Notification` | 10s | Surfaces "needs your input" in the bar |
| `Stop` / `SubagentStop` | — | Ends a turn (not the session) |
| `SessionEnd` | 10s | Retires the session |

Claude Code is the reference harness: its hook payload already uses the
field names `agent_hook.py` reads, so — unlike [`codex-hooks`](../codex-hooks/)
and [`opencode-hooks`](../opencode-hooks/) — there is no translator in
between. `agent_hook.sh` is wired straight in.

`SessionEnd`, not `Stop`, is what retires a session: `Stop` fires at the
end of every assistant turn.

## What it touches

Only `~/.claude/settings.json`, and only its own entries. Wiring is a
`jq` merge, never a template, so hooks you already have for other tools
survive untouched; re-running install or enable replaces this plugin's
entry rather than duplicating it. Removing or disabling the plugin drops
exactly the entries pointing at `agent_hook.sh` and prunes any hook
event left empty.

If `settings.json` exists but isn't valid JSON, wiring aborts with an
error and changes nothing — it will not clobber a file it can't parse.

## Install

```sh
git clone https://github.com/T-Crypt/aphotic-plugins ~/aphotic-plugins
aphotic plugin install claude-hooks
```

Or for plugin development (edits take effect without reinstalling):

```sh
aphotic plugin install claude-hooks --link
```
