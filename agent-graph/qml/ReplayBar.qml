// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.agentGraph

ColumnLayout {
    id: root

    required property GraphReplay replay
    property string runId: ""

    signal exited

    spacing: Tokens.spacing.small

    Component.onCompleted: AgentGraphService.refreshRuns()

    readonly property var lanes: {
        const events = root.replay.events;
        const stamps = root.replay.stamps;
        const open = ({});
        const rows = ({});
        const order = [];

        for (let i = 0; i < events.length; i++) {
            const e = events[i];
            if (!e.toolId)
                continue;
            const lane = `${e.sessionId}|${e.agentId ?? ""}`;
            if (!rows[lane]) {
                rows[lane] = [];
                order.push(lane);
            }
            if (e.event === "pre_tool_use") {
                open[e.toolId] = { lane: lane, tool: e.tool ?? "", start: stamps[i] ?? 0, index: i, status: "running" };
                rows[lane].push(open[e.toolId]);
            } else if (open[e.toolId]) {
                open[e.toolId].end = stamps[i] ?? 0;
                open[e.toolId].status = e.event === "post_tool_use_failure" ? "errored" : "completed";
            }
        }

        return order.map(lane => ({
            key: lane,
            agent: lane.split("|")[1],
            blocks: rows[lane].map(b => ({
                tool: b.tool,
                index: b.index,
                status: b.status,
                start: b.start,
                end: b.end ?? (root.replay.durationMs || b.start + 1)
            }))
        }));
    }

    function _time(ms: real): string {
        const total = Math.max(0, Math.round(ms / 1000));
        return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
    }

    function _span(ms: real): string {
        const total = Math.max(0, Math.round(ms / 1000));
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        const seconds = total % 60;
        if (hours > 0)
            return `${hours}h ${minutes}m ${seconds}s`;
        return minutes > 0 ? `${minutes}m ${seconds}s` : `${seconds}s`;
    }

    function _summaryMarkdown(): string {
        const events = root.replay.events;
        if (events.length === 0)
            return "";

        const origin = events[0].t ?? 0;
        // Not AgentGraphService.replaySpan: that is a separate binding on the same
        // event list and still reads its previous value while the list is settling,
        // so a summary taken right after a run loads would report a 0s span.
        const span = (events[events.length - 1].t ?? origin) - origin;
        const sessions = AgentGraphService.foldEvents(events, events.length);

        const open = ({});
        const tools = ({});
        const toolOrder = [];
        const branches = ({});
        const branchOrder = [];
        const errors = [];
        let calls = 0;

        for (let i = 0; i < events.length; i++) {
            const e = events[i];
            if (!e.toolId)
                continue;
            if (e.event === "pre_tool_use") {
                const tool = e.tool || qsTr("(unknown)");
                if (!tools[tool]) {
                    tools[tool] = { calls: 0, errored: 0 };
                    toolOrder.push(tool);
                }
                tools[tool].calls++;
                calls++;
                open[e.toolId] = { tool: tool, at: (e.t ?? origin) - origin };

                const branch = e.agentType ?? "";
                if (branch) {
                    if (branches[branch] === undefined) {
                        branches[branch] = 0;
                        branchOrder.push(branch);
                    }
                    branches[branch]++;
                }
            } else if (open[e.toolId]) {
                if (e.event === "post_tool_use_failure") {
                    tools[open[e.toolId].tool].errored++;
                    errors.push(open[e.toolId]);
                }
                delete open[e.toolId];
            }
        }

        const unfinished = Object.keys(open).length;
        const models = sessions.map(s => s.modelInfo.raw ? (s.modelInfo.locality ? `${s.modelInfo.raw} (${s.modelInfo.locality})` : s.modelInfo.raw) : "").filter((m, i, all) => m && all.indexOf(m) === i);
        const statuses = sessions.map(s => s.status).filter((s, i, all) => all.indexOf(s) === i);

        toolOrder.sort((a, b) => tools[b].calls - tools[a].calls || a.localeCompare(b));
        branchOrder.sort((a, b) => branches[b] - branches[a] || a.localeCompare(b));

        const lines = [];
        lines.push(`# Agent run \`${root.runId}\``);
        lines.push("");
        lines.push(`- **Model** — ${models.length > 0 ? models.join(", ") : qsTr("unreported")}`);
        lines.push(`- **Wall clock** — ${root._span(span)}`);
        lines.push(`- **Started** — ${events[0].timestamp ?? qsTr("unknown")}`);
        lines.push(`- **Tool calls** — ${calls} across ${toolOrder.length} ${toolOrder.length === 1 ? qsTr("tool") : qsTr("tools")}`);
        lines.push(`- **Errored** — ${errors.length}`);
        if (unfinished > 0)
            lines.push(`- **Still open at end** — ${unfinished}`);
        lines.push(`- **Subagent branches** — ${branchOrder.length}`);
        lines.push(`- **Status at end** — ${statuses.join(", ")}`);
        lines.push("");

        lines.push(`## ${qsTr("Tool calls")}`);
        lines.push("");
        if (toolOrder.length === 0) {
            lines.push(`_${qsTr("No tool calls recorded.")}_`);
        } else {
            lines.push(`| ${qsTr("Tool")} | ${qsTr("Calls")} | ${qsTr("Errored")} |`);
            lines.push("| --- | ---: | ---: |");
            for (const tool of toolOrder)
                lines.push(`| ${tool} | ${tools[tool].calls} | ${tools[tool].errored} |`);
        }
        lines.push("");

        lines.push(`## ${qsTr("Errored calls")}`);
        lines.push("");
        if (errors.length === 0) {
            lines.push(`_${qsTr("None.")}_`);
        } else {
            for (const failure of errors)
                lines.push(`- \`+${root._time(failure.at)}\` ${failure.tool}`);
        }
        lines.push("");

        lines.push(`## ${qsTr("Subagent branches")}`);
        lines.push("");
        if (branchOrder.length === 0) {
            lines.push(`_${qsTr("No subagent calls in this run.")}_`);
        } else {
            for (const branch of branchOrder)
                lines.push(`- **${branch}** — ${branches[branch]} ${branches[branch] === 1 ? qsTr("call") : qsTr("calls")}`);
        }
        lines.push("");

        lines.push("---");
        lines.push(`_${qsTr("Generated by Aphotic Agent Graph.")}_`);
        lines.push("");

        return lines.join("\n");
    }

    function exportRun(): void {
        if (!root.runId)
            return;
        const home = Quickshell.env("HOME");
        exporter.command = ["cp", `${home}/.local/state/aphotic/agent-runs/${root.runId}.jsonl`, `${home}/agent-run-${root.runId}.jsonl`];
        exporter.running = true;
    }

    function exportSummary(): void {
        if (!root.runId || !root.replay.loaded)
            return;
        const markdown = root._summaryMarkdown();
        if (!markdown)
            return;
        const home = Quickshell.env("HOME");
        summaryExporter.markdown = markdown;
        summaryExporter.stdinEnabled = true;
        summaryExporter.command = ["sh", "-c", 'cat > "$1"', "sh", `${home}/agent-run-${root.runId}-summary.md`];
        summaryExporter.running = true;
    }

    Process {
        id: exporter
        onExited: code => Toaster.toast(code === 0 ? qsTr("Run exported") : qsTr("Export failed"), code === 0 ? `~/agent-run-${root.runId}.jsonl` : qsTr("Could not copy the run archive"), code === 0 ? "download_done" : "error")
    }

    Process {
        id: summaryExporter

        property string markdown: ""

        stdinEnabled: true
        onStarted: {
            summaryExporter.write(summaryExporter.markdown);
            // Quickshell exposes no explicit stdin close -- clearing stdinEnabled
            // is what sends EOF, and the `cat` on the other end never exits without it.
            summaryExporter.stdinEnabled = false;
        }
        onExited: code => Toaster.toast(code === 0 ? qsTr("Summary exported") : qsTr("Export failed"), code === 0 ? `~/agent-run-${root.runId}-summary.md` : qsTr("Could not write the run summary"), code === 0 ? "download_done" : "error")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            text: "history"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.small
        }

        StyledText {
            text: qsTr("Runs")
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            contentWidth: runRow.implicitWidth
            flickableDirection: Flickable.HorizontalFlick
            clip: true

            Row {
                id: runRow
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    model: AgentGraphService.runs

                    StyledRect {
                        id: chip

                        required property var modelData
                        readonly property bool active: chip.modelData.id === root.runId

                        implicitWidth: chipLabel.implicitWidth + Tokens.padding.medium
                        implicitHeight: 24
                        radius: Tokens.rounding.full
                        color: chip.active ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.9)
                        border.width: 1
                        border.color: chip.active ? "transparent" : Colours.palette.m3outlineVariant

                        StyledText {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: chip.modelData.id.slice(0, 8)
                            font: Tokens.font.label.small
                            color: chip.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            onClicked: {
                                root.runId = chip.modelData.id;
                                AgentGraphService.loadRun(chip.modelData.id);
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            visible: AgentGraphService.runs.length === 0
            text: qsTr("No recorded runs yet")
            font: Tokens.font.label.small
            color: Colours.palette.m3outlineVariant
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        component TransportButton: StyledRect {
            required property string glyph
            property bool accented: false
            signal activated

            implicitWidth: 28
            implicitHeight: 28
            radius: Tokens.rounding.full
            color: accented ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.9)
            border.width: 1
            border.color: accented ? "transparent" : Colours.palette.m3outlineVariant

            MaterialIcon {
                anchors.centerIn: parent
                text: parent.glyph
                color: parent.accented ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                onClicked: parent.activated()
            }
        }

        TransportButton {
            glyph: "replay"
            onActivated: root.replay.seekTo(0)
        }

        TransportButton {
            glyph: "skip_previous"
            onActivated: root.replay.step(-1)
        }

        TransportButton {
            glyph: root.replay.playing ? "pause" : "play_arrow"
            accented: true
            onActivated: root.replay.toggle()
        }

        TransportButton {
            glyph: "skip_next"
            onActivated: root.replay.step(1)
        }

        StyledRect {
            implicitWidth: speedLabel.implicitWidth + Tokens.padding.medium
            implicitHeight: 26
            radius: Tokens.rounding.full
            color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.9)
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            StyledText {
                id: speedLabel
                anchors.centerIn: parent
                text: `${root.replay.speed}x`
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                onClicked: root.replay.speed = root.replay.speed >= 8 ? 1 : root.replay.speed * 2
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: `${root._time(root.replay.positionMs)} / ${root._time(root.replay.durationMs)} · ${root.replay.cursor}/${root.replay.events.length}`
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }

        TransportButton {
            glyph: "download"
            onActivated: root.exportRun()
        }

        TransportButton {
            glyph: "summarize"
            onActivated: root.exportSummary()
        }

        TransportButton {
            glyph: "close"
            onActivated: root.exited()
        }
    }

    StyledRect {
        id: scrubber

        Layout.fillWidth: true
        implicitHeight: 6
        radius: Tokens.rounding.full
        color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

        StyledRect {
            width: parent.width * root.replay.progress
            height: parent.height
            radius: parent.radius
            color: Colours.palette.m3primary
        }

        TapHandler {
            onTapped: point => root.replay.seekTo(point.position.x / scrubber.width * root.replay.durationMs)
        }

        DragHandler {
            target: null
            yAxis.enabled: false
            onCentroidChanged: if (active) root.replay.seekTo(centroid.position.x / scrubber.width * root.replay.durationMs)
        }
    }

    Column {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall
        spacing: 3

        Repeater {
            model: root.lanes

            Item {
                id: lane

                required property var modelData

                width: parent.width
                height: 14

                StyledText {
                    id: laneLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: 66
                    text: lane.modelData.agent ? qsTr("subagent") : qsTr("main")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3outlineVariant
                    elide: Text.ElideRight
                }

                Item {
                    anchors.left: laneLabel.right
                    anchors.leftMargin: Tokens.spacing.extraSmall
                    anchors.right: parent.right
                    height: parent.height

                    Repeater {
                        model: lane.modelData.blocks

                        StyledRect {
                            id: block

                            required property var modelData
                            readonly property real span: Math.max(1, root.replay.durationMs)

                            x: parent.width * (block.modelData.start / block.span)
                            width: Math.max(3, parent.width * ((block.modelData.end - block.modelData.start) / block.span))
                            height: 10
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Tokens.rounding.extraSmall
                            color: block.modelData.status === "errored"
                                ? Colours.palette.m3error
                                : block.modelData.index < root.replay.cursor
                                    ? Colours.palette.m3primary
                                    : Qt.alpha(Colours.palette.m3outlineVariant, 0.7)

                            StateLayer {
                                anchors.fill: parent
                                radius: parent.radius
                                onClicked: root.replay.seekToIndex(block.modelData.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
