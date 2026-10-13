#!/usr/bin/env bash
# `aphotic xfreerdp` -- profile-driven RDP sessions.
#
# Sourced by core's plugin CLI dispatch (aphotic_plugin_cli_run), not
# executed, so aphotic_err/aphotic_warn/aphotic_log/aphotic_require and the
# XDG paths are already in scope exactly as they are for a core cmd_*.sh.
# That is also why every failure returns instead of exiting: a `return`
# leaves the dispatcher's subshell alive to report the status.
#
# One profile lives in ~/.config/aphotic/plugins/xfreerdp/settings.json,
# written by the Settings > Network > Remote Desktop pane and read by
# nothing else. No password is ever read from it, passed on a command line
# or stored anywhere: the session asks through FREERDP_ASKPASS, which is
# why `ps` never shows a password.
#
# The argv below follows the proven wrapper this replaces (~/.local/bin/
# work-rdp) field for field, including the two that look odd and are not:
# an initial /size: alongside /dynamic-resolution (the session still needs
# a starting geometry), and the single-dash -grab-keyboard (the only way
# the Windows key reaches the remote session).

# Resolved with shell builtins only, no `dirname`: the CLI has to answer
# `status` on a machine where PATH is empty or broken, and this line runs
# before anything can check.
_rdp_plugin_dir="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
_rdp_askpass="${_rdp_plugin_dir}/bin/rdp-askpass"
_rdp_settings="${APHOTIC_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/aphotic}/plugins/xfreerdp/settings.json"

_rdp_usage() {
    cat <<'EOF'
usage: aphotic xfreerdp <command>

  connect [--dry-run]   Start the session, or focus it when it is already up
                        --dry-run prints the xfreerdp3 argv and does nothing else
  status                Print running, not-running or unknown
  disconnect            Close the session window

Settings live in ~/.config/aphotic/plugins/xfreerdp/settings.json, written by
Settings > Network > Remote Desktop. No password is stored or passed on the
command line; the session prompts for it.
EOF
}

# hyprctl is only usable inside a live session. Both halves matter: a
# hyprctl on PATH with no compositor to talk to fails the same way a missing
# one does, and `status` has to tell the pane that apart from "not running".
_rdp_hypr_ready() {
    command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]
}

# The window class, which is also what the compositor matches on. Read from
# the profile, falling back to the same default the pane ships, so `status`
# still answers on a machine that has never opened the pane.
_rdp_class() {
    local class=""
    if [[ -r "$_rdp_settings" ]] && command -v jq >/dev/null 2>&1; then
        class="$(jq -r '.window.class // ""' "$_rdp_settings" 2>/dev/null || true)"
    fi
    printf '%s' "${class:-work-rdp}"
}

_rdp_class_present() {
    local class="$1" clients
    clients="$(hyprctl clients -j 2>/dev/null)" || return 1
    jq -e --arg c "$class" 'any(.[]?; .class == $c)' <<<"$clients" >/dev/null 2>&1
}

# Waits for the window to appear after a spawn so pinning and fullscreen
# have something to act on. Bounded and short: this is a one-shot after a
# spawn, not a watcher, and a CLI has no compositor event source to wait on
# instead (the pane's own Hypr event stream is the place for that).
_rdp_wait_for_class() {
    local class="$1" i
    for ((i = 0; i < 20; i++)); do
        if _rdp_class_present "$class"; then
            return 0
        fi
        sleep 0.25
    done
    return 1
}

# Every field of the profile, in one jq call and in the argv's own order.
# Fields are joined with a unit separator rather than newlines so a value
# can hold anything printable without splitting the stream, and every key is
# defaulted here: a settings file holding only `host` still produces a
# complete session, because the merge lives in the pane and this is the
# reader that has to agree with it.
#
# The trailing "end" is a sentinel, not a field: `read -a` drops a trailing
# empty field, and `extra` is empty in every profile that has no free-form
# arguments, so without it the last field would sometimes not exist at all.
_rdp_read_settings() {
    jq -r '
        # jq'"'"'s `//` operator yields the right hand side for false as well as
        # null, so `.mic.enabled // true` would turn a disabled microphone
        # back on. This is the null-only default both this reader and the
        # pane actually mean.
        def d($v; $fallback): if $v == null then $fallback else $v end;
        [
          d(.host; ""),
          (d(.port; 3389) | tostring),
          d(.user; ""),
          d(.sec; "nla"),
          d(.cert; "ignore"),
          (d(.mic.enabled; true) | tostring),
          d(.mic.device; ""),
          d(.speaker.device; ""),
          (d(.camera.enabled; true) | tostring),
          d(.resolution.mode; "dynamic"),
          (d(.resolution.width; 1920) | tostring),
          (d(.resolution.height; 1080) | tostring),
          d(.window.class; "work-rdp"),
          (d(.window.grab_keyboard; true) | tostring),
          (d(.window.auto_reconnect; true) | tostring),
          d(.window.gfx; "AVC420"),
          d(.window.workspace; "none"),
          (d(.window.fullscreen; false) | tostring),
          d(.extra; ""),
          "end"
        ] | join("\u001f")
    ' "$_rdp_settings"
}

# Fills _rdp_argv. Order is the baseline's, and the conditionals are the
# only places a value can remove a flag entirely: no /u: when the profile
# names no user (FreeRDP prompts instead), no /microphone: when the mic is
# off, no /dvc:rdpecam when the camera is off.
_rdp_build_argv() {
    local -a f
    local -a extra
    IFS=$'\x1f' read -r -a f <<<"$1"

    _rdp_argv=("-v:${f[0]}:${f[1]}")

    if [[ -n "${f[2]}" ]]; then
        _rdp_argv+=("/u:${f[2]}")
    fi

    _rdp_argv+=("/sec:${f[3]}")
    _rdp_argv+=("/cert:${f[4]}")
    _rdp_argv+=("/size:${f[10]}x${f[11]}")

    if [[ "${f[9]}" == "dynamic" ]]; then
        _rdp_argv+=("/dynamic-resolution")
    fi

    if [[ "${f[8]}" == "true" ]]; then
        _rdp_argv+=("/dvc:rdpecam")
    fi

    _rdp_argv+=("/gfx:${f[15]}")

    if [[ -n "${f[7]}" ]]; then
        _rdp_argv+=("/sound:sys:pulse,dev:${f[7]}")
    else
        _rdp_argv+=("/sound:sys:pulse")
    fi

    if [[ "${f[5]}" == "true" ]]; then
        if [[ -n "${f[6]}" ]]; then
            _rdp_argv+=("/microphone:sys:pulse,dev:${f[6]}")
        else
            _rdp_argv+=("/microphone:sys:pulse")
        fi
    fi

    _rdp_argv+=("/wm-class:${f[12]}")

    if [[ "${f[14]}" == "true" ]]; then
        _rdp_argv+=("/auto-reconnect")
    fi

    if [[ "${f[13]}" == "true" ]]; then
        _rdp_argv+=("-grab-keyboard")
    fi

    # The free-form tail is split once here, never re-expanded, so a value
    # with a quote or a space in it reaches xfreerdp as the user typed it.
    if [[ -n "${f[18]}" ]]; then
        read -r -a extra <<<"${f[18]}"
        _rdp_argv+=("${extra[@]}")
    fi

    _rdp_host="${f[0]}"
    _rdp_workspace="${f[16]}"
    _rdp_fullscreen="${f[17]}"
    _rdp_class_value="${f[12]}"
}

_rdp_cmd_connect() {
    local dry_run="false"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run="true"; shift ;;
            *) aphotic_err "unknown option for 'xfreerdp connect': $1"; return 1 ;;
        esac
    done

    aphotic_require jq || return 1

    if [[ ! -f "$_rdp_settings" ]]; then
        aphotic_err "no Remote Desktop profile yet: Settings > Network > Remote Desktop"
        return 1
    fi

    # A connect racing a pane save must fail loudly rather than launch half
    # a session off a truncated file. The pane writes the whole document in
    # one write, so the window for this is small by construction.
    if ! jq empty "$_rdp_settings" >/dev/null 2>&1; then
        aphotic_err "cannot read ${_rdp_settings}: not valid JSON"
        return 1
    fi

    local line
    line="$(_rdp_read_settings)" || { aphotic_err "cannot read ${_rdp_settings}"; return 1; }

    local -a _rdp_argv
    _rdp_build_argv "$line"

    # A profile with no host is a pane that was never filled in, not a
    # machine to connect to, and the message names where to go.
    if [[ -z "$_rdp_host" ]]; then
        aphotic_err "no Remote Desktop profile yet: Settings > Network > Remote Desktop"
        return 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        printf '%s\n' "${_rdp_argv[@]}"
        return 0
    fi

    local class="${_rdp_class_value}"

    # Toggle first, the way the existing custom.lua bind does: a second
    # press focuses the session instead of starting a second one. Skipped
    # entirely without a compositor, so this still works from a bare TTY.
    if _rdp_hypr_ready; then
        if _rdp_class_present "$class"; then
            hyprctl dispatch focuswindow "class:^(${class})\$" >/dev/null
            return 0
        fi
    fi

    # FreeRDP only consults FREERDP_ASKPASS when no password was supplied,
    # which is always the case here. Must be a bare executable path: FreeRDP
    # appends its own prompt arguments.
    if [[ ! -x "$_rdp_askpass" ]]; then
        aphotic_err "${_rdp_askpass} is not executable -- reinstall the plugin"
        return 1
    fi
    export FREERDP_ASKPASS="$_rdp_askpass"

    aphotic_require xfreerdp3 || return 1

    # Detached so the first press does not block on the password prompt, and
    # with no redirect, so FreeRDP's own diagnostics stay on the session's
    # stderr where they have always been.
    if ! setsid -f xfreerdp3 "${_rdp_argv[@]}"; then
        aphotic_err "xfreerdp3 failed to start"
        return 1
    fi

    if ! _rdp_hypr_ready; then
        return 0
    fi

    if [[ -n "$_rdp_workspace" && "$_rdp_workspace" != "none" ]]; then
        if _rdp_wait_for_class "$class"; then
            hyprctl dispatch movetoworkspacesilent "${_rdp_workspace},class:^(${class})\$" >/dev/null
        else
            aphotic_warn "the session window did not appear in time -- not pinned to ${_rdp_workspace}"
        fi
    fi

    # Off by default: SUPER + SHIFT + F is the manual entry and stays the
    # one people know.
    if [[ "$_rdp_fullscreen" == "true" ]]; then
        if _rdp_wait_for_class "$class"; then
            hyprctl dispatch focuswindow "class:^(${class})\$" >/dev/null
            hyprctl dispatch fullscreen 0 >/dev/null
        else
            aphotic_warn "the session window did not appear in time -- not fullscreened"
        fi
    fi

    return 0
}

# Never fails, and prints exactly one word, because this is the pane's
# status source: an unreachable compositor is `unknown`, which is a fact
# about the machine, not an error about the session.
_rdp_cmd_status() {
    local class
    class="$(_rdp_class)"

    if ! _rdp_hypr_ready; then
        echo "unknown"
        return 0
    fi

    if _rdp_class_present "$class"; then
        echo "running"
    else
        echo "not-running"
    fi
    return 0
}

_rdp_cmd_disconnect() {
    local class
    class="$(_rdp_class)"

    if ! _rdp_hypr_ready; then
        aphotic_err "no compositor to close the session with"
        return 1
    fi

    if ! _rdp_class_present "$class"; then
        aphotic_warn "no Remote Desktop session is open"
        return 0
    fi

    hyprctl dispatch closewindow "class:^(${class})\$" >/dev/null
    return 0
}

_rdp_verb="${1:-}"
shift || true

case "$_rdp_verb" in
    connect)
        _rdp_cmd_connect "$@"
        return $?
        ;;
    status)
        _rdp_cmd_status "$@"
        return $?
        ;;
    disconnect)
        _rdp_cmd_disconnect "$@"
        return $?
        ;;
    "" | -h | --help | help)
        _rdp_usage
        return 0
        ;;
    *)
        aphotic_err "unknown command for 'aphotic xfreerdp': ${_rdp_verb}"
        _rdp_usage >&2
        return 1
        ;;
esac
