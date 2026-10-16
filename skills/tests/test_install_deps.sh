#!/usr/bin/env bash
# skills/tests/test_install_deps.sh -- the install hook, no network, no real
# binary, no screen, no input.
#
# Two scenarios the user can reach on a real machine:
#   1. non-interactive call (piped install, CI, the AUR helper) gets the
#      install instructions and exits 0 without downloading anything.
#   2. a wrong sha256 fails closed, exits non-zero, and names both hashes
#      in the message so a release that re-shaved bytes is impossible to
#      miss.
#
# Both run against a local file:// URL that points at a fixture binary,
# the same override the contract test uses to assert the pin.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/skills/hooks/install-deps.sh"
BIN="$ROOT/skills/tests/fixtures/skills-manager-cli"

fail() { echo "FAIL: $1" >&2; exit 1; }
[[ -f "$HOOK" ]] || fail "install-deps.sh missing"
[[ -x "$BIN" ]] || fail "fixture binary not executable"

URL="file://$BIN"
GOOD_SHA="$(sha256sum "$BIN" | cut -d' ' -f1)"
# A 64-hex of all 1s that is not the real hash; a real release that
# re-shaves bytes can never produce this, so any match is by design.
WRONG_SHA="1111111111111111111111111111111111111111111111111111111111111110"

# Drop any skills-manager-cli a developer machine happens to carry from
# the ambient PATH. Don't isolate /usr/bin: the hook needs curl,
# sha256sum, chmod, mktemp and friends, and enumerating them is a losing
# game. The four resolver candidates then miss, and the hook proceeds.
strip_skills_cli() {
    local d out=""
    local IFS=:
    for d in $PATH; do
        [[ -x "$d/skills-manager-cli" ]] && continue
        out+="${out:+:}${d}"
    done
    printf '%s' "$out"
}

# ── non-interactive path ────────────────────────────────────────────────
# With stdin not a tty, the hook answers 0 without ever touching the
# download. Force resolver failure so the hook actually reaches the
# prompt gate rather than bailing out the moment it finds an existing
# install.
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT" "$TEST_ROOT2"' EXIT
HOME="$TEST_ROOT/home"
mkdir -p "$HOME/.skills-manager/bin"
SAFE_PATH="$(strip_skills_cli)"

output="$(
    APHOTIC_SKILLS_CLI="/no/such/skills-manager-cli" \
    APHOTIC_SKILLS_CLI_URL="$URL" \
    APHOTIC_SKILLS_CLI_SHA256="$GOOD_SHA" \
    HOME="$HOME" \
    PATH="$SAFE_PATH" \
    bash "$HOOK" \
        < /dev/null \
        > "$TEST_ROOT/out" \
        2> "$TEST_ROOT/err"
)" && rc=0 || rc=$?

[[ "$rc" -eq 0 ]] || fail "non-interactive should exit 0, got $rc; stderr: $(cat "$TEST_ROOT/err")"

[[ ! -e "$HOME/.local/share/aphotic/skills-manager/bin/skills-manager-cli" ]] \
    || fail "non-interactive install wrote a binary"

grep -q 'Not running interactively' "$TEST_ROOT/err" \
    || fail "stderr missing the not-interactive line"
grep -q "$URL" "$TEST_ROOT/err" \
    || fail "stderr missing the file:// URL the user can run themselves"

# ── wrong-hash path ─────────────────────────────────────────────────────
# The hook only verifies a hash on the path that downloads. With the
# resolver again failing and a deterministic "yes" through
# APHOTIC_SKILLS_ASSUME_YES, the download runs against the file://
# mirror; the SHA check then refuses, exits non-zero, and prints both
# hashes.
#
# APHOTIC_SKILLS_ASSUME_YES is a hook-only knob used by this test.
# Without it set, the hook still requires an interactive y/N, the
# same way every install script does.
TEST_ROOT2="$(mktemp -d)"
HOME="$TEST_ROOT2/home"
mkdir -p "$HOME/.skills-manager/bin"

set +e
output2="$(
    APHOTIC_SKILLS_CLI="/no/such/skills-manager-cli" \
    APHOTIC_SKILLS_CLI_URL="$URL" \
    APHOTIC_SKILLS_CLI_SHA256="$WRONG_SHA" \
    APHOTIC_SKILLS_ASSUME_YES=1 \
    HOME="$HOME" \
    PATH="$SAFE_PATH" \
    bash "$HOOK" \
        > "$TEST_ROOT2/out" \
        2> "$TEST_ROOT2/err"
)"
rc2=$?
set -e

[[ "$rc2" -ne 0 ]] \
    || fail "wrong-hash install should exit non-zero, got $rc2; stderr: $(cat "$TEST_ROOT2/err")"

[[ ! -e "$HOME/.local/share/aphotic/skills-manager/bin/skills-manager-cli" ]] \
    || fail "wrong-hash install dropped a binary"

# Both hashes named in the refused-install message. The "Refusing to
# install" block on stderr prints `expected` (the pin) and `got` (the
# actual hash) on dedicated lines, so a release that re-shaved bytes
# without bumping the pin fails the test rather than silently
# rewriting the binary.
grep -qE '^Refusing to install' "$TEST_ROOT2/err" \
    || fail "the refused-install header line is missing"
grep -qE "^[[:space:]]*expected[[:space:]]+$WRONG_SHA" "$TEST_ROOT2/err" \
    || fail "expected-hash line missing or mis-formatted"
grep -qE "^[[:space:]]*got[[:space:]]+$GOOD_SHA" "$TEST_ROOT2/err" \
    || fail "got-hash line missing or not the actual fixture hash"

echo "PASS: install-deps (non-interactive + wrong-hash closed)"
