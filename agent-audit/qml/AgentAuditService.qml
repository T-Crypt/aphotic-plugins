pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services.ai

// The evidence Agent Audit reads, and nothing about how it is drawn.
//
// Two sources, and the difference between them is the whole design.
// `liveEvents` is the session happening now; `replayedEvents` is one
// archived run under a scrubber. A run is selected or it is not, and
// `evidence` in the workspace picks between them on that alone.
//
// The seed is the part worth explaining. AgentEvents tails the log with
// `tail -n 400 -F` and replays that backlog to whoever is holding it at
// the time -- so a surface that takes its hold later sees only what
// arrives after it asked, and every event already on disk is gone. The
// pet and the notch tile both hold the tail from shell start, so this
// plugin is never the first holder on a real desktop and opening it
// showed an empty run tree over a log with a thousand events in it.
// Reading the same backlog here removes the race rather than trying to
// win it, and `_key` drops the overlap where the two sources meet.
Singleton {
    id: root

    readonly property string stateDir: `${Quickshell.env("HOME")}/.local/state/aphotic`
    readonly property string eventLogPath: `${root.stateDir}/agent-events.jsonl`
    readonly property string runsDir: `${root.stateDir}/agent-runs`
    readonly property var liveSessions: AgentEvents.liveSessions

    // How many events either source keeps. Matches AgentEvents' own
    // backlog, so the seed and the stream cover the same window.
    readonly property int historyLimit: 400

    readonly property var liveEvents: {
        const seen = ({});
        const merged = [];
        const all = root._seeded.concat(root._streamed);
        for (let i = 0; i < all.length; i++) {
            const key = root._key(all[i]);
            if (seen[key])
                continue;
            seen[key] = true;
            merged.push(all[i]);
        }
        return merged.slice(Math.max(0, merged.length - root.historyLimit));
    }

    readonly property var replayedEvents: root.replayEvents.slice(0, root.replayIndex)
    readonly property bool replayFinished: root.replayIndex >= root.replayEvents.length
    readonly property bool seeded: root._seedDone

    property var runs: []
    property string selectedRunId: ""
    property var replayEvents: []
    property int replayIndex: 0
    property bool replaying: false

    property var _seeded: []
    property var _streamed: []
    property bool _seedDone: false
    property var _visibleOwners: ({})

    // Identity for one event across the two sources. A hook writes one
    // line per (session, moment, kind), and `toolId` separates the pre
    // and post halves of the same tool call landing in the same
    // millisecond.
    function _key(event: var): string {
        return `${event?.sessionId ?? ""}|${event?.t ?? ""}|${event?.event ?? ""}|${event?.toolId ?? ""}`;
    }

    function _parseLines(text: string): var {
        const parsed = [];
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].length === 0)
                continue;
            try {
                const event = JSON.parse(lines[i]);
                if (event?.event && event?.sessionId)
                    parsed.push(event);
            } catch (e) {}
        }
        return parsed;
    }

    function refreshRuns(): void {
        runLister.running = false;
        runLister.running = true;
    }

    function reseed(): void {
        seeder.running = false;
        seeder.running = true;
    }

    function loadRun(id: string): void {
        if (!id) {
            root.clearRun();
            return;
        }
        if (id.includes("/") || id.includes("..")) {
            return;
        }
        root.selectedRunId = id;
        root.replayEvents = [];
        root.replayIndex = 0;
        root.replaying = false;
        runReader.command = ["cat", `${root.runsDir}/${id}.jsonl`];
        runReader.running = false;
        runReader.running = true;
    }

    // Back to the live stream. The replay state is dropped rather than
    // parked, because coming back to a run re-reads it anyway and a run
    // still being written to has more in it than it did.
    function clearRun(): void {
        root.selectedRunId = "";
        root.replayEvents = [];
        root.replayIndex = 0;
        root.replaying = false;
    }

    function toggleReplay(): void {
        if (root.replayEvents.length === 0)
            return;
        if (root.replayFinished)
            root.replayIndex = 0;
        root.replaying = !root.replaying;
    }

    function showAllReplay(): void {
        root.replaying = false;
        root.replayIndex = root.replayEvents.length;
    }

    function setSurfaceVisible(owner: string, visible: bool): void {
        if (!owner)
            return;
        const next = Object.assign({}, root._visibleOwners);
        if (visible)
            next[owner] = true;
        else
            delete next[owner];
        root._visibleOwners = next;
        const anyVisible = Object.keys(next).length > 0;
        AgentEvents.hold("agent-audit", anyVisible);
        if (anyVisible) {
            root.refreshRuns();
            root.reseed();
        } else {
            root.replaying = false;
        }
    }

    Connections {
        target: AgentEvents

        function onRecord(event): void {
            const next = root._streamed.concat([event]);
            root._streamed = next.slice(Math.max(0, next.length - root.historyLimit));
        }
    }

    Timer {
        interval: 80
        repeat: true
        running: root.replaying
        onTriggered: {
            root.replayIndex = Math.min(root.replayIndex + 1, root.replayEvents.length);
            if (root.replayFinished)
                root.replaying = false;
        }
    }

    // The same backlog AgentEvents would have replayed, read directly so
    // this plugin does not depend on being the first to ask for it.
    Process {
        id: seeder
        command: ["sh", "-c", `tail -n ${root.historyLimit} '${root.eventLogPath}' 2>/dev/null || true`]

        stdout: StdioCollector {
            onStreamFinished: {
                root._seeded = root._parseLines(text);
                root._seedDone = true;
            }
        }
    }

    // Newest run first, by modification time. Sorting the filenames was
    // sorting UUIDs, which is an arbitrary order that put this morning's
    // run below one from last week. The first line of each file comes
    // back with it, because it carries the working directory and the
    // harness and reading it here costs one pass rather than 25 opens
    // from QML.
    Process {
        id: runLister
        command: ["sh", "-c", `d='${root.runsDir}'; [ -d "$d" ] || exit 0; for f in "$d"/*.jsonl; do [ -f "$f" ] || continue; printf '%s\\t%s\\t%s\\t%s\\n' "$(basename "$f" .jsonl)" "$(stat -c %Y "$f" 2>/dev/null || echo 0)" "$(wc -l < "$f" | tr -d ' ')" "$(head -n 1 "$f")"; done | sort -k2,2nr | head -n 40`]

        stdout: StdioCollector {
            onStreamFinished: {
                const rows = [];
                const lines = text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    if (lines[i].length === 0)
                        continue;
                    const parts = lines[i].split("\t");
                    if (parts.length < 3)
                        continue;
                    let first = null;
                    try {
                        first = JSON.parse(parts[3] ?? "");
                    } catch (e) {}
                    const cwd = String(first?.cwd ?? "");
                    rows.push({
                        id: parts[0],
                        modified: Number(parts[1]) * 1000,
                        lines: Number(parts[2]),
                        cwd: cwd,
                        project: cwd.length > 0 ? cwd.split("/").filter(p => p.length > 0).pop() ?? cwd : "",
                        harness: String(first?.harness ?? "")
                    });
                }
                root.runs = rows;
            }
        }
    }

    Process {
        id: runReader

        stdout: StdioCollector {
            onStreamFinished: {
                root.replayEvents = root._parseLines(text);
                root.replayIndex = root.replayEvents.length;
            }
        }
    }
}
