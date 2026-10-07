#!/usr/bin/env bash
# pi-hooks/hooks/unwire.sh -- called by `aphotic plugin disable|remove
# pi-hooks` with no arguments. Removes the adapter symlink (and any
# hand-placed copy carrying the same name) from every pi-family harness
# discovery dir and deletes the hook config, so a disabled plugin reports
# nothing and a re-enabled one wires a single copy again.
set -euo pipefail

link_name="aphotic_pi_hook.js"

rm -f "$HOME/.pi/agent/extensions/$link_name"
rm -f "$HOME/.omp/agent/hooks/pre/$link_name"
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/aphotic/pi-hook.json"

for exe in pi omp; do
    if command -v "$exe" >/dev/null 2>&1 && pgrep -x "$exe" >/dev/null 2>&1; then
        echo "note: $exe is running; restart it to drop the hook." >&2
    fi
done
