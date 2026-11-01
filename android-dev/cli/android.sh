#!/usr/bin/env bash
# `aphotic android` -- Android development on this machine.
#
# A thin front door. Core's plugin CLI dispatch sources this file
# (aphotic_plugin_cli_run), which hands every argument to the engine, and
# the engine owns the usage text and the exit codes. One place decides,
# so the command is never a second way past anything the engine checks.

_android_cli_dir="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"

"${_android_cli_dir}/bin/androidctl" "$@"
