# Hardware Advisor

Adds a **Hardware Advisor** pane to Aphotic's Settings window that
answers one question: which local model actually fits this machine.

- **Scan on demand** — one button runs `llmfit` against your real
  CPU/GPU. Never polled: a scan shells out to live hardware detection
  (`nvidia-smi`, `rocm-smi`, …), so running it on a timer would spawn
  those repeatedly for no reason.
- **Detected hardware, shown back to you** — CPU, cores, RAM, and the
  GPU with its VRAM, exactly as `llmfit` saw it. If `llmfit` warns while
  still succeeding, the warning is surfaced rather than hidden behind a
  clean exit code: a warning here means the detected hardware itself may
  be wrong.
- **One-click Ollama pull** — but only for a tag `llmfit` itself
  confirms is real (`ollama_name`). Its recommendation pool skews to
  community fine-tunes in vLLM/AWQ/GPTQ formats that were never
  published to Ollama, so a guessed tag would have been a pull that
  always failed. No confirmed tag, no button.

Deliberately not here: chat providers, API keys, the Ollama host and the
model store. Those are core's AI pane, and `llmfit` has nothing to do
with them — it is a recommendation tool, not a provider.

## Requirements

- The `ai` layer installed (`requires_layer = "ai"`). Without it the
  pane is absent from Settings rather than present and empty.
- The `llmfit` binary on `PATH` (`requires = { binaries = ["llmfit"] }`).
  Aphotic does not bundle it and cannot install it for you; the `ai`
  profile layer pulls it in, or install it directly:

  ```sh
  curl -fsSL https://llmfit.axjns.dev/install.sh | sh
  ```

  With the layer on but the binary missing, the pane says so instead of
  silently offering a Scan button that cannot work.

The one-click pull additionally needs Ollama reachable — it hands the
tag to core's provider, which is what actually pulls.

## Install

```sh
aphotic plugin install llm-fit
```
