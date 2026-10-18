"""The engine: the fold, the caps, the digest, the injection.

pytest style, and runnable standalone with
`python3 agent-memory/tests/test_memory_core.py`, because a maintainer on a
machine without pytest still has to be able to prove this works.

Every case drives the module the way the CLI does: the file is exec'd with
its own namespace under a throwaway APHOTIC_STATE_HOME and HOME, so nothing
here can read a real memory store or a real ~/.claude/CLAUDE.md.
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

CORE = pathlib.Path(__file__).resolve().parent.parent / "python" / "memory_core.py"

# The one failure the whole design turns on: an errored tool call whose
# message names a path and a line number.
FAILURE = 'jq: error (at /tmp/x:12): Cannot index string with "a"'


def event(**fields):
    return json.dumps(fields, separators=(",", ":"))


def base(**fields):
    record = {"v": 2, "harness": "omp", "sessionId": "o1", "ts": "2026-10-07T18:31:40Z"}
    record.update(fields)
    return event(**record)


FIXTURE = "\n".join([
    base(event="session_start", status="running", t=1791397100000, cwd="/repo"),
    base(event="turn", status="running", t=1791397100100),
    "{not valid json at all",
    base(event="tool_call", tool="bash", toolId="c1", toolStatus="running", t=1791397101000),
    base(event="tool_call", tool="bash", toolId="c1", toolStatus="completed",
         t=1791397101500, durationMs=400),
    base(event="tool_call", tool="bash", toolId="c2", toolStatus="running", t=1791397102000),
    base(event="tool_call", tool="bash", toolId="c2", toolStatus="errored", t=1791397102500,
         error={"kind": "exit-nonzero", "message": FAILURE}),
    event(v=1, sessionId="o1", event="post_tool_use_failure",
          timestamp="2026-10-07T18:31:43Z", t=1791397103000, tool="grep"),
    json.dumps({"v": 2, "harness": "claude", "sessionId": "o2", "event": "session_start",
                "status": "running", "t": 1791397200000, "ts": "2026-10-07T18:33:20Z",
                "cwd": "/home/tcrypt/aphotic-plugins"}, separators=(",", ":")),
]) + "\n"


def load_core(root):
    """Exec the engine under a throwaway state home and hand back its
    namespace, so a test calls the very code the CLI calls."""
    os.environ["APHOTIC_STATE_HOME"] = str(root / "aphotic")
    os.environ["HOME"] = str(root)
    namespace = {"__name__": "memory_core_under_test"}
    exec(compile(CORE.read_text(encoding="utf-8"), str(CORE), "exec"), namespace)
    return namespace


def state_dir(root):
    state = root / "aphotic"
    state.mkdir(parents=True, exist_ok=True)
    return state


def write_events(root, text=FIXTURE):
    (state_dir(root) / "agent-events.jsonl").write_text(text, encoding="utf-8")
    return state_dir(root)


def run_cli(root, *argv):
    env = dict(os.environ)
    env["APHOTIC_STATE_HOME"] = str(root / "aphotic")
    env["HOME"] = str(root)
    return subprocess.run([sys.executable, str(CORE), *argv],
                          capture_output=True, text=True, env=env)


def claude_md(root):
    return root / ".claude" / "CLAUDE.md"


def store_of(root):
    return json.loads((root / "aphotic" / "agent-memory" / "store.json").read_text(encoding="utf-8"))


def issue_for(store, tool):
    return next(e for e in store["errors"] if e["tool"] == tool)


# --- the fold -------------------------------------------------------------

def test_fold_counts_projects_tools_and_issues(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    store = store_of(tmp_path)

    aphotic = store["projects"]["/home/tcrypt/aphotic-plugins"]
    assert aphotic["sessions"] == 1
    assert aphotic["tools"] == {}
    assert aphotic["harnesses"] == {"claude": 1}

    repo = store["projects"]["/repo"]
    assert repo["sessions"] == 1
    assert repo["turns"] == 1
    assert repo["tools"]["bash"] == {"calls": 2, "failures": 1, "totalMs": 400}
    assert repo["harnesses"] == {"omp": 1}

    # The v1 failure line folded into the same project through the session
    # map, and the malformed line cost nothing.
    assert repo["tools"]["grep"] == {"calls": 1, "failures": 1, "totalMs": 0}
    assert repo["failureCount"] == 2

    assert len(store["errors"]) == 2
    failed = issue_for(store, "bash")
    assert failed["kind"] == "exit-nonzero"
    assert failed["message"] == FAILURE
    assert failed["count"] == 1
    assert failed["sessions"] == ["o1"]
    assert failed["resolved"] is False


def test_build_is_idempotent(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    first = store_of(tmp_path)
    assert core["main"](["build"]) == 0
    again = store_of(tmp_path)
    again.pop("lastBuild")
    first.pop("lastBuild")
    assert again == first


def test_second_occurrence_of_the_same_failure_counts_up(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    # A second crash of the same shape, later, in the same session, against
    # a different path and line: one issue with a count of two.
    again = base(event="tool_call", tool="bash", toolId="c9", toolStatus="errored",
                 t=1791397109000,
                 error={"kind": "exit-nonzero",
                        "message": FAILURE.replace("/tmp/x:12", "/tmp/y:47")})
    write_events(tmp_path, (tmp_path / "aphotic" / "agent-events.jsonl").read_text(encoding="utf-8") + again + "\n")
    assert core["main"](["build"]) == 0
    store = store_of(tmp_path)
    assert issue_for(store, "bash")["count"] == 2
    assert store["projects"]["/repo"]["tools"]["bash"]["calls"] == 3
    # Two failed bash calls plus the v1 grep failure folded earlier.
    assert store["projects"]["/repo"]["failureCount"] == 3


def test_signature_ignores_paths_numbers_and_hex(tmp_path):
    core = load_core(tmp_path)
    lines = [
        base(event="session_start", status="running", t=1791397100000, cwd="/repo"),
        base(event="error", status="idle", t=1791397101000,
             error={"kind": "parse", "message": "failed on /etc/a.conf line 42 at 0xdeadbeefcafe"}),
        base(event="error", status="idle", t=1791397102000,
             error={"kind": "parse", "message": "failed on /etc/b.conf line 7 at 0x112233445566"}),
    ]
    write_events(tmp_path, "\n".join(lines) + "\n")
    assert core["main"](["build"]) == 0
    store = store_of(tmp_path)
    assert len(store["errors"]) == 1
    assert store["errors"][0]["count"] == 2


def test_signature_separates_tools(tmp_path):
    normalize = load_core(tmp_path)["normalize_message"]
    assert normalize("jq failed at /tmp/x:12") == normalize("jq failed at /tmp/y:9")
    assert normalize("bash failed at /tmp/x:12") != normalize("sed failed at /tmp/x:12")


def test_hook_failures_split_by_command_and_line(tmp_path):
    core = load_core(tmp_path)
    fail = lambda t, tid, err: base(event="tool_call", tool="Bash", toolId=tid,
                                    toolStatus="errored", t=t, error=err)
    lines = [
        base(event="session_start", status="running", t=1791397100000, cwd="/repo"),
        fail(1791397101000, "a", {"cmd": "jq", "exit": 127, "head": "bash: line 1: jq: command not found"}),
        fail(1791397102000, "b", {"cmd": "jq", "exit": 127, "head": "bash: line 3: jq: command not found"}),
        fail(1791397103000, "c", {"cmd": "git", "exit": 1, "head": "! [rejected] main -> main (fetch first)"}),
        fail(1791397104000, "d", {"cmd": "sleep", "interrupt": True}),
        fail(1791397105000, "e", {}),
    ]
    write_events(tmp_path, "\n".join(lines) + "\n")
    assert core["main"](["build"]) == 0
    store = store_of(tmp_path)
    by_cmd = {e["cmd"]: e for e in store["errors"]}
    assert by_cmd["jq"]["count"] == 2
    assert by_cmd["jq"]["kind"] == "exit-127"
    assert by_cmd["jq"]["message"] == "bash: line 1: jq: command not found"
    assert by_cmd["git"]["kind"] == "exit-1"
    assert by_cmd["sleep"]["kind"] == "interrupted"
    assert by_cmd[""]["kind"] == "exit-nonzero"
    assert len(store["errors"]) == 4
    digest = (tmp_path / "aphotic" / "agent-memory" / "context.md").read_text(encoding="utf-8")
    assert "tool=Bash cmd=jq kind=exit-127 count=2" in digest


def test_store_without_cmd_loads(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    path = tmp_path / "aphotic" / "agent-memory" / "store.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    for entry in data["errors"]:
        entry.pop("cmd", None)
    path.write_text(json.dumps(data), encoding="utf-8")
    store = core["load_store"]()
    assert all(entry["cmd"] == "" for entry in store["errors"])


def test_project_without_a_session_start_is_unattributed(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path, base(event="tool_call", tool="bash", toolId="z1",
                                toolStatus="completed", t=1791397101500) + "\n")
    assert core["main"](["build"]) == 0
    assert "(unattributed)" in store_of(tmp_path)["projects"]


# --- caps and pruning -----------------------------------------------------

def test_errors_are_capped_per_project(tmp_path):
    core = load_core(tmp_path)
    lines = [base(event="session_start", status="running", t=1791397100000, cwd="/repo")]
    for index in range(55):
        lines.append(base(event="error", status="idle", t=1791397101000 + index,
                          error={"kind": f"x{index}", "message": f"failure {index}"}))
    for repeat in range(5):
        lines.append(base(event="error", status="idle", t=1791397109000 + repeat,
                          error={"kind": "x0", "message": "failure 0"}))
    write_events(tmp_path, "\n".join(lines) + "\n")
    assert core["main"](["build"]) == 0
    store = store_of(tmp_path)
    assert len(store["errors"]) == 50
    assert store["errors"][0]["count"] == 6


# --- the digest -----------------------------------------------------------

def test_digest_shape(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    text = core["digest"](store_of(tmp_path))
    lines = text.split("\n")
    assert lines[0].startswith("# agent memory -- generated ")
    assert "projects=" in lines[1]
    assert "project /repo" in lines
    assert "  sessions=1 turns=1 tool_calls=3 failures=2" in lines
    issue = next(line for line in lines if "tool=bash" in line)
    assert issue.startswith("  issue ")
    assert "kind=exit-nonzero" in issue
    assert "count=1" in issue
    # The path and the line number are what the signature collapsed.
    assert "/tmp/x:12" not in issue
    assert f':: jq: error (at <path>:<n>): cannot index string with "a"' in issue


def test_digest_of_an_empty_store_is_one_line(tmp_path):
    core = load_core(tmp_path)
    assert core["digest"](core["load_store"]()) == "# agent memory -- no sessions recorded yet"


def test_digest_hides_resolved_issues(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    sig = issue_for(store_of(tmp_path), "bash")["sig"]
    assert core["main"](["resolve", sig]) == 0
    assert sig not in core["digest"](core["load_store"]())
    assert core["main"](["reopen", sig]) == 0
    assert sig in core["digest"](core["load_store"]())


def test_digest_is_capped(tmp_path):
    core = load_core(tmp_path)
    store = core["load_store"]()
    for index in range(20):
        path = f"/repo/{index}"
        store["projects"][path] = {
            "lastSeen": 1791397100000 + index,
            "sessions": 1,
            "turns": 2,
            "harnesses": {"omp": 1},
            "tools": {"bash": {"calls": 3, "failures": 0, "totalMs": 0}},
            "failureCount": 0,
            "errorCount": 0,
        }
        for note in range(4):
            store["notes"].append({"id": f"n{index}{note}", "project": path,
                                   "text": f"note {note}", "created": 1791397100000 + note})
    lines = core["digest"](store).split("\n")
    assert 2 < len(lines) <= 40
    assert lines[0].startswith("# agent memory -- generated ")


# --- notes and issues -----------------------------------------------------

def test_notes_round_trip(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    assert core["main"](["note", "rebuild the index after a manifest edit"]) == 0
    assert core["main"](["note", "second thought"]) == 0
    store = store_of(tmp_path)
    assert [n["id"] for n in store["notes"]] == ["n0", "n1"]
    assert store["notes"][0]["project"] == "/home/tcrypt/aphotic-plugins"
    assert core["main"](["forget", "n0"]) == 0
    assert [n["id"] for n in store_of(tmp_path)["notes"]] == ["n1"]
    assert core["main"](["forget", "n0"]) == 2


def test_note_needs_a_project(tmp_path):
    core = load_core(tmp_path)
    assert core["main"](["note", "nowhere to put it"]) == 2


def test_resolve_by_unique_prefix_and_ambiguity(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    store = store_of(tmp_path)
    store["errors"] = [dict(store["errors"][0], sig="abcd11112222"),
                       dict(store["errors"][0], sig="abcd33334444")]
    (tmp_path / "aphotic" / "agent-memory" / "store.json").write_text(
        json.dumps(store), encoding="utf-8")
    assert core["main"](["resolve", "abcd"]) == 2
    assert core["main"](["resolve", "abcd1"]) == 0
    assert store_of(tmp_path)["errors"][0]["resolved"] is True
    assert core["main"](["reopen", "abcd1"]) == 0
    assert store_of(tmp_path)["errors"][0]["resolved"] is False


def test_unknown_project_is_an_error_with_candidates(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    assert core["main"](["errors", "--project", "nope"]) == 2
    assert core["main"](["errors", "--project", "aphotic-plugins"]) == 0


# --- injection ------------------------------------------------------------

def test_inject_is_idempotent_and_leaves_everything_else_alone(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    target = claude_md(tmp_path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("# my rules\n\nstay here\n", encoding="utf-8")
    assert core["main"](["inject", "--enable"]) == 0
    first = target.read_bytes()
    assert core["main"](["inject", "--enable"]) == 0
    assert target.read_bytes() == first
    text = first.decode("utf-8")
    assert text.startswith("# my rules\n\nstay here\n")
    assert "<!-- aphotic:agent-memory:start -->" in text
    assert "<!-- aphotic:agent-memory:end -->" in text
    assert core["main"](["inject", "--status"]) == 0
    assert core["main"](["inject", "--disable"]) == 0
    remaining = target.read_text(encoding="utf-8")
    assert remaining.startswith("# my rules\n\nstay here")
    assert "agent-memory" not in remaining


def test_inject_starts_a_fresh_claude_file(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    target = claude_md(tmp_path)
    assert not target.exists()
    assert core["main"](["inject", "--enable"]) == 0
    assert target.read_text(encoding="utf-8").startswith("<!-- aphotic:agent-memory:start -->")
    assert core["main"](["inject", "--disable"]) == 0
    assert target.read_text(encoding="utf-8") == ""


# --- the command, end to end ----------------------------------------------

def test_cli_reports_the_fixture_numbers(tmp_path):
    write_events(tmp_path)
    built = run_cli(tmp_path, "build")
    assert built.returncode == 0, built.stderr
    stats = run_cli(tmp_path, "stats")
    assert stats.returncode == 0, stats.stderr
    assert "projects=2" in stats.stdout
    assert "tool_calls=3" in stats.stdout
    assert "failures=2" in stats.stdout
    assert "open_issues=2" in stats.stdout

    context = run_cli(tmp_path, "context")
    assert context.returncode == 0
    issue = next(line for line in context.stdout.split("\n") if "tool=bash" in line)
    assert issue.startswith("  issue ")
    assert "kind=exit-nonzero" in issue


if __name__ == "__main__":
    import inspect

    for name in sorted(globals()):
        if not name.startswith("test_") or not callable(globals()[name]):
            continue
        function = globals()[name]
        arguments = inspect.signature(function).parameters
        with tempfile.TemporaryDirectory() as directory:
            if arguments:
                function(pathlib.Path(directory))
            else:
                function()
        print(f"PASS: {name}")


# --- lessons --------------------------------------------------------------

def _repeated(times, sessions=2, t0=1791397101000):
    lines = [base(event="session_start", status="running", t=1791397100000 + n, cwd="/repo",
                  sessionId=f"o{1 + n}") for n in range(sessions)]
    for n in range(times):
        lines.append(base(event="tool_call", tool="Bash", toolId=f"r{n}", toolStatus="errored",
                          sessionId=f"o{1 + n % sessions}", t=t0 + n * 1000,
                          error={"cmd": "jq", "exit": 127, "head": "jq: command not found"}))
    return lines


def test_a_failure_becomes_a_candidate_after_three_hits_in_two_sessions(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path, "\n".join(_repeated(2)) + "\n")
    assert core["main"](["build"]) == 0
    assert core["candidates"](core["load_store"]()) == []
    write_events(tmp_path, "\n".join(_repeated(3)) + "\n")
    assert core["main"](["build"]) == 0
    found = core["candidates"](core["load_store"]())
    assert [e["cmd"] for e in found] == ["jq"]


def test_promote_writes_a_rule_and_later_failures_count_as_hits(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path, "\n".join(_repeated(3)) + "\n")
    assert core["main"](["build"]) == 0
    sig = core["candidates"](core["load_store"]())[0]["sig"]
    assert core["main"](["promote", sig[:6], "Hosts .25 and .30 have no jq; parse on this machine"]) == 0
    store = store_of(tmp_path)
    assert store["lessons"][0]["sig"] == sig and store["lessons"][0]["project"] == "/repo"
    assert core["candidates"](core["load_store"]()) == []
    later = _repeated(5, t0=9_000_000_000_000)[-2:]
    write_events(tmp_path, "\n".join(_repeated(3) + later) + "\n")
    assert core["main"](["build"]) == 0
    assert store_of(tmp_path)["lessons"][0]["hits"] == 2
    digest = (tmp_path / "aphotic" / "agent-memory" / "context.md").read_text(encoding="utf-8")
    lines = digest.splitlines()
    assert lines[1].startswith("Rules learned from past failures")
    assert "Hosts .25 and .30 have no jq; parse on this machine [repo] (broken 2x since written)" in digest


def test_promote_refuses_an_unknown_signature_and_empty_text(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    assert core["main"](["promote", "zzzzzz", "x"]) == 2
    assert core["main"](["promote", "-", ""]) == 2
    assert core["main"](["promote", "-", "Always run the tests"]) == 0
    assert store_of(tmp_path)["lessons"][0]["project"] == ""


def test_retire_removes_only_that_lesson(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    core["main"](["promote", "-", "one"])
    core["main"](["promote", "-", "two"])
    assert core["main"](["retire", "l1"]) == 0
    assert [l["text"] for l in store_of(tmp_path)["lessons"]] == ["two"]
    assert core["main"](["retire", "l9"]) == 2


def test_sources_import_memory_files_and_rule_lines_read_only(tmp_path):
    memory = tmp_path / "mem"
    memory.mkdir()
    (memory / "MEMORY.md").write_text("- index\n", encoding="utf-8")
    (memory / "a.md").write_text("---\nname: no-jq\ndescription: Hosts .25/.30 have no jq\n"
                                 "metadata:\n  type: feedback\n---\n\nUse python.\n**Why:** PVE minimal.\n",
                                 encoding="utf-8")
    (memory / "b.md").write_text("---\nname: who\ndescription: The user is an operator\ntype: user\n---\n",
                                 encoding="utf-8")
    incidents = tmp_path / "incidents.md"
    incidents.write_text("# Incidents\n\n## 2026-10-03 build froze the box\n**Rule:** no heavy build while "
                         "the engine is resident.\n", encoding="utf-8")
    before = {p: p.read_bytes() for p in [incidents, *memory.iterdir()]}
    config = tmp_path / "cfg" / "aphotic" / "agent-memory"
    config.mkdir(parents=True)
    (config / "sources.toml").write_text(
        f'[[source]]\nkind = "claude-memory"\npath = "{memory}"\n\n'
        f'[[source]]\nkind = "rule-lines"\npath = "{incidents}"\nlabel = "incidents"\n', encoding="utf-8")
    os.environ["XDG_CONFIG_HOME"] = str(tmp_path / "cfg")
    try:
        core = load_core(tmp_path)
        write_events(tmp_path)
        assert core["main"](["build"]) == 0
    finally:
        del os.environ["XDG_CONFIG_HOME"]
    imported = store_of(tmp_path)["imported"]
    assert sorted(i["text"] for i in imported) == [
        "Hosts .25/.30 have no jq", "no heavy build while the engine is resident."]
    rule = next(i for i in imported if i["kind"] == "rule")
    assert rule["why"] == "2026-10-03 build froze the box" and rule["label"] == "incidents"
    assert next(i for i in imported if i["kind"] == "feedback")["why"] == "PVE minimal."
    assert {p: p.read_bytes() for p in before} == before
    # A pinned import becomes a lesson that keeps its source.
    assert core["main"](["promote", rule["id"]]) == 0
    assert store_of(tmp_path)["lessons"][0]["source"] == str(incidents)


def test_missing_sources_file_imports_nothing(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    assert store_of(tmp_path)["imported"] == []


# --- injection into every harness -------------------------------------------

def _registry(tmp_path, *entries):
    path = state_dir(tmp_path) / "harnesses.json"
    path.write_text(json.dumps({"schemaVersion": 1, "harnesses": list(entries)}), encoding="utf-8")


def test_targets_come_from_the_registry_with_claude_as_the_floor(tmp_path):
    core = load_core(tmp_path)
    _registry(tmp_path, {"id": "codex", "label": "Codex", "instructions": ".codex/AGENTS.md"},
              {"id": "omp", "label": "Oh My Pi", "instructions": ""},
              {"id": "bad", "instructions": "/etc/passwd"})
    targets = core["injection_targets"]()
    assert [t["id"] for t in targets] == ["claude", "codex"]
    assert targets[1]["path"] == str(tmp_path / ".codex" / "AGENTS.md")


def test_inject_one_harness_and_build_refreshes_only_enabled_files(tmp_path):
    core = load_core(tmp_path)
    _registry(tmp_path, {"id": "codex", "label": "Codex", "instructions": ".codex/AGENTS.md"})
    write_events(tmp_path, "\n".join(_repeated(3)) + "\n")
    assert core["main"](["build"]) == 0
    agents = tmp_path / ".codex" / "AGENTS.md"
    agents.parent.mkdir(parents=True)
    agents.write_text("# codex rules\n", encoding="utf-8")
    assert core["main"](["inject", "--enable", "--harness", "codex"]) == 0
    text = agents.read_text(encoding="utf-8")
    assert text.startswith("# codex rules\n")
    assert "Failing repeatedly with no rule yet" in text and "project /repo" not in text
    assert not claude_md(tmp_path).exists()
    sig = core["candidates"](core["load_store"]())[0]["sig"]
    assert core["main"](["promote", sig, "Use python for JSON on the PVE hosts"]) == 0
    assert core["main"](["build"]) == 0
    assert "Use python for JSON on the PVE hosts" in agents.read_text(encoding="utf-8")
    assert not claude_md(tmp_path).exists()
    assert core["main"](["inject", "--disable", "--harness", "codex"]) == 0
    assert agents.read_text(encoding="utf-8") == "# codex rules\n"


def test_inject_an_unknown_harness_is_an_error(tmp_path):
    core = load_core(tmp_path)
    assert core["main"](["inject", "--enable", "--harness", "nope"]) == 2


def test_disable_restores_the_file_byte_for_byte(tmp_path):
    core = load_core(tmp_path)
    write_events(tmp_path)
    assert core["main"](["build"]) == 0
    target = claude_md(tmp_path)
    target.parent.mkdir(parents=True, exist_ok=True)
    for original in ("# a\n", "# a\n\n", "# a\n\nb\n\n\n"):
        target.write_text(original, encoding="utf-8")
        assert core["main"](["inject", "--enable"]) == 0
        assert core["main"](["inject", "--disable"]) == 0
        assert target.read_text(encoding="utf-8") == original
