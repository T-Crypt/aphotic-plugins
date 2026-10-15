#!/usr/bin/env bash
# ios-dev/bin/lib.sh -- shared paths, config, the toolchain table and the
# session state file. Sourced by every other script in bin/.
#
# One rule holds this file together: the CLI is the only writer of the
# state file, and the QML surfaces are the only readers. Nothing else
# writes it, so there is no lock and no merge.

_IOS_LIB_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
_IOS_PLUGIN_DIR="$(cd "${_IOS_LIB_DIR}/.." && pwd)"

_IOS_TOOLS_DIR="${_IOS_PLUGIN_DIR}/tools"
_IOS_XTOOL_DIR="${_IOS_TOOLS_DIR}/xtool"
_IOS_XTOOL="${_IOS_XTOOL_DIR}/AppRun"

_IOS_CONFIG_HOME="${APHOTIC_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/aphotic}"
_IOS_CONFIG_DIR="${_IOS_CONFIG_HOME}/plugins/ios-dev"
_IOS_CONFIG="${_IOS_CONFIG_DIR}/config"
_IOS_STATE="${_IOS_CONFIG_DIR}/state.json"

# xtool ships one prebuilt archive per architecture. Both are pinned by
# sha256 because the release page publishes no checksums, so the pin is
# the only thing standing between a user and whatever a replaced asset
# happens to be. Update all three numbers together when bumping.
_IOS_XTOOL_VERSION="1.22.2"
_IOS_XTOOL_SHA_X86_64="e3176cdf861f58b7f135c755c7bfaec92d0568ef826027b4e5e3d82b3219ddfe"
_IOS_XTOOL_SHA_AARCH64="a42962f19874205ddd807ee4f97687fc83ddc9be176a8b1122a94af3de58d990"

_IOS_SWIFT_BIN="swift"
_IOS_XCODE_URL="https://developer.apple.com/download/all/?q=Xcode"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

# Sourced, not parsed: it is a shell file this plugin writes and the user
# is invited to edit. A missing file is not an error, it is a machine that
# has not run setup yet.
_ios_load_config() {
    IOS_BUNDLE_PREFIX="com.example"
    IOS_APPS_DIR="$HOME/Projects/ios"
    # shellcheck source=/dev/null
    [[ -r "$_IOS_CONFIG" ]] && . "$_IOS_CONFIG"
    IOS_APPS_DIR="${IOS_APPS_DIR/#\~/$HOME}"
}

_ios_save_config() {
    mkdir -p "$_IOS_CONFIG_DIR"
    cat >"${_IOS_CONFIG}.tmp" <<EOF
# ios-dev settings. Written by 'aphotic ios setup'; edit freely.
IOS_BUNDLE_PREFIX="${IOS_BUNDLE_PREFIX}"
IOS_APPS_DIR="${IOS_APPS_DIR}"
EOF
    mv "${_IOS_CONFIG}.tmp" "$_IOS_CONFIG"
}

# ---------------------------------------------------------------------------
# The dev layer gate
# ---------------------------------------------------------------------------

# The gate the shell already evaluates for every surface, evaluated here
# too so the command matches what the user can see. A layer-gated plugin
# whose command still ran would be a second, quieter way in.
_ios_layer_enabled() {
    local toml="${APHOTIC_DOTS_DIR:-}/aphotic.toml"
    [[ -r "$toml" ]] || return 0
    local list
    list="$(sed -n 's/.*layers[[:space:]]*=[[:space:]]*\[\([^]]*\)\].*/\1/p' "$toml" | tr -d '"' | tr ',' ' ')"
    [[ " $list " == *" dev "* ]]
}

_ios_require_layer() {
    _ios_layer_enabled && return 0
    cat >&2 <<'EOF'
ios-dev is gated on the dev layer, which this install does not carry.

Every surface this plugin declares is already hidden, so the shell is
behaving correctly. To turn the layer on, add it and let the installer
record it:

  ./install.sh --with dev

After that, run: aphotic ios doctor
EOF
    return 1
}

# ---------------------------------------------------------------------------
# The toolchain table
#
# A table rather than a chain of conditionals, because the doctor output,
# the workspace checklist and setup's step list all read the same five
# facts and must not drift apart. Order is the order the user sees.
# ---------------------------------------------------------------------------

_IOS_CHECK_IDS=(swift sdk xtool usbmuxd)

_ios_check_label() {
    case "$1" in
        swift) echo "Swift toolchain" ;;
        sdk) echo "Darwin SDK" ;;
        xtool) echo "xtool" ;;
        usbmuxd) echo "usbmuxd" ;;
    esac
}

_ios_check_ok() {
    case "$1" in
        swift) command -v "$_IOS_SWIFT_BIN" >/dev/null 2>&1 ;;
        sdk) command -v "$_IOS_SWIFT_BIN" >/dev/null 2>&1 && "$_IOS_SWIFT_BIN" sdk list 2>/dev/null | grep -qx darwin ;;
        xtool) [[ -x "$_IOS_XTOOL" ]] ;;
        usbmuxd) command -v usbmuxd >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

# Never fails. A missing detail is not an error, it is the state a machine
# is in before setup, and a 127 from a probe that ran `swift` on a host
# without swift would take the whole doctor down under `set -e`.
_ios_check_detail() {
    local out=""
    case "$1" in
        swift) out="$("$_IOS_SWIFT_BIN" --version 2>/dev/null | head -n1 || true)" ;;
        sdk) out="$("$_IOS_SWIFT_BIN" sdk list 2>/dev/null | awk '/^darwin/{print $2; exit}' || true)" ;;
        xtool) out="$("$_IOS_XTOOL" --version 2>/dev/null | head -n1 || true)" ;;
        usbmuxd) out="$(usbmuxd version 2>/dev/null | head -n1 || true)" ;;
    esac
    printf '%s\n' "$out"
    return 0
}

# The one instruction that matters most is not a command, because no
# command can carry it out: the SDK lives only inside Apple's Xcode
# archive, and that download needs a browser session. Everything else
# here is something `aphotic ios setup` does.
_ios_check_fix() {
    case "$1" in
        swift) echo "aphotic ios setup" ;;
        sdk)
            echo "download the matching Xcode archive from ${_IOS_XCODE_URL}, then: xtool sdk install <path to the .xip>"
            ;;
        xtool) echo "aphotic ios setup" ;;
        usbmuxd) echo "aphotic ios setup" ;;
    esac
}

_ios_toolchain_ready() {
    local id
    for id in "${_IOS_CHECK_IDS[@]}"; do
        _ios_check_ok "$id" || return 1
    done
    return 0
}

# ---------------------------------------------------------------------------
# Session state
#
# One field carries the phase, not a boolean per phase. Two booleans that
# must agree is how a session reads as building and running at once.
#
# Three phases this phase of the plugin can honestly report. `xtool dev
# run` owns the compile and the install inside one process and reports
# neither, so claiming a building phase here would be inventing a state.
# ---------------------------------------------------------------------------

_IOS_STATE_SCHEMA=1

_ios_state_default() {
    jq -n --argjson schema "$_IOS_STATE_SCHEMA" '{
        schema: $schema,
        toolchain: [],
        ready: false,
        devices: [],
        session: {state: "idle", project: "", detail: "", pid: 0},
        updated: 0
    }'
}

_ios_state_init() {
    if [[ ! -s "$_IOS_STATE" ]]; then
        mkdir -p "$_IOS_CONFIG_DIR"
        _ios_state_default >"$_IOS_STATE"
    fi
}

# Refreshes the toolchain, device and session blocks in place. The session
# block is preserved rather than rewritten, because this runs on a timer
# from the shell while a build is in flight.
_ios_state_refresh() {
    command -v jq >/dev/null 2>&1 || return 0
    _ios_state_init

    local rows="[]" id ok detail
    for id in "${_IOS_CHECK_IDS[@]}"; do
        ok="false"
        _ios_check_ok "$id" && ok="true"
        detail="$(_ios_check_detail "$id")"
        rows="$(jq -c --arg id "$id" --arg label "$(_ios_check_label "$id")" \
            --argjson ok "$ok" --arg detail "$detail" --arg fix "$(_ios_check_fix "$id")" \
            '. + [{id: $id, label: $label, ok: $ok, detail: $detail, fix: $fix}]' <<<"$rows")"
    done

    local ready="false"
    _ios_toolchain_ready && ready="true"

    local devices="[]"
    devices="$(_ios_devices_json 2>/dev/null || echo '[]')"

    local tmp="${_IOS_STATE}.tmp"
    jq --argjson rows "$rows" --argjson ready "$ready" --argjson devices "$devices" \
        --argjson now "$(date +%s)" \
        '.toolchain = $rows | .ready = $ready | .devices = $devices | .updated = $now' \
        "$_IOS_STATE" >"$tmp" 2>/dev/null && mv "$tmp" "$_IOS_STATE"
}

_ios_state_get() {
    _ios_state_init
    cat "$_IOS_STATE"
}

_ios_session_set() {
    local state="$1" project="${2:-}" detail="${3:-}" pid="${4:-0}"
    command -v jq >/dev/null 2>&1 || return 0
    _ios_state_init
    local tmp="${_IOS_STATE}.tmp"
    jq --arg state "$state" --arg project "$project" --arg detail "$detail" \
        --argjson pid "$pid" --argjson now "$(date +%s)" \
        '.session = {state: $state, project: $project, detail: $detail, pid: $pid} | .updated = $now' \
        "$_IOS_STATE" >"$tmp" 2>/dev/null && mv "$tmp" "$_IOS_STATE"
}

# ---------------------------------------------------------------------------
# Devices
# ---------------------------------------------------------------------------

# xtool's own list, because it is the same answer the build uses. A second
# reader would be a second opinion about what is plugged in.
_ios_devices_json() {
    [[ -x "$_IOS_XTOOL" ]] || { echo "[]"; return 0; }
    local out
    out="$("$_IOS_XTOOL" devices --no-wait 2>/dev/null || true)"
    [[ -n "$out" ]] || { echo "[]"; return 0; }
    printf '%s\n' "$out" | jq -R -s '
        split("\n") | map(select(length > 0)) | map(
            capture("^(?<name>[^\\[]+)\\s*\\[(?<transport>[^\\]]*)\\]:\\s*(?<udid>\\S+)$")
        ) | map({udid: .udid, name: (.name | sub("^\\s+"; "") | sub("\\s+$"; "")), transport: .transport, version: ""})
    '
}

# ---------------------------------------------------------------------------
# Project discovery
# ---------------------------------------------------------------------------

# An xtool project is a directory holding Package.swift. The nearest one
# walking up from the caller's directory is the one they mean, which is
# what makes `aphotic ios run` work from a subdirectory.
_ios_find_project() {
    local start="${1:-$PWD}" dir
    dir="$(cd "$start" 2>/dev/null && pwd)" || return 1
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/Package.swift" ]] && { echo "$dir"; return 0; }
        dir="$(dirname "$dir")"
    done
    return 1
}

_ios_bundle_id_of() {
    local project="$1" name
    name="$(basename "$project")"
    echo "${IOS_BUNDLE_PREFIX}.${name}"
}
