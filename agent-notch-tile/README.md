# Agent Notch Tile

Docks a tile into Aphotic's notch showing, at a glance:

- **Waiting for input** — the primary signal. A harness that has stopped
  and is waiting on you badges the collapsed notch, so you get it without
  opening anything.
- **Active harness and phase** — one line: which harness is working and
  whether it is running, idle, or waiting.
- **The rest of the stack** — one compact row per other live harness:
  which agents a machine runs at once, each with its phase, last tool
  and subagent count. A machine running only Pi or only OMP reads the
  same tile as one running Claude Code.
- **Live subagents** — how many are running under the active session. A
  count, not a roster.
- **Quota bars** — the windows the harness reports about itself, each
  with the time until it resets: Claude Code's five-hour and seven-day
  allowance, Codex's five-hour and weekly limits, and how full the
  session's context is (the only window a local-model session such as
  Pi or OMP reports, which is why the bars never show a false zero
  for a subscription the harness has no concept of). Amber past 75%,
  red past 90%.
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
- At least one wired harness — Claude Code, Codex, OpenCode, Pi or
  OMP (`requires_data = "harness"`). That harness's hook plugin
  ([`claude-hooks`](../claude-hooks/),
  [`codex-hooks`](../codex-hooks/),
  [`opencode-hooks`](../opencode-hooks/),
  [`pi-hooks`](../pi-hooks/)) is what writes the events this tile
  reads, so a harness with no hook wired shows an idle tile.

Both are checked by the shell from this plugin's manifest. With either
unmet the tile is absent from the notch rather than present and empty.

The quota bars need one thing more: the harness has to report its
windows at all. Claude Code does through its `statusLine` slot, which
`claude-hooks` has to own -- if you already had a `statusLine`
configured, the plugin leaves it alone and those bars stay hidden.
The other harnesses report `quota` records on the event feed instead:
Codex's five-hour and weekly limits off its session log, the session's
context fill on OpenCode, Pi and OMP, and OMP's provider windows when
its provider reports them. A local-model session with no subscription
has a context bar and nothing else -- an honest gap, not a false zero.
All bars hide once their reading goes stale, because every harness
reports those numbers only while a session is live.

## Install

```sh
aphotic plugin install agent-notch-tile
```
