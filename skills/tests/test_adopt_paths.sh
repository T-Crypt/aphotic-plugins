#!/usr/bin/env bash
# skills/tests/test_adopt_paths.sh -- discovery for `aphotic skills adopt`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN="$ROOT/skills"
CLI="$PLUGIN/cli/skills.sh"
FIXTURES="$ROOT/skills/tests/fixtures"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

HOME_DIR="$TEST_ROOT/home"
mkdir -p "$HOME_DIR"
export HOME="$HOME_DIR"

# A few known dirs: one real, one symlink to another, one missing.
mkdir -p "$HOME/.claude/skills" "$HOME/.codex/skills"
mkdir -p "$HOME/.agents"
ln -s "$HOME/.claude/skills" "$HOME/.agents/skills"
# ~/.config/opencode/skills deliberately missing

# Drop-in with an extra (non-known) dir plus a missing one and a comment.
mkdir -p "$HOME/.config/aphotic/skills" "$HOME/dropin-skills"
printf '%s\n# a comment\n%s\n' "$HOME/dropin-skills" "$HOME/nope-skills" \
    > "$HOME/.config/aphotic/skills/dirs.txt"

STUB="$FIXTURES/skills-manager-cli"
chmod +x "$STUB"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# adopt-paths plain
plain="$(APHOTIC_SKILLS_CLI="$STUB" SKILLS_STUB_FIXTURES="$FIXTURES" HOME="$HOME" \
    bash "$CLI" adopt-paths)"
printf '%s\n' "$plain"

# dedup by realpath: agents/skills symlink collapses with claude/skills
lines="$(printf '%s\n' "$plain" | grep -c . || true)"
[[ "$lines" -eq 3 ]] || fail "expected 3 paths, got $lines"

# missing opencode dir skipped
if printf '%s\n' "$plain" | grep -q 'opencode/skills'; then
    fail "missing opencode dir was not skipped"
fi

# drop-in honored
printf '%s\n' "$plain" | grep -qx "$HOME/dropin-skills" \
    || fail "drop-in dir missing from adopt-paths output"

# installed agent dir included (codex is installed in the stub)
printf '%s\n' "$plain" | grep -qx "$HOME/.codex/skills" \
    || fail "installed agent dir missing from adopt-paths output"

# --json shape
json_out="$(APHOTIC_SKILLS_CLI="$STUB" SKILLS_STUB_FIXTURES="$FIXTURES" HOME="$HOME" \
    bash "$CLI" adopt-paths --json)"
printf '%s\n' "$json_out" | jq -e '.paths | length == 3' >/dev/null \
    || fail "adopt-paths --json wrong count"

# adopt passes the paths through to the stub
adopt_out="$(APHOTIC_SKILLS_CLI="$STUB" SKILLS_STUB_FIXTURES="$FIXTURES" HOME="$HOME" \
    bash "$CLI" adopt --json --dry-run)"
printf '%s\n' "$adopt_out"
printf '%s\n' "$adopt_out" | jq -e '.candidates == 3' >/dev/null \
    || fail "adopt did not pass the 3 discovered paths"

# no paths -> rc 2
EMPTY_HOME="$TEST_ROOT/emptyhome"
mkdir -p "$EMPTY_HOME"
set +e
APHOTIC_SKILLS_CLI="$STUB" SKILLS_STUB_FIXTURES="$FIXTURES" HOME="$EMPTY_HOME" \
    bash "$CLI" adopt >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail "expected rc 2 with no paths, got $rc"

echo "PASS: adopt-paths discovery"
