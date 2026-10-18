pragma Singleton
pragma ComponentBehavior: Bound

// The plugin's whole model: the memory store on disk, refreshed by running
// the same Python engine the CLI runs, and the shape of the lists the
// workspace plane draws.
//
// Deliberately the only file here that imports no qs.* module. The engine
// is a plain process and the store is a plain JSON file, so this can be
// instantiated offscreen under a throwaway state directory -- which is
// what tests/MemoryServiceProbe.qml does to prove the build path works
// without a desktop.
//
// Nothing here watches anything. No FileView, no Timer: the plane is the
// only consumer and it owns the watch, so a closed plane costs nothing.
// The fold runs a process, so this needs Quickshell.Io; everything else in
// here is plain JavaScript over plain JSON.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string stateHome: {
        const override = Quickshell.env("APHOTIC_STATE_HOME");
        if (override !== null && override.length > 0)
            return override;
        return `${Quickshell.env("HOME")}/.local/state/aphotic`;
    }

    // The engine is reached through the plugin's own command, not through a
    // path derived from this file. The shell links `modules/plugins/
    // agentMemory` at the plugin's qml/ directory, so `../python` resolves
    // to a directory that does not exist next to it; `aphotic memory` is the
    // one route that is right in a linked checkout and in an installed copy
    // alike, and it runs the very script the command does.
    readonly property string cliPrefix: "memory"

    readonly property string eventsPath: `${root.stateHome}/agent-events.jsonl`
    readonly property string storePath: `${root.stateHome}/agent-memory/store.json`
    readonly property string contextPath: `${root.stateHome}/agent-memory/context.md`

    // Parsed store.json, or null until the first successful read.
    property var store: null
    property string contextText: ""
    property string lastOutput: ""
    property bool busy: false
    property var injectTargets: []

    readonly property int projectCap: 100
    readonly property int issueCap: 200
    readonly property int noteCap: 300

    function build(): void {
        if (root.busy)
            return;
        root.busy = true;
        cliRunner.command = ["aphotic", root.cliPrefix, "build"];
        cliRunner.running = false;
        cliRunner.running = true;
    }

    // args is a plain array: ["note", "text", "--project", path], ["forget",
    // "n7"], ["resolve", "ab12cd34ef56"], ["inject", "--enable"]. Every
    // verb the CLI takes is reachable, because it is the CLI: one engine,
    // one set of rules.
    function act(action: string, args: var): void {
        if (root.busy)
            return;
        root.busy = true;
        cliRunner.command = ["aphotic", root.cliPrefix].concat([action], args ?? []);
        cliRunner.running = false;
        cliRunner.running = true;
    }

    // Which harnesses name a rules file, and which carry the block. Its own
    // runner, so asking never drops a build queued on the main one.
    function refreshTargets(): void {
        targetsRunner.running = false;
        targetsRunner.running = true;
    }

    function reload(): void {
        storeCat.running = false;
        storeCat.running = true;
        contextCat.running = false;
        contextCat.running = true;
    }

    function projectName(path: string): string {
        const clean = String(path ?? "");
        if (clean.length === 0 || clean === "(unattributed)")
            return "(unattributed)";
        const parts = clean.split("/").filter(part => part.length > 0);
        return parts.length > 0 ? parts[parts.length - 1] : clean;
    }

    function projects(): var {
        if (!root.store || !root.store.projects)
            return [];
        const rows = Object.keys(root.store.projects).map(path => {
            const entry = root.store.projects[path];
            const tools = entry.tools ?? ({});
            let calls = 0;
            for (const name of Object.keys(tools))
                calls += Number(tools[name].calls ?? 0);
            return {
                path: path,
                name: root.projectName(path),
                sessions: Number(entry.sessions ?? 0),
                turns: Number(entry.turns ?? 0),
                calls: calls,
                failures: Number(entry.failureCount ?? 0),
                errorCount: Number(entry.errorCount ?? 0),
                harnesses: Object.keys(entry.harnesses ?? ({})),
                lastSeen: Number(entry.lastSeen ?? 0)
            };
        });
        rows.sort((a, b) => (b.failures - a.failures) || (b.errorCount - a.errorCount) || (b.lastSeen - a.lastSeen));
        return rows.slice(0, root.projectCap);
    }

    function errorsFor(path: string): var {
        if (!root.store || !root.store.errors)
            return [];
        return root.store.errors
            .filter(entry => entry.project === path)
            .sort((a, b) => (Number(a.resolved) - Number(b.resolved)) || (Number(b.candidate ?? false) - Number(a.candidate ?? false))
                || (b.count - a.count) || (b.last - a.last))
            .slice(0, root.issueCap);
    }

    function notesFor(path: string): var {
        if (!root.store || !root.store.notes)
            return [];
        return root.store.notes
            .filter(note => note.project === path)
            .sort((a, b) => b.created - a.created)
            .slice(0, root.noteCap);
    }

    // A rule written for this project, or for every project.
    function lessonsFor(path: string): var {
        if (!root.store || !root.store.lessons)
            return [];
        return root.store.lessons
            .filter(lesson => lesson.project === "" || lesson.project === path)
            .sort((a, b) => (b.hits - a.hits) || (b.created - a.created));
    }

    // Imported lessons not yet pinned as rules.
    function importedLessons(): var {
        if (!root.store || !root.store.imported)
            return [];
        const pinned = new Set((root.store.lessons ?? []).map(lesson => `${lesson.source}|${lesson.text}`));
        return root.store.imported.filter(entry => !pinned.has(`${entry.source}|${entry.text}`));
    }

    function toolsFor(path: string): var {
        if (!root.store || !root.store.projects || !root.store.projects[path])
            return [];
        const tools = root.store.projects[path].tools ?? ({});
        const rows = Object.keys(tools).map(name => ({
            tool: name,
            calls: Number(tools[name].calls ?? 0),
            failures: Number(tools[name].failures ?? 0),
            totalMs: Number(tools[name].totalMs ?? 0)
        }));
        rows.sort((a, b) => b.calls - a.calls || b.failures - a.failures);
        return rows;
    }

    // Everything the engine printed on its last run, so the plane can show
    // "resolved <sig>" or the injection status without parsing a file.
    Process {
        id: cliRunner

        stdout: StdioCollector {
            onStreamFinished: {
                root.lastOutput = text.trim();
                root.busy = false;
                // Every verb either writes the store or answers from it, so
                // re-reading is always right and never a wasted read.
                root.reload();
                root.refreshTargets();
            }
        }
    }

    Process {
        id: targetsRunner

        command: ["aphotic", root.cliPrefix, "inject", "--status", "--json"]

        stdout: StdioCollector {
            onStreamFinished: {
                let rows = [];
                try {
                    rows = JSON.parse(text);
                } catch (error) {
                    rows = [];
                }
                root.injectTargets = Array.isArray(rows) ? rows : [];
            }
        }
    }

    Process {
        id: storeCat

        command: ["cat", root.storePath]

        stdout: StdioCollector {
            onStreamFinished: {
                let data = null;
                try {
                    data = JSON.parse(text);
                } catch (error) {
                    data = null;
                }
                root.store = (data && data.projects) ? data : null;
            }
        }
    }

    Process {
        id: contextCat

        command: ["cat", root.contextPath]

        stdout: StdioCollector {
            onStreamFinished: root.contextText = text
        }
    }
}
