# Agent Memory

Every session your coding agent runs already leaves a trail: which tool it
called, which failed, what broke. That trail lives in one file, rotates
every thousand lines, and is gone. This plugin folds it into a memory that
stays.

A workstation on the workspace plane (`SUPER + SHIFT + W`), an
`aphotic memory` command, and a digest you can inject into `~/.claude/CLAUDE.md`
so the next session starts knowing what broke last time.

- **It reads what the hooks already write.** No extra hook, no second log,
  no daemon. The one evidence file the hooks plugins already produce
  (`~/.local/state/aphotic/agent-events.jsonl`) is the only input, and the
  fold is a whole-file scan of a file that is capped at 1000 lines.
- **Failures become issues, not noise.** A message is normalised before it
  is counted: paths, numbers and hex runs collapse, so `jq` failing on
  `/tmp/x:12` and on `/tmp/y:47` are one issue with a count of two, not two
  one-off lines. One build after the file rotated still counts them,
  because the counts live in the store, not in a cursor over the file.
- **Resolve and reopen.** An issue you have fixed is closed and leaves the
  digest; the same tool failing again reopens it. Nothing is deleted
  silently, and the note you wrote stays yours.
- **Deterministic, so a repeat is free.** No model, no network, no
  summarising. The same file and store always produce the same digest.
  `build` twice on an unchanged file changes nothing, and the digest is
  the same text you would write by hand.

## What it collects

The same tool-call metadata the hooks plugins already write: a tool name, a
duration, a harness name, a working directory, an error kind and an error
message, plus the notes you add yourself. It never reads a prompt, a
response, a transcript or a file diff, and nothing leaves the machine.

## The store

`~/.local/state/aphotic/agent-memory/`:

- `store.json` — every project on record with its session, turn and tool
  counts; every failure signature with an occurrence count; your notes.
- `context.md` — the digest, rewritten on each build.

Both are plain files. `remove` takes the plugin and leaves the data, which
`[owns]` declares so the uninstaller says so out loud. Bounds: 50 issues
per project, 400 in total, 300 notes, 200 projects, 5000 remembered event
keys.

## Install

```sh
aphotic plugin install agent-memory
```

It needs the `ai` layer for the workspace plane and harness events on
record; the command works without the plane.

## Commands

```sh
aphotic memory build                # fold the event log into the store
aphotic memory projects             # every project on record
aphotic memory errors [--project P] # failure signatures, open first
aphotic memory notes [--project P]  # notes, newest first
aphotic memory note "text"          # add a note
aphotic memory forget n7            # remove one
aphotic memory resolve ab12         # close a failure signature
aphotic memory reopen ab12          # open it again
aphotic memory context [--project P]  # the digest
aphotic memory stats                # totals
aphotic memory inject --status       # enabled or disabled
```

## Injecting into Claude Code

```sh
aphotic memory inject --enable
```

This writes the digest into `~/.claude/CLAUDE.md` between two HTML comment
markers and touches nothing else in the file. Running it twice leaves the
file byte-identical, and `--disable` takes the markers and the block with
them. Claude Code reads the file at session start, so the digest is the
first thing the next session sees.

The same digest is available to any other harness through
`aphotic memory context`.

## Idle cost

Nothing runs while the plane is closed: no daemon, no `tail`, no timer.
Opening the plane runs one `python3` fold; each action runs one more; and a
new line in the event log triggers at most one rebuild every 1.5 seconds
while the plane is open. A fold of the whole capped log takes a
millisecond.

## Tests

```sh
python3 -m pytest agent-memory/tests/test_memory_core.py -q
bash agent-memory/tests/test_memory_cli.sh
bash agent-memory/tests/test_manifest.sh
bash agent-memory/tests/test_memory_service.sh
```

## License

GPL-3.0. See [LICENSE](../LICENSE).
