#!/usr/bin/env bash
# codex-hooks/hooks/install-deps.sh -- called by `aphotic plugin
# install|enable codex-hooks` via the manifest's `[requires].install_script`
# when the `codex` binary is missing, in place of core's default
# `yay -S <binary-name>`.
#
# Why this exists: there is no AUR package named `codex`. Core's default
# resolves a missing binary to a package of the same name, so
# `yay -S codex` lands on `codex-bin` -- an unrelated Electron note-taking
# app for CS students -- whose `electron32` dependency pulls a full
# chromium source tree. That is where the ~18GB `chromium-mirror` download
# came from: not Codex, and not anything this plugin needs.
#
# `openai-codex-bin` is the correct AUR package and is offered below as
# the fallback. OpenAI's own installer is the default because it is the
# upstream-supported path and keeps itself updated.
set -euo pipefail

if command -v codex >/dev/null 2>&1; then
    exit 0
fi

echo "codex-hooks needs OpenAI's Codex CLI, which isn't on PATH."
echo
echo "  upstream installer:  curl -fsSL https://chatgpt.com/codex/install.sh | sh"
echo "  or from the AUR:     yay -S openai-codex-bin"
echo

# Piping a remote script into a shell is not something to do silently on
# the user's behalf -- same reason core shells out to an *interactive*
# `yay -S` rather than `--noconfirm`: an install script is arbitrary code
# and the user gets to see it coming. Non-interactive callers are told
# what to run instead of having it run for them.
if [[ ! -t 0 ]]; then
    echo "Not running interactively -- skipping the install." >&2
    echo "Run one of the commands above, then: aphotic plugin install codex-hooks" >&2
    exit 0
fi

read -r -p "Run the upstream installer now? [y/N] " reply
if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Skipped. Codex hooks are wired either way and start reporting once codex is on PATH."
    exit 0
fi

curl -fsSL https://chatgpt.com/codex/install.sh | sh

if ! command -v codex >/dev/null 2>&1; then
    echo
    echo "Installer finished but 'codex' still isn't on PATH -- it usually lands in ~/.local/bin;" >&2
    echo "make sure that's in your PATH, then re-run 'aphotic plugin list' to confirm." >&2
fi
