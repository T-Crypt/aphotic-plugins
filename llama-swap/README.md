# llama-swap

Adds an AI tile to Aphotic's notch for a configured llama-swap host.

The tile shows:

- Host reachability and every running model.
- Each local model's measured GPU memory claim.
- Live generation speed and context usage while the tile is visible.
- Inference mode state with an Enter or Exit control.
- An Unload control for each model.

The tile starts no polling loop. Aphotic's shared llama-swap services own
host and generation polling, and the tile holds generation stats only while
you can see it. The plugin runs a one-shot local process lookup when the
visible model list changes so it can join model ports to measured VRAM claims.

## Requirements

- The `ai` layer installed (`requires_layer = "ai"`).
- A llama-swap host set in Settings → AI. Without one, the tile explains
  what is missing and starts no process lookup.

## Install

```sh
aphotic plugin install llama-swap
```
