#!/usr/bin/env bash
# `aphotic ios` -- iOS development on this machine.
#
# A thin front door. Core's plugin CLI dispatch sources this file
# (aphotic_plugin_cli_run), which hands every argument to the engine, and
# the engine owns the layer gate, the usage text and the exit codes. One
# place decides, so the command cannot be a second way in past the gate
# the registry already evaluates for every surface this plugin declares.

_ios_cli_dir="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"

"${_ios_cli_dir}/bin/iosctl" "$@"
