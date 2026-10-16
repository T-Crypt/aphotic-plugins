#!/usr/bin/env bash
# skills/lib/skillscli.sh -- where the skills-manager CLI is, and which
# version this plugin expects.
#
# Pure shell on purpose. This is sourced by cli/skills.sh for the terminal
# and executed directly by qml/SkillsService.qml, so the pane and the
# command can never pick a different binary. Nothing in here may call an
# aphotic helper (aphotic_err, aphotic_log): the QML runs it as a plain
# child process with no core library loaded.
#
# Run it with no arguments to print the resolved path, which is how the
# service finds the CLI once per refresh.
#
# Resolution order, and why:
#   1. $APHOTIC_SKILLS_CLI       an explicit override wins so the tests and a
#                                power user have one way to pin a binary.
#   2. ~/.skills-manager/bin/     what upstream's own installer publishes. If
#                                the desktop app is installed, this is the
#                                binary that shares its database schema, so
#                                it is preferred over our own copy.
#   3. our pinned download        hash-checked. A mismatch fails closed: we
#                                will not run there, we fall through instead.
#   4. PATH                       last, with a version warning, because a
#                                distro or cargo build can lag the pin.

# The release this plugin was developed and tested against. Bump both lines
# together, then re-run tests/test_install_deps.sh, which re-derives the
# hash from the real asset.
skillscli_pin_version() { printf '1.42.0\n'; }

# Both the hash and the URL honour an override so the installer can be
# pointed at a mirror, and so tests/test_install_deps.sh can exercise the
# real download path against a local file. The pin above stays the default;
# nothing sets these on a normal machine.
skillscli_pin_sha256() {
    printf '%s\n' "${APHOTIC_SKILLS_CLI_SHA256:-17b94fc78ab6888422146718786b4ed68b0563b9c7b981bb7a1385595a63d628}"
}

skillscli_asset_name() { printf 'skills-manager-cli-Linux-x64\n'; }

skillscli_release_url() {
    if [[ -n "${APHOTIC_SKILLS_CLI_URL:-}" ]]; then
        printf '%s\n' "$APHOTIC_SKILLS_CLI_URL"
        return 0
    fi
    printf 'https://github.com/xingkongliang/skills-manager/releases/download/v%s/%s\n' \
        "$(skillscli_pin_version)" "$(skillscli_asset_name)"
}

skillscli_published_path() {
    printf '%s/.skills-manager/bin/skills-manager-cli\n' "${HOME:?HOME is not set}"
}

# Outside the plugin directory on purpose: `aphotic plugin update skills`
# replaces the plugin directory, and a downloaded binary inside it would be
# removed with the old tree.
skillscli_pinned_path() {
    printf '%s/aphotic/skills-manager/bin/skills-manager-cli\n' \
        "${XDG_DATA_HOME:-${HOME:?HOME is not set}/.local/share}"
}

skillscli_sha256() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        return 1
    fi
}

# 0 when the file hashes to the pin. Missing hash tooling is a soft failure
# so a machine without coreutils still gets a working plugin.
skillscli_verify_pin() {
    local file="$1" actual expected
    expected="$(skillscli_pin_sha256)"
    actual="$(skillscli_sha256 "$file")" || return 0
    [[ "$actual" == "$expected" ]]
}

# "<source>\t<path>" for every candidate, in preference order. The source
# tag is what lets `doctor` say which binary was chosen and why.
skillscli_candidates() {
    local path
    if [[ -n "${APHOTIC_SKILLS_CLI:-}" ]]; then
        printf 'override\t%s\n' "$APHOTIC_SKILLS_CLI"
    fi
    printf 'published\t%s\n' "$(skillscli_published_path)"
    printf 'pinned\t%s\n' "$(skillscli_pinned_path)"
    path="$(command -v skills-manager-cli 2>/dev/null)" && \
        printf 'path\t%s\n' "$path"
    return 0
}

skillscli_resolve() {
    local source path
    while IFS=$'\t' read -r source path; do
        [[ -n "$path" && -x "$path" ]] || continue
        if [[ "$source" == "pinned" ]] && ! skillscli_verify_pin "$path"; then
            printf 'skills: ignoring %s, it does not match the pinned %s build\n' \
                "$path" "$(skillscli_pin_version)" >&2
            continue
        fi
        printf '%s\n' "$path"
        return 0
    done < <(skillscli_candidates)
    return 1
}

skillscli_resolve_source() {
    local resolved
    resolved="$(skillscli_resolve)" || return 1
    skillscli_candidates | awk -F'\t' -v p="$resolved" '$2 == p { print $1; exit }'
}

skillscli_version_of() {
    "$1" --version 2>/dev/null | head -1 | tr -d '\r' | sed 's/.*[[:space:]]//'
}

# A single line to show the user when the binary is missing or the wrong
# one. `aphotic skills doctor` prints it, and the pane shows it verbatim.
skillscli_install_hint() {
    cat <<EOF
skills-manager-cli $(skillscli_pin_version) is not installed.
This plugin can fetch it for you:

    aphotic plugin install skills     # runs the downloader and asks first

Or install it yourself and leave it at one of these paths:

    $(skillscli_published_path)
    $(skillscli_pinned_path)

or anywhere on PATH.
EOF
}

# Executed rather than sourced: dispatch one subcommand by name so the QML
# service can ask for a single value without loading a shell library.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    fn="skillscli_${1:-resolve}"
    if declare -F "$fn" >/dev/null; then
        shift || true
        "$fn" "$@"
    else
        printf 'usage: %s [resolve|resolve_source|pin_version|pin_sha256|pinned_path|published_path|asset_name|release_url]\n' \
            "$(basename "$0")" >&2
        exit 2
    fi
fi
