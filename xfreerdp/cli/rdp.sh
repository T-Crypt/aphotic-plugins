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
# why `ps` never shows a password. The free-form `extra` tail is the one
# field a password could reach the argv through, so a flag that carries one
# is refused there (_rdp_is_secret_flag) instead of being handed over.
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

# True for an extra argument that would put a secret in this process's
# command line, where `ps` shows it. FreeRDP takes the password there, and
# `/p:`, `-p:` and `+p:` are one flag to its own parser, which warns about
# the exposure itself. /pth:, /assistance: and a credential inside a gateway
# or proxy argument leak the same way. This plugin asks through
# FREERDP_ASKPASS instead and says so, so these are refused rather than
# handed to xfreerdp.
_rdp_is_secret_flag() {
    local key="$1"

    # FreeRDP drops one of /, - or + from the front of every argument, so
    # which spelling a user typed says nothing about which flag it is.
    case "$key" in
        /* | -* | +*) key="${key#[-/+]}" ;;
        *) return 1 ;;
    esac
    key="${key#[-/+]}"

    case "$key" in
        p | p:* | pth:* | assistance:*)
            return 0
            ;;
    esac

    # A credential carried inside a gateway or proxy string: `,p:<secret>` in
    # the gateway's comma separated form, `user:password@` in a proxy URL.
    # Both are anchored to those shapes, so a gateway to a host called
    # `rdp:443` and a proxy URL with no password in it are left alone.
    if [[ "$key" == gateway:* && "$key" =~ (^|,)p: ]]; then
        return 0
    fi
    if [[ "$key" == proxy:* && "$key" =~ :[^:@/]*@ ]]; then
        return 0
    fi

    return 1
}

# Every field of the profile, from one jq call, as name/value pairs with a
# NUL after each half. Nothing here is line based: jq writes a real newline
# for a "\n" in a value, and a reader that stopped at one used to cut the
# record short and abort the CLI with a bash unbound variable instead of an
# error. The names come out of this list too, so a refusal can name the
# setting someone has to fix rather than an index nobody can map back.
#
# Every key is defaulted here: a settings file holding only `host` still
# produces a complete session, because the merge lives in the pane and this
# is the reader that has to agree with it.
_rdp_read_settings() {
    jq -j '
        # `//` yields the right hand side for false as well as null, so
        # `.mic.enabled // true` would turn a disabled microphone back on.
        # This is the null-only default both this reader and the pane mean.
        def d($v; $fallback): if $v == null then $fallback else $v end;
        [
          ["host",                   d(.host; "")],
          ["port",                   (d(.port; 3389) | tostring)],
          ["user",                   d(.user; "")],
          ["sec",                    d(.sec; "nla")],
          ["cert",                   d(.cert; "ignore")],
          ["mic.enabled",            (d(.mic.enabled; true) | tostring)],
          ["mic.device",             d(.mic.device; "")],
          ["speaker.device",         d(.speaker.device; "")],
          ["camera.enabled",         (d(.camera.enabled; true) | tostring)],
          ["resolution.mode",        d(.resolution.mode; "dynamic")],
          ["resolution.width",       (d(.resolution.width; 1920) | tostring)],
          ["resolution.height",      (d(.resolution.height; 1080) | tostring)],
          ["window.class",           d(.window.class; "work-rdp")],
          ["window.grab_keyboard",   (d(.window.grab_keyboard; true) | tostring)],
          ["window.auto_reconnect",  (d(.window.auto_reconnect; true) | tostring)],
          ["window.gfx",             d(.window.gfx; "AVC420")],
          ["window.workspace",       d(.window.workspace; "none")],
          ["window.fullscreen",      (d(.window.fullscreen; false) | tostring)],
          ["extra",                  d(.extra; "")]
        ]
        | .[]
        | .[0] + "\u0000" + (.[1] | tostring) + "\u0000"
    ' "$_rdp_settings"
}

# Fills _rdp_argv. Order is the baseline's, and the conditionals are the
# only places a value can remove a flag entirely: no /u: when the profile
# names no user (FreeRDP prompts instead), no /microphone: when the mic is
# off, no /dvc:rdpecam when the camera is off.
#
# Returns non-zero, with a message someone can act on, for a profile this
# reader cannot turn into a command line: a record that did not arrive
# whole, a value with a line break in it, or a password flag. Anything a
# user can write into the settings file has to come back as an aphotic_err,
# never as a raw bash error out of the caller's `set -e`.
_rdp_build_argv() {
    local -a rec
    local -a extra
    local -A f=()
    local i name value n

    mapfile -d '' -t rec < <(_rdp_read_settings)
    n=${#rec[@]}

    # The record is name/value pairs in the order above, headed by `host`
    # and tailed by `extra`. Anything else means the record was damaged on
    # the way here (a NUL inside a value, a read cut short), and refusing
    # beats guessing at a shape that is already wrong.
    if (( n < 2 || n % 2 != 0 )) || [[ "${rec[0]}" != "host" || "${rec[n - 2]}" != "extra" ]]; then
        aphotic_err "cannot read ${_rdp_settings}: it is not a profile this plugin writes"
        return 1
    fi

    for ((i = 0; i < n; i += 2)); do
        name="${rec[i]}"
        value="${rec[i + 1]}"
        # Every field is a single line, because the pane's inputs are and
        # FreeRDP has nothing to do with a line break in a host or a flag.
        # Refusing by name is also what stops a pasted newline from cutting
        # `extra` short and dropping the flags after it without a word.
        if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
            aphotic_err "the '${name}' setting has a line break -- fix it in Settings > Network > Remote Desktop"
            return 1
        fi
        f["$name"]="$value"
    done

    _rdp_argv=("-v:${f[host]:-}:${f[port]:-}")

    if [[ -n "${f[user]:-}" ]]; then
        _rdp_argv+=("/u:${f[user]}")
    fi

    _rdp_argv+=("/sec:${f[sec]:-}")
    _rdp_argv+=("/cert:${f[cert]:-}")
    _rdp_argv+=("/size:${f[resolution.width]:-}x${f[resolution.height]:-}")

    if [[ "${f[resolution.mode]:-}" == "dynamic" ]]; then
        _rdp_argv+=("/dynamic-resolution")
    fi

    if [[ "${f[camera.enabled]:-}" == "true" ]]; then
        _rdp_argv+=("/dvc:rdpecam")
    fi

    _rdp_argv+=("/gfx:${f[window.gfx]:-}")

    if [[ -n "${f[speaker.device]:-}" ]]; then
        _rdp_argv+=("/sound:sys:pulse,dev:${f[speaker.device]}")
    else
        _rdp_argv+=("/sound:sys:pulse")
    fi

    if [[ "${f[mic.enabled]:-}" == "true" ]]; then
        if [[ -n "${f[mic.device]:-}" ]]; then
            _rdp_argv+=("/microphone:sys:pulse,dev:${f[mic.device]}")
        else
            _rdp_argv+=("/microphone:sys:pulse")
        fi
    fi

    _rdp_argv+=("/wm-class:${f[window.class]:-}")

    if [[ "${f[window.auto_reconnect]:-}" == "true" ]]; then
        _rdp_argv+=("/auto-reconnect")
    fi

    if [[ "${f[window.grab_keyboard]:-}" == "true" ]]; then
        _rdp_argv+=("-grab-keyboard")
    fi

    # The free-form tail is split once here, never re-expanded, so a value
    # with a quote or a space in it reaches xfreerdp as the user typed it.
    if [[ -n "${f[extra]:-}" ]]; then
        read -r -a extra <<<"${f[extra]}"
        for word in "${extra[@]}"; do
            if _rdp_is_secret_flag "$word"; then
                aphotic_err "the 'extra' setting carries a password ('${word}'): the session asks for it through zenity instead, so it never reaches 'ps' -- remove it in Settings > Network > Remote Desktop"
                return 1
            fi
        done
        _rdp_argv+=("${extra[@]}")
    fi

    _rdp_host="${f[host]:-}"
    _rdp_workspace="${f[window.workspace]:-}"
    _rdp_fullscreen="${f[window.fullscreen]:-}"
    _rdp_class_value="${f[window.class]:-}"
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

    local -a _rdp_argv
    _rdp_build_argv || return 1

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
