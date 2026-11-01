#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AD="$ROOT/android-dev"
MANIFEST="$AD/plugin.toml"
CTL="$AD/bin/androidctl"
PACK="$AD/pack.toml"

CLEANUPS=()
fail() {
    local t
    for t in "${CLEANUPS[@]:-}"; do
        [[ -n "$t" && -d "$t" ]] && rm -rf "$t"
    done
    echo "FAIL: $1"
    exit 1
}

# The manifest.
rg -q '^name = "android-dev"$' "$MANIFEST" || fail "wrong plugin name"
rg -q '^display_name = "Android Development"$' "$MANIFEST" || fail "wrong display name"
rg -q '^category = "dev"$' "$MANIFEST" || fail "wrong category"
rg -q '^version = "0.1.0"$' "$MANIFEST" || fail "wrong version"
rg -q '^capabilities = \["cli"\]$' "$MANIFEST" || fail "capabilities must be cli only in this slice"

# Top-level command, because a subcommand only resolves when core ships
# a command file of that name, and no core file ever names a plugin.
rg -q '^command = "android"$' "$MANIFEST" || fail "cli does not declare the android command"
rg -q '^subcommand = ' "$MANIFEST" && fail "cli must be top-level, not a subcommand"

# No UI sections yet. This slice is the CLI alone.
rg -q '^\[(ui|action|action_[0-9]|keybind)' "$MANIFEST" && fail "this slice declares no UI, action or keybind sections"

# The package-name override pattern. java arrives from a package that is
# not named java, and declaring the SDK tools here would send core down
# its `yay -S <binary-name>` path, which owns nothing of theirs.
rg -q 'binaries = \["java", "unzip"\]' "$MANIFEST" || fail "missing declared runtime binaries"
rg -q 'packages = \["jdk17-openjdk", "unzip"\]' "$MANIFEST" || fail "missing the package-name override"
for binary in sdkmanager adb; do
    rg -q "binaries = \[[^]]*\"${binary}\"" "$MANIFEST" && fail "${binary} must not be in requires.binaries"
done

# Every path the manifest owns sits under one of the two user directories
# this plugin writes.
rg -q 'external_config = \[' "$MANIFEST" || fail "manifest does not list its external paths"
while IFS= read -r owned; do
    # shellcheck disable=SC2088  # the manifest stores these paths with a literal tilde
    case "$owned" in
        *"~/.local/share/aphotic/plugins/android-dev/"* | "~/.android/"*) ;;
        *) fail "owns an unexpected path: ${owned}" ;;
    esac
done < <(sed -n '/^external_config = \[/,/^\]/p' "$MANIFEST" | sed -n 's/.*"\(~[^"]*\)".*/\1/p')

# Every file the manifest names must exist inside the plugin's own tree.
while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    [[ -f "$AD/$path" ]] || fail "manifest names a missing path: $path"
done < <(sed -n 's/^script = "\(.*\)"$/\1/p' "$MANIFEST")

for script in bin/androidctl bin/lib.sh cli/android.sh; do
    [[ -r "$AD/$script" ]] || fail "missing $script"
done
[[ -x "$AD/bin/androidctl" ]] || fail "androidctl is not executable"
[[ -x "$AD/cli/android.sh" ]] || fail "cli/android.sh is not executable"
grep -q 'lib.sh' "$AD/bin/androidctl" || fail "the engine does not source lib.sh"

# Nothing may run a privileged command on its own.
for script in "$AD"/bin/* "$AD"/cli/*.sh "$AD/tests"/*.sh; do
    rg -q '^\s*sudo ' "$script" && fail "$(basename "$script") runs sudo"
done

for script in bin/androidctl bin/lib.sh cli/android.sh tests/test_android_dev.sh; do
    bash -n "$AD/$script" || fail "bash -n failed on $script"
    shellcheck -x "$AD/$script" || fail "shellcheck failed on $script"
done

# The pack. It is one download pinned by checksum, so the checksum has
# to be a checksum.
python3 - "$PACK" <<'PY' || fail "pack.toml does not parse"
import re
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    doc = tomllib.load(handle)
cmd = doc["cmdline_tools"]
if not re.fullmatch(r"[0-9a-f]{64}", str(cmd.get("sha256", ""))):
    sys.exit(1)
if not str(cmd.get("url", "")).startswith("https://"):
    sys.exit(1)
if not str(cmd.get("version", "")).isdigit():
    sys.exit(1)
pkgs = doc["pack"]["packages"]
if not pkgs or not all(isinstance(p, str) and p for p in pkgs):
    sys.exit(1)
PY

"$CTL" --help >/dev/null || fail "--help must exit 0"

# Behaviour, not implementation. The engine answers correctly with
# nothing installed, which is the state every user is in before setup.
HOME_DIR="$(mktemp -d)"
CLEANUPS+=("$HOME_DIR")
export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export XDG_DATA_HOME="$HOME_DIR/.local/share"

doctor_out=""
if doctor_out="$("$CTL" doctor 2>&1)"; then
    fail "doctor reports success on a machine with no toolchain"
fi
grep -q '\[missing\]' <<<"$doctor_out" || fail "doctor reports nothing missing on a fresh machine"
grep -q '\[ok' <<<"$doctor_out" || fail "doctor prints no [ok] line for the checks that pass"
grep -q "$HOME_DIR/.local/share/aphotic/plugins/android-dev/sdk" <<<"$doctor_out" || fail "the sdk check does not resolve under HOME"

paths="$("$CTL" paths)"
grep -q "$HOME_DIR/.local/share/aphotic/plugins/android-dev/sdk" <<<"$paths" || fail "paths does not resolve the SDK root under HOME"
grep -q "$HOME_DIR/.config/aphotic/plugins/android-dev" <<<"$paths" || fail "paths does not print the config dir"

status="$("$CTL" status)"
grep -q "sdk root: no" <<<"$status" || fail "status claims an SDK on a fresh machine"
grep -q "pack complete: no" <<<"$status" || fail "status claims a complete pack on a fresh machine"

if "$CTL" bogus >/dev/null 2>&1; then
    fail "an unknown command must not exit 0"
fi

# A tampered zip. The alternate pack names a local file whose checksum
# cannot match, so setup must refuse it, delete it and leave no SDK tree
# behind. No network here, the fake zip is the whole download.
FAKE_HOME="$(mktemp -d)"
CLEANUPS+=("$FAKE_HOME")
fake_zip="$FAKE_HOME/fake.zip"
printf 'not a real command line tools archive\n' >"$fake_zip"
fake_pack="$FAKE_HOME/fake-pack.toml"
{
    echo '[cmdline_tools]'
    echo 'version = "0"'
    echo "url = \"file://$fake_zip\""
    echo 'sha256 = "0000000000000000000000000000000000000000000000000000000000000000"'
    echo '[pack]'
    echo 'packages = ["platform-tools"]'
} >"$fake_pack"

setup_home="$FAKE_HOME/home"
if HOME="$setup_home" XDG_CONFIG_HOME="$setup_home/.config" XDG_DATA_HOME="$setup_home/.local/share" \
    ANDROID_DEV_PACK_FILE="$fake_pack" "$CTL" setup </dev/null >"$FAKE_HOME/setup.out" 2>&1; then
    fail "setup accepted a zip with the wrong checksum"
fi
grep -qi 'checksum' "$FAKE_HOME/setup.out" || fail "setup did not say which check failed"
if [[ -e "$setup_home/.local/share/aphotic/plugins/android-dev/sdk" ]]; then
    fail "setup left an sdk dir behind after a refused zip"
fi

# The licenses gate. The cmdline tools are unpacked and the pack package
# is not installed, so setup reaches the licenses step. The fake
# sdkmanager records every call instead of installing anything.
sdk_root="$setup_home/.local/share/aphotic/plugins/android-dev/sdk"
mkdir -p "$sdk_root/cmdline-tools/latest/bin"
printf '#!/bin/sh\necho "$@" >>"%s"\nexit 0\n' "$FAKE_HOME/sdkmanager.calls" \
    >"$sdk_root/cmdline-tools/latest/bin/sdkmanager"
chmod +x "$sdk_root/cmdline-tools/latest/bin/sdkmanager"

# Without a terminal setup stops before the licenses and before the pack,
# and prints the exact command instead of running it.
no_term="$(HOME="$setup_home" XDG_CONFIG_HOME="$setup_home/.config" XDG_DATA_HOME="$setup_home/.local/share" \
    ANDROID_DEV_PACK_FILE="$fake_pack" "$CTL" setup </dev/null 2>&1)"
grep -qi 'licenses' <<<"$no_term" || fail "setup did not stop at the licenses"
grep -q -- "--sdk_root=$sdk_root --licenses" <<<"$no_term" || fail "setup did not print the exact licenses command"
if [[ -e "$FAKE_HOME/sdkmanager.calls" ]]; then
    fail "setup ran sdkmanager without a terminal"
fi

# With a terminal the licenses are shown and the pack installs. script(1)
# is only trusted when the probe proves it can hand a tty to the command,
# so hosts without one simply skip this half.
if command -v script >/dev/null 2>&1 && script -qec 'test -t 0' /dev/null >/dev/null 2>&1; then
    HOME="$setup_home" XDG_CONFIG_HOME="$setup_home/.config" XDG_DATA_HOME="$setup_home/.local/share" \
        ANDROID_DEV_PACK_FILE="$fake_pack" \
        script -qec "$CTL setup" /dev/null </dev/null >"$FAKE_HOME/setup.tty" 2>&1 || true
    [[ -e "$FAKE_HOME/sdkmanager.calls" ]] || fail "setup did not offer the licenses on a terminal"
    grep -q -- '--licenses' "$FAKE_HOME/sdkmanager.calls" || fail "setup skipped the licenses call"
    grep -q -- "--sdk_root=$sdk_root platform-tools" "$FAKE_HOME/sdkmanager.calls" \
        || fail "setup did not install the pack on a terminal"
fi

rm -rf "$HOME_DIR" "$FAKE_HOME"
echo "PASS: android-dev"
