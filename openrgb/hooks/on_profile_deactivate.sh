#!/usr/bin/env bash
# Aphotic plugin hook: fired when a ProfileEngine domain profile deactivates
# (its RESTORE phase). Single positional arg: the profile id.
#
# Reverts to whatever the remaining state resolves to -- the idle theme
# color, or breathing if an agent session is still live. The revert goes
# through the forced (black-flash) path, since reverting often means
# writing the exact mode+color OpenRGB already believes is applied, and
# several controllers silently no-op an identical resend.
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
openrgb_plugin_run profile deactivate "${1:-}"
