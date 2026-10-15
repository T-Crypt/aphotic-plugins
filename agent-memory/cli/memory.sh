#!/usr/bin/env bash
# `aphotic memory` -- fold local agent session events into a durable memory.
#
# Sourced by core's plugin CLI dispatch (aphotic_plugin_cli_run), not
# executed, so aphotic_err/aphotic_warn/aphotic_log/aphotic_require and the
# XDG paths are already in scope exactly as they are for a core cmd_*.sh.
# That is also why every failure returns instead of exiting: a `return`
# leaves the dispatcher's subshell alive to report the status.
#
# This file is intentionally a dispatch line and nothing more. The fold,
# the caps, the digest format and the CLAUDE.md marker block are one
# Python file so the CLI and the workspace plane run exactly the same
# code, and stdlib only so there is nothing to install on a user's
# machine for a memory to work.
_agent_memory_plugin_dir="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"

_agent_memory_core="${_agent_memory_plugin_dir}/python/memory_core.py"

_agent_memory_usage() {
    echo "usage: aphotic memory <verb> [args]"
    echo
    echo "  build                          fold agent-events.jsonl into the store"
    echo "  projects [--json]              every project on record"
    echo "  errors [--project P] [--all]    failure signatures, open first"
    echo "  notes [--project P] [--json]    notes, newest first"
    echo "  note TEXT [--project P]        add a note"
    echo "  forget ID                      remove a note"
    echo "  resolve SIG [--project P]      close a failure signature"
    echo "  reopen SIG [--project P]       reopen a failure signature"
    echo "  context [--project P]          print the digest"
    echo "  stats [--json]                 totals"
    echo "  inject --enable|--disable|--status"
}

if [[ "${1:-}" == "help" || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    _agent_memory_usage
    return 0
fi

if [[ -z "${1:-}" ]]; then
    aphotic_err "memory needs a verb"
    _agent_memory_usage >&2
    return 1
fi

if [[ ! -f "$_agent_memory_core" ]]; then
    aphotic_err "memory engine missing: $_agent_memory_core"
    return 1
fi

aphotic_require python3 || return 1

_agent_memory_rc=0
python3 "$_agent_memory_core" "$@" || _agent_memory_rc=$?
return "$_agent_memory_rc"
