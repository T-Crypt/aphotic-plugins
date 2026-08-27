#!/usr/bin/env bash
# Aphotic plugin hook: fired when a project is opened from the
# launcher's "@" project-switcher (see PLUGIN_SYSTEM.md in the
# aphotic-hypr repo for the contract). Runs standalone -- no access to
# aphotic's own helper functions, only what's on PATH. Single positional
# arg: the project's absolute path.
#
# Deliberately does NOT run `direnv allow` on the project's behalf --
# that would defeat the whole point of direnv's per-directory trust
# step (an .envrc can contain arbitrary shell code). This just makes
# the presence of an unreviewed .envrc visible right when you jump into
# a project, instead of only finding out from direnv's own shell-hook
# error the first time a command runs there.
set -euo pipefail

project_path="${1:-}"
[[ -n "$project_path" && -f "$project_path/.envrc" ]] || exit 0

command -v notify-send >/dev/null 2>&1 || exit 0

notify-send "direnv" "$(basename "$project_path") has a .envrc -- run 'direnv allow' in the new terminal if you haven't yet" 2>/dev/null || true
