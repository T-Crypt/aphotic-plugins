# Skill Manager

One library of agent skills, deployed to Claude Code, Codex, OpenCode, Cursor
and every other agent on this machine. Backed by the
[`skills-manager-cli`](https://github.com/xingkongliang/skills-manager) so
the upstream desktop app and this shell share the same database.

![screen](screenshot.png)

## What you get

A workspace surface for the full library and a docked section under AI in
Settings. The workspace lists every skill, lets you search, filter by tag
or source, and deploy to any combination of agents. The right pane shows
the skill's `SKILL.md`, its tags, and per-agent deploy chips. Settings
shows the binary the wrapper resolved, the library location, every agent
the CLI knows about, the presets, and an **Adopt** button for whatever
your agents already have on disk.

A keyboard shortcut (`SUPER + SHIFT + K`) and a command palette action
(`Skills: open the skill manager`) both open the workspace.

## Install

```
aphotic plugin install skills
```

The first time it runs, the plugin downloads `skills-manager-cli` from
upstream's GitHub releases. The download is gated on an interactive
prompt and verified against a pinned sha256; non-interactive callers
(scripts, the installer) get the URL and steps instead, the same rule
`codex-hooks` follows.

## Usage

Terminal:

```
aphotic skills                    # every skill, with agent counts and tags
aphotic skills show <name>        # one skill, with its SKILL.md
aphotic skills deploy <name> <agent>...
aphotic skills undeploy <name> <agent>...
aphotic skills tag add <name> <tag>
aphotic skills presets deploy <name>
aphotic skills presets undeploy <name>
aphotic skills set list
aphotic skills set on <name> [--agent A]
aphotic skills set off <name> [--agent A]
aphotic skills set new <name> [--description D]
aphotic skills set add <name> <skill>...
aphotic skills set remove <name> <skill>...
aphotic skills adopt              # import what the agents already have
aphotic skills doctor             # binary, version, library and counts
aphotic skills path --set DIR     # move the library
```

Adopt discovers skill directories from `skills/data/known-dirs.txt`, every
installed agent's `skills_dir` reported by the CLI, and an optional drop-in
file at `${XDG_CONFIG_HOME:-~/.config}/aphotic/skills/dirs.txt` (same
format: one path per line, `~` allowed, `#` comments). Only existing
directories are scanned, duplicates are removed by realpath, and
`adopt --dry-run` previews the import without writing.

From the shell: `SUPER + SHIFT + K`, or the command palette action
"Skills: open the skill manager".

## Sets

A set is a named group of skills you turn on for a session, such as a UI
set or a Code set. Turning one on leaves the others as they are. The Sets
strip above the skill list lights a set once every skill in it is deployed,
and a click turns it on or off. Each skill row has an Add to set menu.

## Where the library lives

`~/.skills-manager/`, the CLI's default and the same directory the
upstream desktop app reads. Pointing this plugin at a private copy would
give the app and Aphotic two libraries that drift. Change it with
`aphotic skills path --set DIR`; never with a shell setting.

## Verify

```
tools/build_index.py --check      # index.json matches every plugin.toml
skills/tests/test_contract.sh     # manifest agreement, manifest components exist
skills/tests/test_install_deps.sh # sha256 pin, non-interactive safe
skills/tests/test_skills_service.sh     # QML service against the stub CLI
skills/tests/test_skills_surfaces.sh    # surfaces instantiate offscreen
```
