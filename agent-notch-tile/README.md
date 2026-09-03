# Agent Notch Tile

Docks a tile into Aphotic's notch showing, at a glance:

- **Waiting for input** — the primary signal. A harness that has stopped
  and is waiting on you badges the collapsed notch, so you get it without
  opening anything.
- **Active harness and phase** — one line: which harness is working and
  whether it is running, idle, or waiting.
- **Local provider VRAM** — what Ollama is holding on the GPU, read off
  the Resource Engine's claim table rather than a poll of its own.

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

## Install

```sh
aphotic plugin install agent-notch-tile
```
