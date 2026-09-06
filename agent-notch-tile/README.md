# Agent Notch Tile

Docks a tile into Aphotic's notch showing, at a glance:

- **Waiting for input** — the primary signal. A harness that has stopped
  and is waiting on you badges the collapsed notch, so you get it without
  opening anything.
- **Active harness and phase** — one line: which harness is working and
  whether it is running, idle, or waiting.
- **Live subagents** — how many are running under the active session. A
  count, not a roster.
- **Quota bars** — the five-hour and seven-day windows the harness
  reports about itself, plus how full the session's context is, each with
  the time until it resets. Amber past 75%, red past 90%.
- **Today's tokens** — the day's total and the model most of it went to,
  summed off local transcripts.
- **Local provider VRAM** — what Ollama is holding on the GPU, read off
  the Resource Engine's claim table rather than a poll of its own.

Every session waiting on you also gets a row. Click one and its terminal
comes forward, with the shell's own context on the clipboard ready to
paste. Nothing types into a window: a window is matched by working
directory, that match can be ambiguous, and synthetic keystrokes into the
wrong terminal cannot be taken back.

Deliberately not here: the tool-call graph, the node list, and run
replay. Those are [`agent-graph`](../agent-graph/)'s surface, folded from
the same event feed. The two are siblings — either one works with the
other absent, and neither manifest mentions the other.

## Requirements

- The `ai` layer installed (`requires_layer = "ai"`).
- At least one configured harness — Claude Code or Codex
  (`requires_data = "harness"`). Its hook plugin
  ([`claude-hooks`](../claude-hooks/),
  [`codex-hooks`](../codex-hooks/)) is what writes the events this tile
  reads, so a harness with no hook wired shows an idle tile.

Both are checked by the shell from this plugin's manifest. With either
unmet the tile is absent from the notch rather than present and empty.

The quota bars need one thing more: `claude-hooks` has to own Claude
Code's `statusLine` slot, since that command's payload is the only place
a harness states how much of a window it has spent. If you already had a
`statusLine` configured, the plugin leaves it alone and the bars stay
hidden. They also hide once the reading goes stale, because Claude Code
only reports those numbers while a session is live.

## Install

```sh
aphotic plugin install agent-notch-tile
```
