#!/usr/bin/env bash
# Aphotic plugin hook: fired for each AI-agent lifecycle event, with the
# event JSON on stdin -- the same wire format Agent Graph and the bar's
# Live Agent Activity already consume (agent_hook.py's record shape:
# sessionId / event / status / harness / tool / ...).
#
# While any session is live the lighting breathes the current theme
# accent; when the last one stops or ends it goes back to static. Only
# the transitions apply anything -- putting a full device batch in the
# path of every single tool call would cost a lot for no visible change.
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
openrgb_plugin_run agent-event
