#!/usr/bin/env bash
# The CLI: the dispatch contract and every verb end to end.
#
# What this proves without a shell and without a compositor:
#   - cli/memory.sh is a dispatcher, and it is sourced, never executed
#     (an `exit` in here takes the core dispatcher's subshell with it)
#   - it uses only the helpers core puts in scope, and it runs the same
#     engine the workspace plane runs
#   - every verb answers what a reader expects against a fixture event log
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN="$ROOT/agent-memory"
CLI="$PLUGIN/cli/memory.sh"
CORE="$PLUGIN/python/memory_core.py"

[[ -f "$CLI" ]] || fail "cli/memory.sh missing"
[[ -x "$CLI" ]] || fail "cli/memory.sh is not executable"
[[ -f "$CORE" ]] || fail "python/memory_core.py missing"

bash -n "$CLI" || fail "cli/memory.sh is not valid bash"

# Sourced, never executed: an `exit` would take the dispatcher's subshell.
grep -qE '\bexit\b' "$CLI" && fail "cli/memory.sh must use return, not exit"
grep -qE '\breturn\b' "$CLI" || fail "cli/memory.sh never returns"
grep -q 'memory_core\.py' "$CLI" || fail "cli/memory.sh no longer dispatches to the engine"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ------------------------------------------------- the dispatch contract

# A fake python3 that records its argv, so the assertion is about what the
# wrapper actually ran rather than about what it printed.
mkdir -p "$T/bin"
cat > "$T/bin/python3" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$T/dispatched"
STUB
chmod +x "$T/bin/python3"

source_dispatch() {
    # The helpers core puts in scope when it sources a plugin CLI script.
    # The wrapper may use them and may not need anything else.
    PATH="$T/bin:$PATH" \
        bash -c '
            aphotic_require() { return 0; }
            aphotic_err() { printf "err: %s\n" "\$1" >&2; }
            aphotic_warn() { printf "warn: %s\n" "\$1" >&2; }
            aphotic_log() { printf "log: %s\n" "\$1" >&2; }
            source "$1" "$2"
        ' _ "$CLI" "$1"
}

source_dispatch build || fail "memory build returned non-zero"
[[ -f "$T/dispatched" ]] || fail "memory build never reached the engine"
grep -qxF "$CORE" "$T/dispatched" || fail "the wrapper did not run the plugin engine"
grep -qxF "build" "$T/dispatched" || fail "the verb was not passed through"

# The user-facing answer for a missing verb is a usage line and a non-zero
# return, not a stack trace out of bash.
if source_dispatch "" >"$T/verbless-out" 2>"$T/verbless-err"; then
    fail "a verbless invocation has to fail"
fi
grep -q "usage: aphotic memory" "$T/verbless-err" || fail "a verbless invocation prints no usage"

source_dispatch help >"$T/help-out" 2>/dev/null || fail "help failed"
grep -q "usage: aphotic memory" "$T/help-out" || fail "help prints no usage"

# ------------------------------------------------------- a fixture log

STATE="$T/state/aphotic"
mkdir -p "$STATE"
python3 - "$STATE" <<'PY' || fail "the fixture log could not be written"
import json, pathlib, sys
state = pathlib.Path(sys.argv[1])
rows = [
    {"v": 2, "harness": "omp", "sessionId": "o1", "event": "session_start", "status": "running",
     "t": 1791397100000, "ts": "2026-10-07T18:31:40Z", "cwd": "/repo"},
    {"v": 2, "harness": "omp", "sessionId": "o1", "event": "turn", "status": "running",
     "t": 1791397100100, "ts": "2026-10-07T18:31:40Z"},
    {"v": 2, "harness": "omp", "sessionId": "o1", "event": "tool_call", "tool": "bash",
     "toolId": "c1", "toolStatus": "running", "t": 1791397101000},
    {"v": 2, "harness": "omp", "sessionId": "o1", "event": "tool_call", "tool": "bash",
     "toolId": "c1", "toolStatus": "completed", "t": 1791397101500, "durationMs": 400},
    {"v": 2, "harness": "omp", "sessionId": "o1", "event": "tool_call", "tool": "bash",
     "toolId": "c2", "toolStatus": "errored", "t": 1791397102500,
     "error": {"kind": "exit-nonzero",
               "message": 'jq: error (at /tmp/x:12): Cannot index string with "a"'}},
    {"v": 2, "harness": "claude", "sessionId": "o2", "event": "session_start",
     "status": "running", "t": 1791397200000, "ts": "2026-10-07T18:33:20Z",
     "cwd": "/home/tcrypt/aphotic-plugins"},
]
(state / "agent-events.jsonl").write_text(
    "\n".join(json.dumps(row, separators=(",", ":")) for row in rows) + "\n", encoding="utf-8")
PY

export APHOTIC_STATE_HOME="$STATE"
export HOME="$T/home"
mkdir -p "$HOME/.claude"
printf '# my rules\n\nstay here\n' > "$HOME/.claude/CLAUDE.md"

memory() { python3 "$CORE" "$@"; }

# ----------------------------------------------------------- the verbs

OUTPUT="$(memory build)"
[[ "$OUTPUT" =~ ^ok\ projects=2\ errors=1 ]] || fail "build reported the wrong totals: $OUTPUT"

OUTPUT="$(memory stats)"
grep -q "projects=2" <<<"$OUTPUT" || fail "stats lost a project: $OUTPUT"
grep -q "tool_calls=2" <<<"$OUTPUT" || fail "stats lost the completed call: $OUTPUT"
grep -q "failures=1" <<<"$OUTPUT" || fail "stats lost the failure: $OUTPUT"
grep -q "open_issues=1" <<<"$OUTPUT" || fail "stats lost the open issue: $OUTPUT"

OUTPUT="$(memory projects)"
grep -q "^/repo sessions=1 turns=1 calls=2 failures=1 last=2026-10-07$" <<<"$OUTPUT" \
    || fail "projects did not report the fixture: $OUTPUT"

OUTPUT="$(memory errors)"
[[ "$(grep -c '^\[open\] ' <<<"$OUTPUT")" == "1" ]] \
    || fail "errors did not mark the issue open: $OUTPUT"
grep -q "count=1 tool=bash kind=exit-nonzero" <<<"$OUTPUT" \
    || fail "errors lost the issue: $OUTPUT"
grep -q 'jq: error (at /tmp/x:12): Cannot index string with "a"$' <<<"$OUTPUT" \
    || fail "errors did not carry the recorded message: $OUTPUT"

SIG="$(memory errors --json | jq -r '.[0].sig')"
[[ ${#SIG} == 12 ]] || fail "the signature is not twelve characters: $SIG"

OUTPUT="$(memory context)"
grep -q "^# agent memory -- generated " <<<"$OUTPUT" || fail "the digest has no header: $OUTPUT"
grep -q "^  issue $SIG " <<<"$OUTPUT" || fail "the digest lost the issue: $OUTPUT"
grep -q '<path>:<n>' <<<"$OUTPUT" \
    || fail "the digest kept the raw path and line: $OUTPUT"

# ---- notes

[[ "$(memory note "rebuild the index after a manifest edit" --project /repo)" == "n0" ]] \
    || fail "note did not answer with its id"
grep -q "^n0 .* /repo :: rebuild the index after a manifest edit$" <<<"$(memory notes)" \
    || fail "notes did not list the note: $(memory notes)"
memory context | grep -q "note n0" || fail "the digest did not carry the note"

# The default project is the most recently active one, which is the project
# a note is most likely about without one being named.
[[ "$(memory note "latest thought")" == "n1" ]] || fail "the default note did not answer with its id"
grep -q "^n1 .* /home/tcrypt/aphotic-plugins :: latest thought$" <<<"$(memory notes)" \
    || fail "the default note did not land on the most recent project: $(memory notes)"

OUTPUT="$(memory forget n0)"
grep -q "^forgot n0$" <<<"$OUTPUT" || fail "forget did not confirm: $OUTPUT"
OUTPUT="$(memory forget n1)"
grep -q "^forgot n1$" <<<"$OUTPUT" || fail "forget did not confirm: $OUTPUT"
[[ -z "$(memory notes)" ]] || fail "forgetting the notes left a note behind"

if memory forget n0 >"$T/forget-out" 2>&1; then
    fail "forgetting a note that is not there has to fail"
fi
grep -q "no note n0" "$T/forget-out" || fail "a missing note reports nothing useful"

# ---- resolve, reopen

OUTPUT="$(memory resolve "${SIG:0:6}")"
grep -q "^resolved $SIG$" <<<"$OUTPUT" || fail "resolve did not confirm: $OUTPUT"
if memory context | grep -q "issue "; then
    fail "a resolved issue stayed in the digest"
fi
OUTPUT="$(memory errors)"
grep -q "^\[resolved\] " <<<"$OUTPUT" || fail "the resolved issue is not marked: $OUTPUT"

OUTPUT="$(memory resolve "${SIG:0:6}")"
grep -q "^already resolved $SIG$" <<<"$OUTPUT" \
    || fail "resolving twice did not say it was already resolved: $OUTPUT"

OUTPUT="$(memory reopen "$SIG")"
grep -q "^reopened $SIG$" <<<"$OUTPUT" || fail "reopen did not confirm: $OUTPUT"
OUTPUT="$(memory reopen "$SIG")"
grep -q "^already open $SIG$" <<<"$OUTPUT" \
    || fail "reopening twice did not say it was already open: $OUTPUT"
memory context | grep -q "^  issue $SIG " || fail "the reopened issue is missing from the digest"

if memory resolve zzzz >"$T/unknown-out" 2>&1; then
    fail "an unknown signature has to fail"
fi
grep -q "matches 0 issues" "$T/unknown-out" || fail "an unknown signature reports nothing useful"

# ---- a project that is not on record

if memory errors --project nope >"$T/project-out" 2>&1; then
    fail "an unknown project has to fail"
fi
grep -q "no project 'nope' recorded" "$T/project-out" \
    || fail "the project error is not actionable"
grep -q "  /repo" "$T/project-out" || fail "the project error lists no candidates"
[[ "$(memory errors --project aphotic-plugins | wc -l)" == "0" ]] \
    || fail "a project with no issues is not empty"

# ---- injection

[[ "$(memory inject --status)" == "disabled" ]] \
    || fail "a CLAUDE.md without the block is not reported disabled"
OUTPUT="$(memory inject --enable)"
grep -q "^injected " <<<"$OUTPUT" || fail "inject did not confirm: $OUTPUT"
md5sum "$HOME/.claude/CLAUDE.md" | cut -d' ' -f1 > "$T/first"
OUTPUT="$(memory inject --enable)"
grep -q "^already current" <<<"$OUTPUT" || fail "a second enable changed something: $OUTPUT"
md5sum "$HOME/.claude/CLAUDE.md" | cut -d' ' -f1 > "$T/second"
cmp "$T/first" "$T/second" || fail "a second enable was not byte-identical"
[[ "$(memory inject --status)" == "enabled" ]] || fail "the block is not reported as enabled"
head -n 1 "$HOME/.claude/CLAUDE.md" | grep -qxF "# my rules" \
    || fail "injection touched the file's own first line"
OUTPUT="$(memory inject --disable)"
grep -q "^removed the agent-memory block" <<<"$OUTPUT" || fail "disable did not confirm: $OUTPUT"
grep -q "^# my rules$" "$HOME/.claude/CLAUDE.md" || fail "disable lost the user's own line"
grep -q "agent-memory" "$HOME/.claude/CLAUDE.md" && fail "disable left the block behind"
[[ "$(memory inject --status)" == "disabled" ]] \
    || fail "the block is gone but status still says enabled"

# ---- an unknown verb is the parser's answer, not a crash

if memory nonsense >"$T/verb-out" 2>&1; then
    fail "an unknown verb has to fail"
fi
grep -q "invalid choice: 'nonsense'" "$T/verb-out" \
    || fail "the unknown verb error is not the parser's"

echo "PASS: agent-memory CLI"
