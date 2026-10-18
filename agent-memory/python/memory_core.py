#!/usr/bin/env python3
"""agent-memory -- fold local agent session events into a durable memory.

Reads the one feed the harness hook plugins already write
(~/.local/state/aphotic/agent-events.jsonl, see HARNESS_HOOKS_V2.md for the
envelope) and accumulates, under ~/.local/state/aphotic/agent-memory/:

  store.json   cumulative state: per-project counters, error signatures with
               occurrence counts, and the notes the user adds
  context.md   a deterministic digest of that store, the same text
               `inject --enable` writes into ~/.claude/CLAUDE.md

The fold is a whole-file scan with an idempotent key ring, so running
`build` twice on an unchanged file is free, and running it after the live
log rotated is still cumulative: the counters live in the store, not in a
cursor over the file.

No model, no network, no inference. The same file and store always produce
the same output, which is the property everything else here relies on.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import time

STATE = os.environ.get("APHOTIC_STATE_HOME") or os.path.expanduser("~/.local/state/aphotic")
EVENTS = os.path.join(STATE, "agent-events.jsonl")
DATA_DIR = os.path.join(STATE, "agent-memory")
STORE_PATH = os.path.join(DATA_DIR, "store.json")
CONTEXT_PATH = os.path.join(DATA_DIR, "context.md")
CLAUDE_MD = os.path.expanduser("~/.claude/CLAUDE.md")
SOURCES_PATH = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
                            "aphotic", "agent-memory", "sources.toml")

STORE_VERSION = 2
MARKER_START = "<!-- aphotic:agent-memory:start -->"
MARKER_END = "<!-- aphotic:agent-memory:end -->"
EMPTY_DIGEST = "# agent memory -- no sessions recorded yet"
NO_PROJECT = "(unattributed)"

MAX_RECENT = 5000
MAX_ERRORS_PER_PROJECT = 50
MAX_ERRORS = 400
MAX_PROJECTS = 200
MAX_NOTES = 300
MAX_SESSIONS_PER_ERROR = 8
MAX_KNOWN_SESSIONS = 500
MAX_DIGEST_LINES = 40
MAX_DIGEST_SECTIONS = 8
MAX_LIST_LINES = 100
MAX_LESSONS = 200
MAX_IMPORTED = 400
MAX_IMPORT_FILES = 200
CANDIDATE_COUNT = 3
CANDIDATE_SESSIONS = 2
MAX_DIGEST_RULES = 12
MAX_DIGEST_CANDIDATES = 8


# --- store ----------------------------------------------------------------

def now_ms():
    return int(time.time() * 1000)


def empty_project():
    return {
        "lastSeen": 0,
        "sessions": 0,
        "turns": 0,
        "harnesses": {},
        "tools": {},
        "failureCount": 0,
        "errorCount": 0,
    }


def load_store():
    store = {
        "version": STORE_VERSION,
        "lastBuild": 0,
        "recent": [],
        "sessions": {},
        "projects": {},
        "errors": [],
        "nextNoteId": 0,
        "notes": [],
        "nextLessonId": 0,
        "lessons": [],
        "imported": [],
    }
    try:
        with open(STORE_PATH, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return store
    if not isinstance(data, dict):
        return store
    store["recent"] = _string_list(data.get("recent"))
    known = data.get("sessions")
    if isinstance(known, dict):
        store["sessions"] = {str(k): str(v) for k, v in known.items() if isinstance(v, str)}
    store["nextNoteId"] = _int(data.get("nextNoteId"))
    store["lastBuild"] = _int(data.get("lastBuild"))
    projects = data.get("projects")
    if isinstance(projects, dict):
        for path, entry in projects.items():
            if not isinstance(path, str) or not isinstance(entry, dict):
                continue
            merged = empty_project()
            merged.update({k: entry[k] for k in merged if k in entry})
            if isinstance(merged.get("harnesses"), dict):
                merged["harnesses"] = {str(k): _int(v) for k, v in merged["harnesses"].items()}
            tools = {}
            if isinstance(entry.get("tools"), dict):
                for tool, slot in entry["tools"].items():
                    if isinstance(slot, dict):
                        tools[str(tool)] = {
                            "calls": _int(slot.get("calls")),
                            "failures": _int(slot.get("failures")),
                            "totalMs": _int(slot.get("totalMs")),
                        }
            merged["tools"] = tools
            store["projects"][path] = merged
    errors = data.get("errors")
    if isinstance(errors, list):
        for entry in errors:
            if not isinstance(entry, dict) or not entry.get("sig"):
                continue
            store["errors"].append({
                "sig": str(entry.get("sig")),
                "project": str(entry.get("project") or NO_PROJECT),
                "tool": str(entry.get("tool") or ""),
                "kind": str(entry.get("kind") or ""),
                "message": str(entry.get("message") or ""),
                "cmd": str(entry.get("cmd") or ""),
                "count": max(1, _int(entry.get("count"))),
                "first": _int(entry.get("first")),
                "last": _int(entry.get("last")),
                "sessions": _string_list(entry.get("sessions")),
                "resolved": bool(entry.get("resolved")),
            })
    notes = data.get("notes")
    if isinstance(notes, list):
        for entry in notes:
            if not isinstance(entry, dict) or not entry.get("id"):
                continue
            store["notes"].append({
                "id": str(entry.get("id")),
                "project": str(entry.get("project") or NO_PROJECT),
                "text": str(entry.get("text") or ""),
                "created": _int(entry.get("created")),
            })
    store["nextLessonId"] = _int(data.get("nextLessonId"))
    lessons = data.get("lessons")
    if isinstance(lessons, list):
        for entry in lessons:
            if not isinstance(entry, dict) or not entry.get("id") or not entry.get("text"):
                continue
            store["lessons"].append({
                "id": str(entry["id"]),
                "text": str(entry["text"]),
                "why": str(entry.get("why") or ""),
                "project": str(entry.get("project") or ""),
                "sig": str(entry.get("sig") or ""),
                "source": str(entry.get("source") or ""),
                "created": _int(entry.get("created")),
                "hits": _int(entry.get("hits")),
                "lastHit": _int(entry.get("lastHit")),
            })
    imported = data.get("imported")
    if isinstance(imported, list):
        store["imported"] = [entry for entry in imported
                             if isinstance(entry, dict) and entry.get("id") and entry.get("text")]
    return store


def _string_list(value):
    if not isinstance(value, list):
        return []
    return [str(item) for item in value if isinstance(item, (str, int, float))]


def _int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def save_store(store):
    marked = {entry["sig"] + entry["project"] for entry in candidates(store)}
    for entry in store["errors"]:
        entry["candidate"] = entry["sig"] + entry["project"] in marked
    os.makedirs(DATA_DIR, exist_ok=True)
    atomic_write(STORE_PATH, json.dumps(store, indent=1, sort_keys=False) + "\n")


def atomic_write(path, text):
    """Write text to path atomically: a temp file beside it, then rename."""
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, path)


# --- fold -----------------------------------------------------------------

def normalize_message(message):
    """Collapse a failure message to the shape that repeats.

    Paths, numbers and hex runs become placeholders, so "jq failed on
    /tmp/x:12" and "jq failed on /tmp/y:47" are one signature rather than
    two one-off issues.
    """
    text = str(message or "").lower()
    text = re.sub(r"0x[0-9a-f]+", "<hex>", text)
    text = re.sub(r"\b[0-9a-f]{8,}\b", "<hex>", text)
    text = re.sub(r"(?:/[\w.\-]+)+/?", "<path>", text)
    text = re.sub(r"\d+(?:\.\d+)?", "<n>", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()[:160]


def clean_message(message):
    """One line, no control characters, bounded length."""
    text = str(message or "").replace("\r", " ").replace("\n", " ")
    text = re.sub(r"[\x00-\x1f\x7f]", " ", text)
    return re.sub(r"\s+", " ", text).strip()[:200]


def signature(kind, tool, message, cmd=""):
    raw = f"{kind}|{tool}|{normalize_message(message)}"
    if cmd:
        raw += f"|{cmd}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:12]


def project_slot(store, key, at):
    entry = store["projects"].get(key)
    if entry is None:
        entry = empty_project()
        store["projects"][key] = entry
    if at > entry["lastSeen"]:
        entry["lastSeen"] = at
    return entry


def record_error(store, project, tool, kind, message, at, session_id, cmd=""):
    cmd = clean_message(cmd)[:40]
    sig = signature(kind, tool, message, cmd)
    message = clean_message(message)
    for entry in store["errors"]:
        if entry["sig"] != sig or entry["project"] != project:
            continue
        entry["count"] += 1
        entry["last"] = at
        if message and not entry["message"]:
            entry["message"] = message
        if session_id and session_id not in entry["sessions"]:
            entry["sessions"].append(session_id)
            del entry["sessions"][:-MAX_SESSIONS_PER_ERROR]
        count_hit(store, sig, project, at)
        return
    count_hit(store, sig, project, at)
    store["errors"].append({
        "sig": sig,
        "project": project,
        "tool": tool,
        "kind": kind,
        "message": message,
        "cmd": cmd,
        "count": 1,
        "first": at,
        "last": at,
        "sessions": [session_id] if session_id else [],
        "resolved": False,
    })


def count_hit(store, sig, project, at):
    """A failure the user already wrote a rule for. The rule is not reaching
    the agent, and the hit count is how that shows."""
    for lesson in store["lessons"]:
        if lesson["sig"] != sig or at <= lesson["created"]:
            continue
        if lesson["project"] and lesson["project"] != project:
            continue
        lesson["hits"] += 1
        lesson["lastHit"] = max(lesson["lastHit"], at)


def fold(store):
    """Replay the live event log into the store. Safe to run repeatedly."""
    seen = set(store["recent"])
    order = list(store["recent"])
    # A session_start already folded in an earlier build is in the key ring
    # and is never replayed, so the session to project map has to come from
    # the store. Without it, the second occurrence of a failure in a
    # session whose start line has rotated counts against no project at all.
    sessions = dict(store["sessions"])
    try:
        with open(EVENTS, "r", encoding="utf-8", errors="replace") as handle:
            lines = handle.read().split("\n")
    except OSError:
        lines = []
    for line in lines:
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if not isinstance(record, dict):
            continue
        session_id = record.get("sessionId")
        event = record.get("event") or ""
        if not session_id or not event:
            continue
        at = _int(record.get("t"))
        key = f"{session_id}|{at}|{event}|{record.get('toolId') or ''}"
        if key in seen:
            continue
        seen.add(key)
        order.append(key)
        if record.get("v") == 2:
            fold_v2(store, sessions, record, event, at, session_id)
        else:
            fold_v1(store, sessions, record, event, at, session_id)
    store["recent"] = order[-MAX_RECENT:]
    prune(store)
    store["lastBuild"] = now_ms()
    return store


def fold_v2(store, sessions, record, event, at, session_id):
    if event == "session_start":
        # The one record that names the working directory, so everything
        # in this session attributes here.
        key = record.get("cwd") or NO_PROJECT
        sessions[session_id] = key
        store["sessions"][session_id] = key
        entry = project_slot(store, key, at)
        entry["sessions"] += 1
        harness = str(record.get("harness") or "claude")
        entry["harnesses"][harness] = entry["harnesses"].get(harness, 0) + 1
        return
    key = sessions.get(session_id) or (record.get("cwd") or NO_PROJECT)
    if event == "tool_call":
        status = record.get("toolStatus") or ""
        if status == "running":
            # The pre-call half: a call is counted once, when it ends.
            return
        tool = str(record.get("tool") or "unknown")
        entry = project_slot(store, key, at)
        slot = entry["tools"].setdefault(tool, {"calls": 0, "failures": 0, "totalMs": 0})
        slot["calls"] += 1
        duration = record.get("durationMs")
        if isinstance(duration, (int, float)) and duration > 0:
            slot["totalMs"] += int(duration)
        if status == "errored":
            slot["failures"] += 1
            entry["failureCount"] += 1
            error = record.get("error") if isinstance(record.get("error"), dict) else {}
            code = error.get("exit")
            if error.get("interrupt") is True:
                kind = "interrupted"
            elif isinstance(code, int) and not isinstance(code, bool):
                kind = f"exit-{code}"
            else:
                kind = "exit-nonzero"
            message = error.get("head") or error.get("message") or ""
            record_error(store, key, tool, kind, message, at, session_id, str(error.get("cmd") or ""))
        return
    if event == "error":
        error = record.get("error") if isinstance(record.get("error"), dict) else {}
        entry = project_slot(store, key, at)
        entry["errorCount"] += 1
        record_error(store, key, str(record.get("tool") or ""),
                    str(error.get("kind") or "error"), error.get("message") or "", at, session_id)
        return
    if event == "turn":
        if record.get("status") == "running":
            project_slot(store, key, at)["turns"] += 1
        return
    if event == "session_end":
        project_slot(store, key, at)
        return
    # usage and quota carry billing, not anything a memory keeps.


def fold_v1(store, sessions, record, event, at, session_id):
    if event not in ("post_tool_use", "post_tool_use_failure"):
        return
    key = record.get("cwd") or sessions.get(session_id) or NO_PROJECT
    tool = str(record.get("tool") or "unknown")
    entry = project_slot(store, key, at)
    slot = entry["tools"].setdefault(tool, {"calls": 0, "failures": 0, "totalMs": 0})
    slot["calls"] += 1
    if event == "post_tool_use_failure":
        slot["failures"] += 1
        entry["failureCount"] += 1
        record_error(store, key, tool, "exit-nonzero", "", at, session_id)


def prune(store):
    """Bound the store. Every cap is a stable sort, so trimming never
    depends on dict iteration order."""
    kept = {}
    for entry in store["errors"]:
        kept.setdefault(entry["project"], []).append(entry)
    folded = []
    for project in sorted(kept):
        ranked = sorted(kept[project], key=lambda e: (-e["count"], -e["last"], e["sig"]))
        folded.extend(ranked[:MAX_ERRORS_PER_PROJECT])
    folded.sort(key=lambda e: (-e["count"], -e["last"], e["sig"]))
    store["errors"] = folded[:MAX_ERRORS]

    projects = store["projects"]
    if len(projects) > MAX_PROJECTS:
        ranked = sorted(projects.items(), key=lambda kv: (-kv[1]["lastSeen"], kv[0]))
        store["projects"] = dict(ranked[:MAX_PROJECTS])

    store["notes"] = sorted(store["notes"], key=lambda n: (n["created"], n["id"]))[-MAX_NOTES:]
    store["lessons"] = sorted(store["lessons"], key=lambda n: (n["created"], n["id"]))[-MAX_LESSONS:]
    store["imported"] = store["imported"][:MAX_IMPORTED]
    store["recent"] = store["recent"][-MAX_RECENT:]
    known = store["sessions"]
    if len(known) > MAX_KNOWN_SESSIONS:
        for stale in list(known)[:len(known) - MAX_KNOWN_SESSIONS]:
            del known[stale]


# --- lessons --------------------------------------------------------------

def candidates(store):
    """Open issues that keep coming back with no rule written for them."""
    ruled = {lesson["sig"] for lesson in store["lessons"] if lesson["sig"]}
    found = [e for e in open_issues(store)
             if e["sig"] not in ruled and e["count"] >= CANDIDATE_COUNT
             and len(e["sessions"]) >= CANDIDATE_SESSIONS]
    return sorted(found, key=lambda e: (-e["count"], -e["last"], e["sig"]))


def read_sources():
    """The user's sources file. A missing or unreadable file is no sources."""
    try:
        import tomllib
        with open(SOURCES_PATH, "rb") as handle:
            data = tomllib.load(handle)
    except Exception:
        return []
    out = []
    for entry in data.get("source") or []:
        if isinstance(entry, dict) and entry.get("kind") in ("claude-memory", "rule-lines") and entry.get("path"):
            out.append({"kind": entry["kind"], "path": str(entry["path"]),
                        "label": str(entry.get("label") or entry["path"])})
    return out


def _source_files(source):
    import glob
    pattern = os.path.expanduser(source["path"])
    if source["kind"] == "claude-memory":
        pattern = os.path.join(pattern, "*.md") if not pattern.endswith(".md") else pattern
    files = sorted(f for f in glob.glob(pattern) if os.path.isfile(f))
    return files[:MAX_IMPORT_FILES]


def _frontmatter(text):
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end < 0:
        return {}, text
    fields = {}
    for line in text[3:end].splitlines():
        match = re.match(r"^\s*([A-Za-z_]+):\s*(.*)$", line)
        if match:
            fields[match.group(1)] = match.group(2).strip().strip('"').strip("'")
    return fields, text[end + 4:]


def _import_id(path, text):
    return "i" + hashlib.sha1(f"{path}|{text}".encode("utf-8")).hexdigest()[:10]


def read_claude_memory(path, label):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            text = handle.read(16384)
    except OSError:
        return []
    fields, body = _frontmatter(text)
    if os.path.basename(path) == "MEMORY.md" or fields.get("type") not in ("feedback", "project"):
        return []
    rule = fields.get("description") or ""
    if not rule:
        return []
    why = re.search(r"\*\*Why:\*\*\s*(.+)", body)
    return [{"id": _import_id(path, rule), "text": clean_message(rule),
             "why": clean_message(why.group(1)) if why else "",
             "kind": fields.get("type"), "name": fields.get("name") or os.path.basename(path),
             "source": path, "label": label}]


def read_rule_lines(path, label):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            lines = handle.read(262144).splitlines()
    except OSError:
        return []
    out = []
    heading = ""
    for line in lines:
        if line.startswith("#"):
            heading = line.lstrip("#").strip()
            continue
        match = re.match(r"^\s*\*\*(Rule|Lesson):\*\*\s*(.+)$", line)
        if match:
            rule = clean_message(match.group(2))
            out.append({"id": _import_id(path, rule), "text": rule, "why": clean_message(heading),
                        "kind": match.group(1).lower(), "name": heading, "source": path, "label": label})
    return out


def import_sources(store):
    """Mirror every declared source. Nothing here writes to a source file."""
    found = []
    for source in read_sources():
        reader = read_claude_memory if source["kind"] == "claude-memory" else read_rule_lines
        for path in _source_files(source):
            found.extend(reader(path, source["label"]))
    seen = set()
    unique = []
    for entry in found:
        if entry["id"] not in seen:
            seen.add(entry["id"])
            unique.append(entry)
    store["imported"] = unique[:MAX_IMPORTED]


def add_lesson(store, text, why="", project="", sig="", source=""):
    store["nextLessonId"] += 1
    lesson = {"id": f"l{store['nextLessonId']}", "text": clean_message(text), "why": clean_message(why),
              "project": project, "sig": sig, "source": source, "created": now_ms(),
              "hits": 0, "lastHit": 0}
    store["lessons"].append(lesson)
    return lesson


# --- digest ---------------------------------------------------------------

def utc_date(ms):
    if not ms:
        return "0000-00-00"
    return time.strftime("%Y-%m-%d", time.gmtime(ms / 1000.0))


def tool_calls(entry):
    return sum(slot["calls"] for slot in entry["tools"].values())


def open_issues(store):
    return [entry for entry in store["errors"] if not entry["resolved"]]


def digest(store, project=None, max_lines=MAX_DIGEST_LINES):
    """The injected text. Deterministic, and bounded to max_lines."""
    projects = store["projects"]
    if project is not None:
        if project not in projects:
            raise KeyError(project)
        selected = [project]
        scope = [n for n in store["notes"] if n["project"] == project]
    else:
        selected = sorted(projects,
                          key=lambda k: (-(projects[k]["failureCount"] + projects[k]["errorCount"]),
                                         -projects[k]["lastSeen"], k))[:MAX_DIGEST_SECTIONS]
        scope = store["notes"]
    if not selected:
        return EMPTY_DIGEST

    out = [("fixed", f"# agent memory -- generated {utc_date(now_ms())}")]
    rules = sorted((l for l in store["lessons"] if project is None or l["project"] in ("", project)),
                   key=lambda l: (-l["hits"], -l["created"], l["id"]))[:MAX_DIGEST_RULES]
    if rules:
        out.append(("fixed", "Rules learned from past failures. Follow them before running the command:"))
        for lesson in rules:
            where = f" [{os.path.basename(lesson['project'])}]" if lesson["project"] else ""
            hits = f" (broken {lesson['hits']}x since written)" if lesson["hits"] else ""
            out.append(("rule", f"- {lesson['text']}{where}{hits}"))
    repeat = [e for e in candidates(store) if project is None or e["project"] == project][:MAX_DIGEST_CANDIDATES]
    if repeat:
        out.append(("fixed", "Failing repeatedly with no rule yet. Check before you run these:"))
        for entry in repeat:
            cmd = f" `{entry['cmd']}`" if entry.get("cmd") else ""
            out.append(("candidate", f"- {entry['tool']}{cmd}: {entry['message'] or entry['kind']} "
                                     f"(x{entry['count']}, {len(entry['sessions'])} sessions, "
                                     f"{os.path.basename(entry['project'])})"))
    if project is None:
        out.append(("fixed", f"projects={len(projects)} open_issues={len(open_issues(store))} "
                             f"notes={len(scope)}"))
    for key in selected:
        entry = projects[key]
        out.append(("section", f"project {key}"))
        out.append(("fixed", f"  sessions={entry['sessions']} turns={entry['turns']} "
                            f"tool_calls={tool_calls(entry)} failures={entry['failureCount']}"))
        issues = sorted((e for e in open_issues(store) if e["project"] == key),
                        key=lambda e: (-e["count"], -e["last"], e["sig"]))
        for issue in issues:
            # The normalized message, not the raw one: the digest is the
            # shared shape of the failure, and the exact string is already
            # in the store for anyone who wants it.
            cmd = f" cmd={issue['cmd']}" if issue.get("cmd") else ""
            out.append(("issue", f"  issue {issue['sig']} tool={issue['tool'] or 'none'}{cmd} "
                                 f"kind={issue['kind']} count={issue['count']} "
                                 f"last={utc_date(issue['last'])} :: "
                                 f"{normalize_message(issue['message'])}"))
        notes = sorted((n for n in scope if project is not None or n["project"] == key),
                       key=lambda n: (-n["created"], n["id"]))
        for note in notes:
            out.append(("note", f"  note {note['id']} {utc_date(note['created'])} :: {note['text']}"))
    return "\n".join(text for _, text in cap_lines(out, max_lines))


def cap_lines(out, max_lines):
    """Notes drop first, then whole trailing sections, so a bounded digest
    keeps its headers and its most-repeated issues."""
    entries = list(out)
    while len(entries) > max_lines:
        index = -1
        for position in range(len(entries) - 1, -1, -1):
            if entries[position][0] == "note":
                index = position
                break
        if index < 0:
            break
        del entries[index]
    while len(entries) > max_lines:
        start = -1
        for position in range(len(entries) - 1, -1, -1):
            if entries[position][0] == "section":
                start = position
                break
        if start < 0 or start <= 1:
            break
        del entries[start:]
    return entries[:max_lines]


def write_context(store):
    os.makedirs(DATA_DIR, exist_ok=True)
    atomic_write(CONTEXT_PATH, digest(store) + "\n")


# --- injection ------------------------------------------------------------

def strip_block(text):
    """Remove the marker block and nothing else. Every line outside the
    markers, including blank ones, survives byte for byte."""
    out = []
    skipping = False
    for line in text.split("\n"):
        stripped = line.strip()
        if stripped == MARKER_START:
            skipping = True
            continue
        if skipping:
            if stripped == MARKER_END:
                skipping = False
            continue
        out.append(line)
    return "\n".join(out)


def injection_targets():
    """Every harness that names its global rules file in the registry, plus
    Claude Code's own file, which the plugin has always known."""
    targets = []
    try:
        with open(os.path.join(STATE, "harnesses.json"), "r", encoding="utf-8") as handle:
            registry = json.load(handle)
        harnesses = registry.get("harnesses") if isinstance(registry, dict) else []
    except (OSError, ValueError):
        harnesses = []
    home = os.path.expanduser("~")
    for entry in harnesses or []:
        if not isinstance(entry, dict):
            continue
        rel = entry.get("instructions")
        hid = entry.get("id")
        if not isinstance(rel, str) or not rel or not isinstance(hid, str):
            continue
        if rel.startswith("/") or ".." in rel:
            continue
        targets.append({"id": hid, "label": str(entry.get("label") or hid), "path": os.path.join(home, rel)})
    if not any(t["id"] == "claude" for t in targets):
        targets.insert(0, {"id": "claude", "label": "Claude Code", "path": CLAUDE_MD})
    return targets


def target_for(harness):
    return next((t for t in injection_targets() if t["id"] == harness), None)


def agent_digest(store):
    """What a harness reads at session start: rules first, then the failures
    that keep coming back without one. Project tallies stay in the plane."""
    full = digest(store).split("\n")
    keep = [line for line in full if line.startswith(("# agent memory", "Rules learned", "Failing repeatedly", "- "))]
    if len(keep) <= 1:
        keep.append("No repeated failures on record.")
    return "\n".join(keep[:MAX_DIGEST_LINES])


def inject_enabled(path=None):
    try:
        with open(path or CLAUDE_MD, "r", encoding="utf-8") as handle:
            return MARKER_START in handle.read()
    except OSError:
        return False


def inject_enable(store, path=None):
    path = path or CLAUDE_MD
    body = agent_digest(store) + "\n"
    block = f"{MARKER_START}\n{body}{MARKER_END}\n"
    try:
        with open(path, "r", encoding="utf-8") as handle:
            existing = handle.read()
    except OSError:
        existing = ""
    base = strip_block(existing)
    if base and not base.endswith("\n"):
        base += "\n"
    updated = base + block
    if updated == existing:
        return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    atomic_write(path, updated)
    return True


def inject_disable(path=None):
    path = path or CLAUDE_MD
    try:
        with open(path, "r", encoding="utf-8") as handle:
            existing = handle.read()
    except OSError:
        return False
    updated = strip_block(existing)
    if updated == existing:
        return False
    atomic_write(path, updated)
    return True


def refresh_injections(store):
    """Rewrite the block only where the user already turned it on."""
    for target in injection_targets():
        if inject_enabled(target["path"]):
            inject_enable(store, target["path"])


# --- commands -------------------------------------------------------------

class ProjectNotFound(LookupError):
    """No project matches the name. The candidates are what a caller
    needs to tell the user which projects exist."""

    def __init__(self, name, candidates):
        super().__init__(name)
        self.name = name
        self.candidates = candidates


def resolve_project(store, name):
    """Exact path, else a unique basename. Ambiguity is an error, not a
    silent pick."""
    if name in store["projects"]:
        return name
    matches = sorted(k for k in store["projects"] if os.path.basename(k) == name)
    if len(matches) == 1:
        return matches[0]
    # A name that matched no basename is a typo, and the useful answer is
    # every project on record rather than an empty list.
    raise ProjectNotFound(name, matches if matches else sorted(store["projects"]))


def latest_project(store):
    if not store["projects"]:
        return None
    return sorted(store["projects"].items(), key=lambda kv: (-kv[1]["lastSeen"], kv[0]))[0][0]


def cmd_build(args):
    started = now_ms()
    store = load_store()
    fold(store)
    import_sources(store)
    save_store(store)
    write_context(store)
    refresh_injections(store)
    elapsed = now_ms() - started
    print(f"ok projects={len(store['projects'])} errors={len(store['errors'])} "
          f"notes={len(store['notes'])} lessons={len(store['lessons'])} "
          f"imported={len(store['imported'])} ms={elapsed}")
    return 0


def cmd_projects(args):
    store = load_store()
    rows = sorted(store["projects"].items(),
                  key=lambda kv: (-kv[1]["failureCount"], -kv[1]["lastSeen"], kv[0]))
    if args.json:
        print(json.dumps([{
            "path": path,
            "sessions": entry["sessions"],
            "turns": entry["turns"],
            "calls": tool_calls(entry),
            "failures": entry["failureCount"],
            "lastSeen": entry["lastSeen"],
        } for path, entry in rows], indent=1))
        return 0
    for path, entry in rows[:MAX_LIST_LINES]:
        print(f"{path} sessions={entry['sessions']} turns={entry['turns']} "
              f"calls={tool_calls(entry)} failures={entry['failureCount']} "
              f"last={utc_date(entry['lastSeen'])}")
    return 0


def cmd_errors(args):
    store = load_store()
    if args.project:
        try:
            project = resolve_project(store, args.project)
        except ProjectNotFound as miss:
            return _project_error(miss.name, miss.candidates)
        rows = [e for e in store["errors"] if e["project"] == project]
    else:
        rows = list(store["errors"])
    rows.sort(key=lambda e: (e["resolved"], -e["count"], -e["last"], e["sig"]))
    limit = len(rows) if args.all else MAX_LIST_LINES
    if args.json:
        print(json.dumps(rows[:limit], indent=1))
        return 0
    for entry in rows[:limit]:
        flag = "resolved" if entry["resolved"] else "open"
        print(f"[{flag}] {entry['sig']} count={entry['count']} tool={entry['tool'] or 'none'} "
              f"kind={entry['kind']} project={entry['project']} "
              f"last={utc_date(entry['last'])} :: {entry['message']}")
    return 0


def cmd_notes(args):
    store = load_store()
    if args.project:
        try:
            project = resolve_project(store, args.project)
        except ProjectNotFound as miss:
            return _project_error(miss.name, miss.candidates)
        rows = [n for n in store["notes"] if n["project"] == project]
    else:
        rows = list(store["notes"])
    rows.sort(key=lambda n: (-n["created"], n["id"]))
    if args.json:
        print(json.dumps(rows[:MAX_LIST_LINES], indent=1))
        return 0
    for note in rows[:MAX_LIST_LINES]:
        print(f"{note['id']} {utc_date(note['created'])} {note['project']} :: {note['text']}")
    return 0


def cmd_note(args):
    store = load_store()
    project = None
    if args.project:
        try:
            project = resolve_project(store, args.project)
        except ProjectNotFound as miss:
            return _project_error(miss.name, miss.candidates)
    if project is None:
        project = latest_project(store)
    if project is None:
        print("agent-memory: no project recorded yet; build first or pass --project",
              file=sys.stderr)
        return 2
    text = clean_message(args.text)
    if not text:
        print("agent-memory: note text is empty", file=sys.stderr)
        return 2
    note_id = f"n{store['nextNoteId']}"
    store["nextNoteId"] += 1
    store["notes"].append({"id": note_id, "project": project, "text": text, "created": now_ms()})
    prune(store)
    save_store(store)
    write_context(store)
    print(note_id)
    return 0


def cmd_forget(args):
    store = load_store()
    kept = [n for n in store["notes"] if n["id"] != args.id]
    if len(kept) == len(store["notes"]):
        print(f"agent-memory: no note {args.id}", file=sys.stderr)
        return 2
    store["notes"] = kept
    save_store(store)
    write_context(store)
    print(f"forgot {args.id}")
    return 0


def _match_signature(store, sig, project=None):
    """Every error whose signature starts with `sig`. A prefix shorter
    than four characters matches nothing: it cannot be unique."""
    if len(sig) < 4:
        return []
    matches = [e for e in store["errors"] if e["sig"].startswith(sig)]
    if project is not None:
        matches = [e for e in matches if e["project"] == project]
    return matches


def cmd_resolve(args):
    store = load_store()
    project = None
    if args.project:
        try:
            project = resolve_project(store, args.project)
        except ProjectNotFound as miss:
            return _project_error(miss.name, miss.candidates)
    matches = _match_signature(store, args.sig, project)
    if len(matches) != 1:
        print(f"agent-memory: signature {args.sig} matches {len(matches)} issues", file=sys.stderr)
        for entry in matches:
            print(f"  {entry['sig']} {entry['project']} count={entry['count']}", file=sys.stderr)
        return 2
    entry = matches[0]
    if entry["resolved"]:
        # Idempotent: nothing changed, so nothing is written and the answer
        # says which of the two states the issue was already in.
        print(f"already resolved {entry['sig']}")
        return 0
    entry["resolved"] = True
    save_store(store)
    write_context(store)
    print(f"resolved {entry['sig']}")
    return 0


def cmd_reopen(args):
    store = load_store()
    project = None
    if args.project:
        try:
            project = resolve_project(store, args.project)
        except ProjectNotFound as miss:
            return _project_error(miss.name, miss.candidates)
    matches = _match_signature(store, args.sig, project)
    if len(matches) != 1:
        print(f"agent-memory: signature {args.sig} matches {len(matches)} issues", file=sys.stderr)
        for entry in matches:
            print(f"  {entry['sig']} {entry['project']} count={entry['count']}", file=sys.stderr)
        return 2
    entry = matches[0]
    if not entry["resolved"]:
        print(f"already open {entry['sig']}")
        return 0
    entry["resolved"] = False
    save_store(store)
    write_context(store)
    print(f"reopened {entry['sig']}")
    return 0


def cmd_context(args):
    store = load_store()
    if args.project:
        try:
            project = resolve_project(store, args.project)
        except ProjectNotFound as miss:
            return _project_error(miss.name, miss.candidates)
        print(digest(store, project=project))
        return 0
    try:
        with open(CONTEXT_PATH, "r", encoding="utf-8") as handle:
            print(handle.read(), end="")
    except OSError:
        print(EMPTY_DIGEST)
    return 0


def cmd_stats(args):
    store = load_store()
    sessions = sum(e["sessions"] for e in store["projects"].values())
    turns = sum(e["turns"] for e in store["projects"].values())
    calls = sum(tool_calls(e) for e in store["projects"].values())
    failures = sum(e["failureCount"] for e in store["projects"].values())
    errors = len(store["errors"])
    issues = len(open_issues(store))
    if args.json:
        print(json.dumps({
            "projects": len(store["projects"]),
            "sessions": sessions,
            "turns": turns,
            "tool_calls": calls,
            "failures": failures,
            "errors": errors,
            "open_issues": issues,
            "notes": len(store["notes"]),
            "lastBuild": store["lastBuild"],
        }, indent=1))
        return 0
    print(f"projects={len(store['projects'])} sessions={sessions} turns={turns} "
          f"tool_calls={calls} failures={failures} errors={errors} "
          f"open_issues={issues} notes={len(store['notes'])}")
    return 0


def cmd_inject(args):
    if args.status and args.json:
        rows = [dict(t, enabled=inject_enabled(t["path"])) for t in injection_targets()]
        print(json.dumps(rows, indent=1))
        return 0
    target = target_for(args.harness)
    if target is None:
        print(f"agent-memory: no harness {args.harness!r} names an instructions file", file=sys.stderr)
        return 2
    path = target["path"]
    if args.enable:
        store = load_store()
        fold(store)
        import_sources(store)
        save_store(store)
        write_context(store)
        changed = inject_enable(store, path)
        print(f"injected {path}" if changed else f"already current in {path}")
        return 0
    if args.disable:
        changed = inject_disable(path)
        print(f"removed the agent-memory block from {path}" if changed
              else f"no agent-memory block in {path}")
        return 0
    print("enabled" if inject_enabled(path) else "disabled")
    return 0


def cmd_lessons(args):
    store = load_store()
    rows = sorted(store["lessons"], key=lambda l: (-l["hits"], -l["created"], l["id"]))
    if args.json:
        print(json.dumps({"lessons": rows, "candidates": candidates(store),
                          "imported": store["imported"], "sources": read_sources()}, indent=1))
        return 0
    if not rows:
        print("no lessons yet; promote a repeated failure with `memory promote <sig> \"rule\"`")
    for lesson in rows[:MAX_LIST_LINES]:
        where = lesson["project"] or "global"
        print(f"{lesson['id']} hits={lesson['hits']} {where} :: {lesson['text']}")
    return 0


def cmd_candidates(args):
    store = load_store()
    rows = candidates(store)
    if args.json:
        print(json.dumps(rows, indent=1))
        return 0
    for entry in rows[:MAX_LIST_LINES]:
        print(f"{entry['sig']} x{entry['count']} sessions={len(entry['sessions'])} "
              f"{entry['tool']} {entry.get('cmd') or ''} :: {entry['message']}")
    return 0


def cmd_promote(args):
    """Write a rule. A signature ties it to a failure so later hits count;
    an imported lesson id pins that lesson; neither makes a free rule."""
    store = load_store()
    text = clean_message(args.text or "")
    project = ""
    sig = ""
    source = ""
    why = args.why or ""
    target = args.target
    imported = next((e for e in store["imported"] if e["id"] == target), None)
    if imported is not None:
        text = text or imported["text"]
        why = why or imported["why"]
        source = imported["source"]
    elif target != "-":
        scope = None
        if args.project:
            try:
                scope = resolve_project(store, args.project)
            except ProjectNotFound as miss:
                return _project_error(miss.name, miss.candidates)
        matches = _match_signature(store, target, scope)
        if len(matches) != 1:
            print(f"agent-memory: {target!r} matches {len(matches)} signatures", file=sys.stderr)
            return 2
        sig = matches[0]["sig"]
        project = matches[0]["project"]
    if args.everywhere:
        project = ""
    if not text:
        print("agent-memory: a rule needs text", file=sys.stderr)
        return 2
    lesson = add_lesson(store, text, why, project, sig, source)
    prune(store)
    save_store(store)
    write_context(store)
    print(lesson["id"])
    return 0


def cmd_retire(args):
    store = load_store()
    kept = [l for l in store["lessons"] if l["id"] != args.id]
    if len(kept) == len(store["lessons"]):
        print(f"agent-memory: no lesson {args.id!r}", file=sys.stderr)
        return 2
    store["lessons"] = kept
    save_store(store)
    write_context(store)
    print(f"retired {args.id}")
    return 0


def _project_error(name, matches):
    print(f"agent-memory: no project {name!r} recorded", file=sys.stderr)
    for match in matches:
        print(f"  {match}", file=sys.stderr)
    return 2


def build_parser():
    parser = argparse.ArgumentParser(prog="memory", description=__doc__.split("\n")[0])
    verbs = parser.add_subparsers(dest="verb", required=True)

    verbs.add_parser("build", help="fold the event log into the store")

    projects = verbs.add_parser("projects", help="list every project on record")
    projects.add_argument("--json", action="store_true")

    errors = verbs.add_parser("errors", help="list failure signatures, open first")
    errors.add_argument("--project")
    errors.add_argument("--all", action="store_true", help="no line cap")
    errors.add_argument("--json", action="store_true")

    notes = verbs.add_parser("notes", help="list notes, newest first")
    notes.add_argument("--project")
    notes.add_argument("--json", action="store_true")

    note = verbs.add_parser("note", help="add a note")
    note.add_argument("text")
    note.add_argument("--project", help="defaults to the most recently active project")

    forget = verbs.add_parser("forget", help="remove a note by id")
    forget.add_argument("id")

    resolve = verbs.add_parser("resolve", help="mark a failure signature resolved")
    resolve.add_argument("sig")
    resolve.add_argument("--project")

    reopen = verbs.add_parser("reopen", help="mark a failure signature unresolved")
    reopen.add_argument("sig")
    reopen.add_argument("--project")

    context = verbs.add_parser("context", help="print the digest")
    context.add_argument("--project")

    stats = verbs.add_parser("stats", help="totals across every project")
    stats.add_argument("--json", action="store_true")

    lessons = verbs.add_parser("lessons", help="rules written from past failures")
    lessons.add_argument("--json", action="store_true",
                         help="lessons, candidates, imported lessons and sources")

    cands = verbs.add_parser("candidates", help="repeated failures with no rule yet")
    cands.add_argument("--json", action="store_true")

    promote = verbs.add_parser("promote", help="write a rule for a failure or pin an imported lesson")
    promote.add_argument("target", help="a failure signature, an imported lesson id, or - for a free rule")
    promote.add_argument("text", nargs="?", default="")
    promote.add_argument("--why", default="")
    promote.add_argument("--everywhere", action="store_true", help="not only in the failure's project")
    promote.add_argument("--project", help="pick the failure in this project when the signature repeats")

    retire = verbs.add_parser("retire", help="remove a lesson by id")
    retire.add_argument("id")

    inject = verbs.add_parser("inject", help="manage the marker block in a harness's rules file")
    group = inject.add_mutually_exclusive_group(required=True)
    group.add_argument("--enable", action="store_true")
    group.add_argument("--disable", action="store_true")
    group.add_argument("--status", action="store_true")
    inject.add_argument("--harness", default="claude", help="harness id from the registry")
    inject.add_argument("--json", action="store_true", help="with --status: every harness and its state")
    return parser


HANDLERS = {
    "build": cmd_build,
    "projects": cmd_projects,
    "errors": cmd_errors,
    "notes": cmd_notes,
    "note": cmd_note,
    "forget": cmd_forget,
    "resolve": cmd_resolve,
    "reopen": cmd_reopen,
    "context": cmd_context,
    "stats": cmd_stats,
    "inject": cmd_inject,
    "lessons": cmd_lessons,
    "candidates": cmd_candidates,
    "promote": cmd_promote,
    "retire": cmd_retire,
}


def main(argv):
    args = build_parser().parse_args(argv)
    return HANDLERS[args.verb](args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
