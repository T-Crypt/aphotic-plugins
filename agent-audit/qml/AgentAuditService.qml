pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services.ai

Singleton {
    id: root

    readonly property string stateDir: `${Quickshell.env("HOME")}/.local/state/aphotic`
    readonly property string eventLogPath: `${root.stateDir}/agent-events.jsonl`
    readonly property var liveSessions: AgentEvents.liveSessions
    readonly property var replayedEvents: root.replayEvents.slice(0, root.replayIndex)
    readonly property bool replayFinished: root.replayIndex >= root.replayEvents.length

    property var liveEvents: []
    property var runs: []
    property string selectedRunId: ""
    property var replayEvents: []
    property int replayIndex: 0
    property bool replaying: false
    property var _visibleOwners: ({})

    function refreshRuns(): void {
        runLister.running = false;
        runLister.running = true;
    }

    function loadRun(id: string): void {
        if (!id)
            return;
        root.selectedRunId = id;
        root.replayEvents = [];
        root.replayIndex = 0;
        root.replaying = false;
        runReader.command = ["cat", `${root.stateDir}/agent-runs/${id}.jsonl`];
        runReader.running = false;
        runReader.running = true;
    }

    function toggleReplay(): void {
        if (root.replayEvents.length === 0)
            return;
        if (root.replayFinished)
            root.replayIndex = 0;
        root.replaying = !root.replaying;
    }

    function _appendLive(event: var): void {
        const next = root.liveEvents.concat([event]);
        root.liveEvents = next.slice(Math.max(0, next.length - 400));
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
        if (anyVisible)
            root.refreshRuns();
        else
            root.replaying = false;
    }

    Connections {
        target: AgentEvents

        function onRecord(event): void {
            root._appendLive(event);
        }

        function onTailingChanged(): void {
            if (!AgentEvents.tailing)
                root.liveEvents = [];
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

    Process {
        id: runLister
        command: ["sh", "-c", `find '${root.stateDir}/agent-runs' -maxdepth 1 -type f -name '*.jsonl' -printf '%f\\n' 2>/dev/null | sort -r | head -n 25`]

        stdout: StdioCollector {
            onStreamFinished: {
                root.runs = text.split("\n").filter(name => name.length > 0).map(name => ({
                    id: name.replace(/\.jsonl$/, ""),
                    label: name.replace(/\.jsonl$/, "")
                }));
            }
        }
    }

    Process {
        id: runReader

        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = [];
                for (const line of text.split("\n")) {
                    try {
                        const event = JSON.parse(line);
                        if (event?.event)
                            parsed.push(event);
                    } catch (e) {}
                }
                root.replayEvents = parsed;
            }
        }
    }
}
