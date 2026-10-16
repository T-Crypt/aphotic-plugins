#!/usr/bin/env bash
# skills/hooks/install-deps.sh -- called by `aphotic plugin install|enable
# skills` through the manifest's `[requires].install_script`, because
# skills-manager-cli is missing from PATH.
#
# Why this exists at all: core's default for a missing binary is
# `yay -S <name>`, and there is no package by this name in the Arch repos or
# the AUR. The only upstream distribution is a GitHub release asset.
#
# Why it downloads rather than piping an installer script: upstream publishes
# a single static binary per platform, so there is no script to run. That
# also means the artifact can be verified before it is trusted, which is what
# the sha256 below is for. It is a trust-on-first-use pin -- upstream
# publishes no signature for this asset, only for the desktop installers --
# so it proves the bytes did not change between the release and this
# download. It does not prove the release itself is honest.
#
# Non-interactive callers get the instructions and nothing happens, the same
# rule codex-hooks follows: downloading and executing a binary is not
# something to do silently on the user's behalf.
set -euo pipefail

_sk_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_sk_plugin_dir="$(cd "${_sk_dir}/.." && pwd)"
# shellcheck source=../lib/skillscli.sh
source "${_sk_plugin_dir}/lib/skillscli.sh"

dest="$(skillscli_pinned_path)"
url="$(skillscli_release_url)"
version="$(skillscli_pin_version)"
expected="$(skillscli_pin_sha256)"

# If a binary already resolves, there is nothing to do. This is the common
# case when upstream's own desktop app is installed: it publishes the same
# CLI at ~/.skills-manager/bin, which lib/skillscli.sh prefers, and the
# missing-from-PATH check that brought us here does not see it.
if existing="$(skillscli_resolve 2>/dev/null)"; then
    source="$(skillscli_resolve_source)"
    echo "skills-manager-cli is already available at ${existing} (${source})."
    echo "Local skills, so nothing was downloaded."
    exit 0
fi

cat <<EOF
The Skill Manager needs skills-manager-cli ${version}, which is not installed.

  version     ${version}
  asset       $(skillscli_asset_name)
  from        ${url}
  sha256      ${expected}
  installed   ${dest}

No package manager can supply this: upstream ships it as a GitHub release
asset and nothing else.
EOF

if [[ ! -t 0 && "${APHOTIC_SKILLS_ASSUME_YES:-0}" != "1" ]]; then
    echo
    echo "Not running interactively, so nothing was downloaded." >&2
    echo "Download it yourself with:" >&2
    echo >&2
    echo "    curl -fsSL -o '${dest}' '${url}'" >&2
    echo "    chmod +x '${dest}'" >&2
    echo >&2
    echo "then re-run: aphotic plugin install skills" >&2
    exit 0
fi

printf '\nDownload and install it now? [y/N] '
# APHOTIC_SKILLS_ASSUME_YES=1 is honored only by tests, never on a
# real install. It is checked after the prompt has been announced so
# the message stays the same shape either way.
if [[ "${APHOTIC_SKILLS_ASSUME_YES:-0}" == "1" ]]; then
    reply="y"
else
    read -r reply
fi
if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Skipped. The plugin is installed and its surfaces stay dark until the"
    echo "binary resolves; run 'aphotic skills doctor' to see what it finds."
    exit 0
fi

mkdir -p "$(dirname "$dest")"
tmp="$(mktemp "$(dirname "$dest")/.skills-manager-cli.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

echo "Downloading..."
if ! curl -fsSL -o "$tmp" "$url"; then
    echo >&2
    echo "The download failed. Nothing was installed." >&2
    exit 1
fi
chmod +x "$tmp"

# Fail closed. A mismatch means the bytes are not the release this plugin was
# written against, and running them would be trusting whatever arrived.
actual="$(skillscli_sha256 "$tmp")" || {
    echo >&2
    echo "Could not hash the download (sha256sum and shasum are both missing)." >&2
    echo "Nothing was installed." >&2
    exit 1
}
if [[ "$actual" != "$expected" ]]; then
    cat >&2 <<EOF

Refusing to install: the download does not match the pin.

  expected  ${expected}
  got       ${actual}

Nothing was installed. If upstream re-released v${version} with different
bytes, that is worth looking at before trusting either hash.
EOF
    exit 1
fi

mv -f "$tmp" "$dest"
trap - EXIT

# Verify by running it rather than by trusting the move.
if ! reported="$("$dest" --version 2>/dev/null)"; then
    echo >&2
    echo "Installed ${dest} but it will not run." >&2
    exit 1
fi

echo
echo "Installed ${dest}"
echo "It reports: ${reported}"
