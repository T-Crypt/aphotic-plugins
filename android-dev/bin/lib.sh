#!/usr/bin/env bash
# android-dev/bin/lib.sh -- shared paths, the pack reader and the check
# table. Sourced by every other script in bin/.
#
# One rule holds this file together: every fact here derives from HOME,
# from XDG, or from pack.toml, so doctor, setup, status and run cannot
# disagree about where the SDK is or about what the pack contains.

_ANDROID_LIB_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
_ANDROID_PLUGIN_DIR="$(cd "${_ANDROID_LIB_DIR}/.." && pwd)"

# The SDK root derives from the data dir rather than from the plugin's own
# directory, so a checkout and an install answer the same path question
# and a test can move the whole tree by setting HOME.
_ANDROID_DATA_HOME="${APHOTIC_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/aphotic}"
_ANDROID_SDK_ROOT="${_ANDROID_DATA_HOME}/plugins/android-dev/sdk"
_ANDROID_CMDLINE_HOME="${_ANDROID_SDK_ROOT}/cmdline-tools/latest"
_ANDROID_SDKMANAGER="${_ANDROID_CMDLINE_HOME}/bin/sdkmanager"
_ANDROID_ADB="${_ANDROID_SDK_ROOT}/platform-tools/adb"

_ANDROID_CONFIG_HOME="${APHOTIC_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/aphotic}"
_ANDROID_CONFIG_DIR="${_ANDROID_CONFIG_HOME}/plugins/android-dev"

# The pack. ANDROID_DEV_PACK_FILE names an alternate pack.toml, which is
# how the test points setup at a tampered zip without touching the
# shipped one.
_ANDROID_PACK_DEFAULT="${_ANDROID_PLUGIN_DIR}/pack.toml"

# Java 17 is the floor because older runs refuse the SDK tools with a
# class-version error that reads like a broken download.
_ANDROID_JAVA_MIN=17

# Vendor ids a rule needs to cover Android phones on USB. 18d1 is what
# most of them put on the debug interface, the rest are the common OEM
# fallbacks. Doctor only reports what it finds. It never writes a rule
# and never edits a group.
_ANDROID_USB_VENDORS='18d1|04e8|0fce|0bb4|2207|12d1|2717|1843|045f|0e8d|1004'

# ---------------------------------------------------------------------------
# The pack
# ---------------------------------------------------------------------------

# Reads pack.toml into ANDROID_PACK_VERSION, ANDROID_PACK_URL,
# ANDROID_PACK_SHA256 and ANDROID_PACK_PACKAGES (space separated). A pack
# is one screen of pinned facts, so the whole file is read in one python
# call rather than grepped four times.
_android_load_pack() {
    local file="${ANDROID_DEV_PACK_FILE:-$_ANDROID_PACK_DEFAULT}"
    if [[ ! -r "$file" ]]; then
        echo "android-dev: no pack file at ${file}" >&2
        return 1
    fi
    local out
    if ! out="$(python3 - "$file" <<'PY'
import shlex
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    doc = tomllib.load(handle)
cmd = doc["cmdline_tools"]
fields = {
    "ANDROID_PACK_VERSION": str(cmd["version"]),
    "ANDROID_PACK_URL": str(cmd["url"]),
    "ANDROID_PACK_SHA256": str(cmd["sha256"]),
    "ANDROID_PACK_PACKAGES": " ".join(str(p) for p in doc["pack"]["packages"]),
}
for key, value in fields.items():
    print(key + "=" + shlex.quote(value))
PY
)"; then
        echo "android-dev: ${file} does not parse. The pack reader needs python3 with tomllib." >&2
        return 1
    fi
    # The writer above quotes every value, so this cannot word-split or
    # expand anything the pack file did not state.
    eval "$out"
}

# An sdkmanager id is a folder path with semicolons, so `build-tools;37.0.0`
# lives at build-tools/37.0.0 under the SDK root. platform-tools and
# emulator carry no semicolon and are one folder each.
_android_pkg_dir() {
    printf '%s\n' "${1//;/\/}"
}

# One package id per line, empty when the pack is complete. Never fails,
# because the doctor reads this on machines where nothing is installed.
_android_missing_packages() {
    local id
    [[ -n "${ANDROID_PACK_PACKAGES:-}" ]] || return 0
    if [[ ! -d "$_ANDROID_SDK_ROOT" ]]; then
        # shellcheck disable=SC2086  # ids split on spaces by design
        printf '%s\n' $ANDROID_PACK_PACKAGES
        return 0
    fi
    for id in $ANDROID_PACK_PACKAGES; do
        [[ -d "${_ANDROID_SDK_ROOT}/$(_android_pkg_dir "$id")" ]] || printf '%s\n' "$id"
    done
    return 0
}

# ---------------------------------------------------------------------------
# Probes
# ---------------------------------------------------------------------------

# java -version prints to stderr and carries the version between quotes.
# The old 1.x form resolves to major 1 here, which reads honestly as
# older than 17.
_android_java_major() {
    local line major
    line="$(java -version 2>&1 | head -n1 || true)"
    major="$(printf '%s\n' "$line" | awk -F'"' 'NF>1{print $2; exit}')"
    major="${major%%.*}"
    [[ "$major" =~ ^[0-9]+$ ]] && printf '%s\n' "$major"
    return 0
}

# Prints how USB access is covered, or returns 1. adb reaches a phone
# through a udev rule that names an Android vendor id and grants some
# group access to the node, so a line counts when the id sits right
# behind idVendor, the line speaks of usb or android, and it carries a
# MODE, a GROUP or uaccess. A modem rule that only tags a Sony device or
# a controller rule that matches on idProduct is not adb access. Doctor
# reports what it finds without ever writing a rule or touching a group.
_android_usb_access_source() {
    local d f hits
    for d in /etc/udev/rules.d /usr/lib/udev/rules.d /lib/udev/rules.d; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*rules*; do
            [[ -r "$f" ]] || continue
            hits="$(grep -hE 'idVendor\}?[[:space:]]*=+"?('"$_ANDROID_USB_VENDORS"')"' "$f" 2>/dev/null |
                grep -iE 'usb|"android' |
                grep -E 'MODE=|GROUP=|uaccess' || true)"
            if [[ -n "$hits" ]]; then
                printf 'udev rule %s\n' "$f"
                return 0
            fi
        done
    done
    if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx plugdev; then
        echo "plugdev group membership"
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# The check table
#
# A table rather than a chain of conditionals, because the doctor and the
# status line read the same facts and must not drift apart. Order is the
# order the user sees, dependency first.
# ---------------------------------------------------------------------------

_ANDROID_CHECK_IDS=(java unzip sdk cmdline-tools pack adb usb-access)

_android_check_ok() {
    local major
    case "$1" in
        java)
            major="$(_android_java_major)"
            [[ -n "$major" && "$major" -ge "$_ANDROID_JAVA_MIN" ]]
            ;;
        unzip) command -v unzip >/dev/null 2>&1 ;;
        sdk) [[ -d "$_ANDROID_SDK_ROOT" ]] ;;
        cmdline-tools) [[ -x "$_ANDROID_SDKMANAGER" ]] ;;
        pack) [[ -n "${ANDROID_PACK_PACKAGES:-}" && -z "$(_android_missing_packages)" ]] ;;
        adb) [[ -x "$_ANDROID_ADB" ]] ;;
        usb-access) _android_usb_access_source >/dev/null ;;
        *) return 1 ;;
    esac
}

# Never fails. A missing detail is not an error, it is the state a machine
# is in before setup, and a 127 from a probe with nothing installed would
# take the whole doctor down under `set -e`.
_android_check_detail() {
    local out="" missing
    case "$1" in
        java)
            local major
            major="$(_android_java_major)"
            [[ -n "$major" ]] && out="major ${major}"
            ;;
        unzip) out="$(unzip -v 2>/dev/null | awk 'NR==1{print $2; exit}' || true)" ;;
        # The root is printed even when absent, because a missing
        # directory the doctor never names is a mystery to fix.
        sdk) out="$_ANDROID_SDK_ROOT" ;;
        cmdline-tools)
            out="$(awk -F= '/^Pkg.Revision/{print $2; exit}' "${_ANDROID_CMDLINE_HOME}/source.properties" 2>/dev/null || true)"
            ;;
        pack)
            missing="$(_android_missing_packages | paste -sd, - 2>/dev/null || true)"
            missing="${missing//,/, }"
            [[ -n "$missing" ]] && out="missing ${missing}"
            ;;
        adb) out="$("$_ANDROID_ADB" version 2>/dev/null | awk '/version/{print $NF; exit}' || true)" ;;
        usb-access) out="$(_android_usb_access_source 2>/dev/null || true)" ;;
    esac
    printf '%s\n' "$out"
    return 0
}

# The one instruction that matters per check. Everything except USB
# access is something `aphotic android setup` does. There is no fix for
# USB access to run here, because changing it is the user's call.
_android_check_fix() {
    case "$1" in
        java) echo "install jdk17-openjdk or any newer JDK, then open a new shell" ;;
        unzip) echo "install the unzip package" ;;
        sdk | cmdline-tools | pack | adb) echo "aphotic android setup" ;;
        usb-access) echo "install a udev rule for Android USB vendors, or add yourself to a group one grants, then reload udev and replug" ;;
    esac
}
