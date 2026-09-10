# Agent Graph

Live tool-call graph and run replay for
[Aphotic-Hypr](https://github.com/T-Crypt/aphotic-hypr)'s AI harnesses —
watch Claude Code / Codex sessions unfold as a node graph in the
Dashboard, then scrub back through a recorded run.

## Requires

Nothing beyond the shell itself — pure QML, no external binary. It reads
`~/.local/state/aphotic/agent-events.jsonl` and
`~/.local/state/aphotic/agent-runs/*.jsonl`, which the AI layer's own
harness hooks already write regardless of this plugin (see
`docs/archive/AGENT_TRACKING.md`).

## Activation

This is the first `ui-surface`-capability plugin (manifest v3, see
`docs/archive/PLUGIN_SYSTEM.md` in the Aphotic-Hypr repo). It declares
two surfaces — a Dashboard tab and its own Settings pane — and both
appear only when **all** of:

1. the installer's `ai` layer is on,
2. this plugin is installed and enabled, **and**
3. at least one harness (Claude Code or Codex) is actually configured
   — a bare Ollama install gives the graph nothing to render.

The graph reads the shell's shared agent event feed (`AgentEvents`) and
only asks it to run while the graph is actually on screen, so an
installed-but-unopened plugin costs nothing.

## Install

```sh
git clone https://github.com/T-Crypt/aphotic-plugins ~/aphotic-plugins
aphotic plugin install agent-graph
```

Or for plugin development (edits take effect without reinstalling):

```sh
aphotic plugin install agent-graph --link
```

## Exporting a run

The replay bar has two export buttons, both writing to your home
directory:

- **download** — `~/agent-run-<runId>.jsonl`, a byte-for-byte copy of the
  raw event archive, for feeding back into tooling.
- **summarize** — `~/agent-run-<runId>-summary.md`, a Markdown run report
  meant to be pasted into a PR description or a handoff note: model and
  locality, wall-clock duration, tool-call counts grouped by tool with
  per-tool error counts, every errored call with its offset into the run,
  subagent branches by agent type, and the session's status at the end.

The summary counts the whole recorded run. The graph above it only draws
up to `maxNodesPerSession` nodes per session (60–300 depending on the
quality tier), so on a long run the summary will legitimately report more
calls than the graph has room to show.

## What it does

Extracted whole from the shell's previous built-in Agent Graph dashboard
tab — no behavior change, just no longer part of the base install. See
`APHOTIC_UNIFIED_VISION.md` §2.4 in the Aphotic-Hypr repo for why this
extraction is a formal requirement, not a refactor of convenience.
