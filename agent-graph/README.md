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
`docs/archive/PLUGIN_SYSTEM.md` in the Aphotic-Hypr repo). Its Dashboard
tab only appears when **all** of:

1. the installer's `ai` layer is on,
2. this plugin is installed and enabled, **and**
3. at least one harness (Claude Code or Codex) is actually configured
   — a bare Ollama install gives the graph nothing to render.

## Install

```sh
git clone https://github.com/T-Crypt/aphotic-plugins ~/aphotic-plugins
aphotic plugin install agent-graph
```

Or for plugin development (edits take effect without reinstalling):

```sh
aphotic plugin install agent-graph --link
```

## What it does

Extracted whole from the shell's previous built-in Agent Graph dashboard
tab — no behavior change, just no longer part of the base install. See
`APHOTIC_UNIFIED_VISION.md` §2.4 in the Aphotic-Hypr repo for why this
extraction is a formal requirement, not a refactor of convenience.
