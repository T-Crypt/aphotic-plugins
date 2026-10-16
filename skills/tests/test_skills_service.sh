#!/usr/bin/env bash
# skills/tests/test_skills_service.sh -- the QML service against the stub CLI.
#
# Runs the same probe three times, once per scenario, each with its own HOME
# and its own scratch so a mutation in one cannot be read by the next. The
# probe is a windowless `qs -p` run (QT_QPA_PLATFORM=offscreen) and must never
# be pointed at a live session: `qs -p` maps a second bar.
#
# PATH is a shim holding only the binaries this chain needs, which is how the
# "no binary at all" scenario stays honest on a machine that happens to have
# skills-manager-cli installed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES="$ROOT/skills/tests/fixtures"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

# The chain is qs -> bash -> lib/skillscli.sh -> jq/sed/awk -> the stub.
SHIM="$TEST_ROOT/bin"
mkdir -p "$SHIM" "$TEST_ROOT/imports/qs/modules/plugins"
ln -s "$ROOT/skills/qml" "$TEST_ROOT/imports/qs/modules/plugins/skills"
for bin in bash sh jq column awk sed tr head cut sha256sum dirname basename pwd \
           cat cp mkdir ln rm timeout env; do
    found="$(command -v "$bin" 2>/dev/null)" || continue
    ln -sf "$found" "$SHIM/$bin"
done
ln -sf "$(command -v qs)" "$SHIM/qs"

die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

run_probe() {
    local mode="$1" home="$TEST_ROOT/home-$1"
    mkdir -p "$home/.local/share/aphotic/plugins"
    ln -sfn "$ROOT/skills" "$home/.local/share/aphotic/plugins/skills"

    # A path that is never there, so the missing-binary run falls through
    # the override to the published and pinned locations and then PATH.
    local override="$FIXTURES/skills-manager-cli"
    [[ "$mode" == "missing" ]] && override="$home/no-such-skills-manager-cli"

    # The stub only refuses a deploy when asked, so the conflict run reaches
    # the TARGET_CONFLICT path the CLI takes when a target is not ours.
    local stub_conflict="0"
    [[ "$mode" == "conflict" ]] && stub_conflict="1"

    env -u WAYLAND_DISPLAY \
        HOME="$home" \
        PATH="$SHIM" \
        APHOTIC_SKILLS_CLI="$override" \
        SKILLS_STUB_CONFLICT="$stub_conflict" \
        SKILLS_STUB_FIXTURES="$FIXTURES" \
        SKILLS_PROBE_MODE="$mode" \
        QML2_IMPORT_PATH="$TEST_ROOT/imports" \
        QT_QPA_PLATFORM=offscreen \
        XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
        timeout 20 qs -p "$ROOT/skills/tests/SkillsServiceProbe.qml" 2>&1
}

expect_pass() {
    local mode="$1" expected="$2" output
    output="$(run_probe "$mode")" || true
    printf '%s\n' "$output"
    if grep -q 'FAIL:' <<<"$output"; then
        die "$mode mode failed"
    fi
    grep -q "PASS: $expected" <<<"$output" \
        || die "$mode mode never reached its pass line"
}

# The override makes "no binary anywhere" real rather than assumed.
[[ -e "$SHIM/skills-manager-cli" ]] && die "the shim should not carry skills-manager-cli"

chmod +x "$FIXTURES/skills-manager-cli"

expect_pass ok "the service reads the library, deploys, undeploys, tags, deploys a preset and previews"
expect_pass conflict "a refused deploy surfaces its protected paths and nothing changes"
expect_pass missing "a machine with no binary gets a report, not a parse error"
