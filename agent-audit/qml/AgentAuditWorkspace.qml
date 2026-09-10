pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services
import qs.modules.plugins.agentAudit

// The audit workstation: pick a run on the left, read one step in the
// middle, read the run's shape on the right.
//
// Agent Graph draws the session as a node canvas and answers "what is
// happening". This answers "what happened, step by step", which is why
// it is a list and a field table rather than a second canvas.
//
// Everything drawn here comes from the event schema the harness hooks
// actually write: a tool name, a duration, a harness, a model, and the
// subagent attribution. There are no payloads in that schema -- no tool
// input, no output, no diff -- so nothing here pretends to show one.
Item {
    id: root

    // --- Colour ---------------------------------------------------------
    //
    // Two kinds of colour, and they follow the theme differently.
    //
    // Decorative accents are palette roles, so they move with the
    // wallpaper exactly as everything else in the shell does.
    //
    // Status is not decorative. Pass, warn and fail have to stay apart
    // from each other under every theme, and the generated palette
    // cannot promise that: wallust derives its ramp from the wallpaper,
    // so `color1` is only "red" by ANSI convention and on a real desktop
    // resolves to whatever the picture had. Measured on this install it
    // is a muted purple, which made a failed step and a passing one the
    // same colour. So status takes its saturation and lightness from the
    // live palette, which is what makes it sit in the theme, and fixes
    // only the hue, which is what keeps it readable.
    readonly property color statusReference: Colours.palette.m3primaryOnSurface
    readonly property color statusPass: root.statusHue(145)
    readonly property color statusWarn: root.statusHue(42)
    readonly property color statusFail: root.statusHue(8)

    readonly property color accentTool: Colours.palette.m3primaryOnSurface
    readonly property color accentAgent: Colours.palette.m3tertiaryOnSurface
    readonly property color accentPrompt: Colours.palette.m3secondaryOnSurface

    readonly property color panelColour: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
    readonly property color insetColour: Colours.palette.m3surfaceContainer
    readonly property color hairline: Qt.alpha(Colours.palette.m3onSurface, 0.09)
    readonly property color textPrimary: Colours.palette.m3onSurface
    readonly property color textMuted: Colours.palette.m3onSurfaceVariant

    readonly property font sectionFont: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(0.8).build()

    function statusHue(degrees: real): color {
        const ref = root.statusReference;
        return Qt.hsla(degrees / 360, Math.max(0.38, ref.hslSaturation), Math.min(0.72, Math.max(0.48, ref.hslLightness)), 1);
    }

    // --- Evidence -------------------------------------------------------

    readonly property bool replaying: AgentAuditService.selectedRunId.length > 0
    readonly property var evidence: root.replaying ? AgentAuditService.replayedEvents : AgentAuditService.liveEvents

    readonly property int toolCalls: root.evidence.filter(e => e.event === "pre_tool_use").length
    readonly property int failures: root.evidence.filter(e => root.eventFailed(e)).length
    readonly property int toolMs: root.evidence.reduce((sum, e) => sum + Number(e.durationMs ?? 0), 0)

    readonly property int spanMs: {
        const list = root.evidence;
        if (list.length < 2)
            return 0;
        return Math.max(0, Number(list[list.length - 1].t ?? 0) - Number(list[0].t ?? 0));
    }

    readonly property int subagents: {
        const seen = ({});
        for (let i = 0; i < root.evidence.length; i++) {
            const id = root.evidence[i].spawnedAgentId;
            if (id)
                seen[id] = true;
        }
        return Object.keys(seen).length;
    }

    // Which tools this run leaned on, busiest first. The one view here
    // that reads the run as a whole rather than one step at a time.
    readonly property var toolTally: {
        const counts = ({});
        for (let i = 0; i < root.evidence.length; i++) {
            const name = root.evidence[i].tool;
            if (!name || root.evidence[i].event !== "pre_tool_use")
                continue;
            counts[name] = (counts[name] ?? 0) + 1;
        }
        const rows = Object.keys(counts).map(name => ({
            name: name,
            count: counts[name]
        }));
        rows.sort((a, b) => b.count - a.count);
        return rows.slice(0, 6);
    }

    readonly property int busiestTool: root.toolTally.length > 0 ? root.toolTally[0].count : 0

    property var selectedEvent: null
    property var tags: []
    property bool editingTag: false
    property string owner: `agent-audit-${Math.random()}`

    signal reportRequested(var report)

    onEvidenceChanged: {
        if (root.selectedEvent !== null && !root.evidence.includes(root.selectedEvent))
            root.selectedEvent = null;
    }

    // --- Classification -------------------------------------------------
    //
    // Keyed on the event names the hooks really emit. An earlier pass
    // guessed at names by substring and advertised a "Memory access"
    // kind no harness has ever written.

    function eventFailed(event: var): bool {
        return event?.event === "post_tool_use_failure";
    }

    function eventKind(event: var): string {
        switch (event?.event) {
        case "pre_tool_use":
        case "post_tool_use":
            return event?.spawnedAgentId ? qsTr("Subagent") : qsTr("Tool call");
        case "post_tool_use_failure":
            return qsTr("Failure");
        case "user_prompt_submit":
            return qsTr("Prompt");
        case "notification":
            return qsTr("Notification");
        case "stop":
            return qsTr("Turn end");
        case "session_start":
            return qsTr("Session start");
        case "session_end":
            return qsTr("Session end");
        default:
            return qsTr("Event");
        }
    }

    function eventIcon(event: var): string {
        switch (event?.event) {
        case "pre_tool_use":
            return event?.spawnedAgentId ? "account_tree" : "play_arrow";
        case "post_tool_use":
            return event?.spawnedAgentId ? "account_tree" : "check";
        case "post_tool_use_failure":
            return "error";
        case "user_prompt_submit":
            return "chat";
        case "notification":
            return "notifications";
        case "stop":
            return "stop_circle";
        case "session_start":
            return "login";
        case "session_end":
            return "logout";
        default:
            return "circle";
        }
    }

    function eventColour(event: var): color {
        switch (event?.event) {
        case "post_tool_use_failure":
            return root.statusFail;
        case "post_tool_use":
            return root.statusPass;
        case "pre_tool_use":
            return event?.spawnedAgentId ? root.accentAgent : root.accentTool;
        case "user_prompt_submit":
            return root.accentPrompt;
        case "notification":
            return root.statusWarn;
        default:
            return root.textMuted;
        }
    }

    function eventTitle(event: var): string {
        if (event?.tool)
            return String(event.tool);
        return root.eventKind(event);
    }

    // The other half of a tool call. `pre_tool_use` carries the arguments
    // context and `post_tool_use` carries the timing and the model, so a
    // step selected from either side can show both.
    function partnerOf(event: var): var {
        const id = event?.toolId;
        if (!id)
            return null;
        const wantPost = event.event === "pre_tool_use";
        for (let i = 0; i < root.evidence.length; i++) {
            const other = root.evidence[i];
            if (other === event || other.toolId !== id)
                continue;
            const isPost = other.event === "post_tool_use" || other.event === "post_tool_use_failure";
            if (wantPost === isPost)
                return other;
        }
        return null;
    }

    function clockOf(event: var): string {
        const ms = Number(event?.t ?? 0);
        if (!(ms > 0))
            return String(event?.timestamp ?? "");
        return new Date(ms).toLocaleTimeString(Qt.locale(), "HH:mm:ss");
    }

    function msLabel(ms: var): string {
        const value = Number(ms ?? 0);
        if (!(value > 0))
            return "";
        if (value < 1000)
            return `${Math.round(value)} ms`;
        if (value < 60000)
            return `${(value / 1000).toFixed(2)} s`;
        return `${Math.floor(value / 60000)}m ${Math.round((value % 60000) / 1000)}s`;
    }

    function agoLabel(ms: var): string {
        const delta = Date.now() - Number(ms ?? 0);
        if (!(delta > 0))
            return qsTr("now");
        const minutes = Math.floor(delta / 60000);
        if (minutes < 1)
            return qsTr("just now");
        if (minutes < 60)
            return qsTr("%1m ago").arg(minutes);
        const hours = Math.floor(minutes / 60);
        if (hours < 24)
            return qsTr("%1h ago").arg(hours);
        return qsTr("%1d ago").arg(Math.floor(hours / 24));
    }

    // Every field the schema carries, in the order a reader wants them.
    // Empty values drop out rather than drawing a row of dashes.
    function detailFields(event: var): var {
        if (!event)
            return [];
        const rows = [];
        const partner = root.partnerOf(event);
        function push(label, value, mono) {
            if (value === undefined || value === null || String(value).length === 0)
                return;
            rows.push({
                label: label,
                value: String(value),
                mono: mono === true
            });
        }
        push(qsTr("Time"), root.clockOf(event), true);
        push(qsTr("Duration"), root.msLabel(event.durationMs ?? partner?.durationMs), true);
        push(qsTr("Tool"), event.tool, true);
        push(qsTr("Status"), event.status);
        push(qsTr("Harness"), event.harness ?? partner?.harness);
        push(qsTr("Model"), event.model ?? partner?.model, true);
        push(qsTr("Agent type"), event.agentType ?? partner?.agentType);
        push(qsTr("Agent id"), event.agentId ?? partner?.agentId, true);
        push(qsTr("Spawned agent"), event.spawnedAgentId, true);
        push(qsTr("Spawned model"), event.agentModel, true);
        push(qsTr("Task"), event.agentDescription);
        push(qsTr("Notification"), event.notificationType);
        push(qsTr("Started by"), event.source);
        push(qsTr("Directory"), event.cwd, true);
        push(qsTr("Session"), event.sessionId, true);
        push(qsTr("Tool id"), event.toolId, true);
        return rows;
    }

    function addTag(value: string): void {
        const tag = value.trim();
        if (!tag || root.tags.includes(tag))
            return;
        root.tags = root.tags.concat([tag]);
    }

    function removeTag(index: int): void {
        const next = root.tags.slice();
        next.splice(index, 1);
        root.tags = next;
    }

    function requestReport(): void {
        root.reportRequested({
            runId: AgentAuditService.selectedRunId,
            steps: root.evidence.length,
            toolCalls: root.toolCalls,
            failures: root.failures,
            subagents: root.subagents,
            toolMs: root.toolMs,
            spanMs: root.spanMs,
            tags: root.tags.slice()
        });
    }

    onVisibleChanged: AgentAuditService.setSurfaceVisible(root.owner, visible)
    Component.onCompleted: AgentAuditService.setSurfaceVisible(root.owner, visible)
    Component.onDestruction: AgentAuditService.setSurfaceVisible(root.owner, false)

    // --- Shared pieces --------------------------------------------------

    component SectionLabel: StyledText {
        color: root.textMuted
        font: root.sectionFont
    }

    component Divider: StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: root.hairline
    }

    component RunDelegate: StyledRect {
        id: runRow

        required property var runData
        required property bool current

        width: ListView.view.width
        implicitHeight: 40
        radius: Tokens.rounding.small
        color: runRow.current ? Qt.alpha(root.accentTool, 0.14) : "transparent"
        border.width: runRow.current ? 1 : 0
        border.color: Qt.alpha(root.accentTool, 0.42)

        StateLayer {
            color: root.accentTool
            onClicked: AgentAuditService.loadRun(runRow.runData.id)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.small
            anchors.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "history"
                color: runRow.current ? root.accentTool : root.textMuted
                fontStyle: Tokens.font.icon.small
                fill: runRow.current ? 1 : 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: runRow.runData.project.length > 0 ? runRow.runData.project : runRow.runData.id.slice(0, 8)
                    color: root.textPrimary
                    elide: Text.ElideRight
                    font: Tokens.font.label.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: `${root.agoLabel(runRow.runData.modified)} · ${runRow.runData.lines}`
                    color: root.textMuted
                    elide: Text.ElideRight
                    font: Tokens.font.label.small
                }
            }
        }
    }

    component StepDelegate: StyledRect {
        id: stepRow

        required property var eventData

        readonly property bool selected: root.selectedEvent === stepRow.eventData
        readonly property color tone: root.eventColour(stepRow.eventData)

        width: ListView.view.width
        implicitHeight: 52
        radius: Tokens.rounding.small
        color: stepRow.selected ? Qt.alpha(stepRow.tone, 0.14) : "transparent"
        border.width: stepRow.selected ? 1 : 0
        border.color: Qt.alpha(stepRow.tone, 0.5)

        StateLayer {
            color: stepRow.tone
            onClicked: root.selectedEvent = stepRow.eventData
        }

        StyledRect {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: parent.height - 14
            radius: Tokens.rounding.full
            color: stepRow.tone
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            StyledRect {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: Tokens.rounding.small
                color: Qt.alpha(stepRow.tone, 0.15)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.eventIcon(stepRow.eventData)
                    color: stepRow.tone
                    fontStyle: Tokens.font.icon.small
                    fill: 1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.eventTitle(stepRow.eventData)
                    color: root.textPrimary
                    elide: Text.ElideRight
                    font: Tokens.font.label.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.eventKind(stepRow.eventData)
                    color: root.textMuted
                    elide: Text.ElideRight
                    font: Tokens.font.label.small
                }
            }

            StyledText {
                visible: text.length > 0
                text: root.msLabel(stepRow.eventData.durationMs)
                color: root.textMuted
                font: Tokens.font.mono.small
            }
        }
    }

    component MetricCard: StyledRect {
        id: metric

        required property string label
        required property string value
        required property string icon
        required property color accent

        Layout.fillWidth: true
        implicitHeight: 58
        radius: Tokens.rounding.small
        color: root.insetColour
        border.width: 1
        border.color: root.hairline

        RowLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            StyledRect {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: Tokens.rounding.small
                color: Qt.alpha(metric.accent, 0.15)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: metric.icon
                    color: metric.accent
                    fontStyle: Tokens.font.icon.small
                    fill: 1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                SectionLabel {
                    text: metric.label.toUpperCase()
                }

                StyledText {
                    text: metric.value
                    color: root.textPrimary
                    font: Tokens.font.mono.medium
                }
            }
        }
    }

    // --- Chrome ---------------------------------------------------------

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer
        border.width: 1
        border.color: root.hairline
    }

    StyledRect {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        height: 64
        radius: Tokens.rounding.medium
        color: root.panelColour
        border.width: 1
        border.color: root.hairline

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium

            StyledRect {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: Tokens.rounding.small
                color: Colours.palette.m3primary

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "fact_check"
                    color: Colours.contrastOn(Colours.palette.m3primary)
                    fontStyle: Tokens.font.icon.medium
                    fill: 1
                }
            }

            ColumnLayout {
                spacing: 0

                StyledText {
                    text: qsTr("Agent Audit")
                    color: root.textPrimary
                    font: Tokens.font.title.small
                }

                StyledText {
                    Layout.maximumWidth: 260
                    text: root.replaying ? qsTr("Replaying %1").arg(AgentAuditService.selectedRunId.slice(0, 8)) : qsTr("Live session stream")
                    color: root.textMuted
                    elide: Text.ElideRight
                    font: Tokens.font.mono.small
                }
            }

            TagChip {
                readonly property bool live: AgentAuditService.liveSessions.length > 0

                label: root.replaying ? qsTr("REPLAY") : live ? qsTr("RUNNING") : qsTr("IDLE")
                icon: root.replaying ? "history" : live ? "bolt" : "pause"
                accent: root.replaying ? root.accentAgent : live ? root.statusPass : root.textMuted
                interactive: false
                filled: true
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 26
                    orientation: ListView.Horizontal
                    spacing: Tokens.spacing.extraSmall
                    clip: true
                    model: root.tags

                    delegate: TagChip {
                        required property string modelData

                        label: modelData
                        accent: root.accentAgent
                        interactive: false
                    }
                }
            }

            TagChip {
                visible: !root.editingTag
                label: qsTr("Add tag")
                icon: "add"
                accent: root.accentTool
                onClicked: {
                    root.editingTag = true;
                    tagInput.forceActiveFocus();
                }
            }

            TextField {
                id: tagInput

                visible: root.editingTag
                Layout.preferredWidth: 150
                Layout.preferredHeight: 26
                color: root.textPrimary
                placeholderText: qsTr("tag-name")
                placeholderTextColor: root.textMuted
                selectByMouse: true
                font: Tokens.font.mono.small
                leftPadding: Tokens.padding.medium
                rightPadding: Tokens.padding.medium
                topPadding: 0
                bottomPadding: 0

                background: StyledRect {
                    radius: Tokens.rounding.full
                    color: root.insetColour
                    border.width: 1
                    border.color: tagInput.activeFocus ? root.accentTool : root.hairline
                }

                onAccepted: {
                    root.addTag(text);
                    text = "";
                    root.editingTag = false;
                }

                Keys.onEscapePressed: {
                    text = "";
                    root.editingTag = false;
                }
            }
        }
    }

    SplitView {
        id: workbench

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Tokens.spacing.medium
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        anchors.bottomMargin: Tokens.padding.large
        orientation: Qt.Horizontal

        handle: Item {
            implicitWidth: Tokens.spacing.medium

            StyledRect {
                anchors.centerIn: parent
                width: 1
                height: parent.height - Tokens.spacing.large
                color: root.hairline
            }
        }

        // --- Left: runs, then steps -------------------------------------

        StyledRect {
            SplitView.preferredWidth: 288
            SplitView.minimumWidth: 240
            radius: Tokens.rounding.medium
            color: root.panelColour
            border.width: 1
            border.color: root.hairline
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                SectionLabel {
                    text: qsTr("SOURCE")
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Tokens.rounding.small
                    color: root.replaying ? "transparent" : Qt.alpha(root.statusPass, 0.14)
                    border.width: root.replaying ? 0 : 1
                    border.color: Qt.alpha(root.statusPass, 0.42)

                    StateLayer {
                        color: root.statusPass
                        onClicked: AgentAuditService.clearRun()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.small
                        anchors.rightMargin: Tokens.padding.small
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: "bolt"
                            color: root.replaying ? root.textMuted : root.statusPass
                            fontStyle: Tokens.font.icon.small
                            fill: root.replaying ? 0 : 1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("Live session")
                            color: root.replaying ? root.textMuted : root.textPrimary
                            font: Tokens.font.label.medium
                        }

                        StyledText {
                            text: String(AgentAuditService.liveEvents.length)
                            color: root.textMuted
                            font: Tokens.font.mono.small
                        }
                    }
                }

                ListView {
                    id: runList

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 132)
                    clip: true
                    spacing: 2
                    model: AgentAuditService.runs

                    delegate: RunDelegate {
                        required property var modelData

                        runData: modelData
                        current: AgentAuditService.selectedRunId === modelData.id
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: AgentAuditService.runs.length === 0
                    text: qsTr("No archived runs under ~/.local/state/aphotic/agent-runs.")
                    color: root.textMuted
                    wrapMode: Text.Wrap
                    font: Tokens.font.label.small
                }

                Divider {}

                RowLayout {
                    Layout.fillWidth: true

                    SectionLabel {
                        Layout.fillWidth: true
                        text: qsTr("STEPS")
                    }

                    StyledText {
                        text: String(root.evidence.length)
                        color: root.textMuted
                        font: Tokens.font.mono.small
                    }
                }

                ListView {
                    id: stepList

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: root.evidence

                    delegate: StepDelegate {
                        required property var modelData

                        eventData: modelData
                    }

                    ScrollBar.vertical: ScrollBar {}
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.evidence.length === 0
                    text: AgentAuditService.seeded ? qsTr("No events in this source yet.") : qsTr("Reading the event log.")
                    color: root.textMuted
                    wrapMode: Text.Wrap
                    font: Tokens.font.label.small
                }

                // Only a replayed run has a position to scrub. The live
                // stream has no end to seek to.
                StyledRect {
                    Layout.fillWidth: true
                    visible: root.replaying
                    implicitHeight: 38
                    radius: Tokens.rounding.small
                    color: root.insetColour
                    border.width: 1
                    border.color: root.hairline

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.small
                        anchors.rightMargin: Tokens.padding.small
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: AgentAuditService.replaying ? "pause" : "play_arrow"
                            color: root.accentTool
                            fontStyle: Tokens.font.icon.small
                            fill: 1

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: AgentAuditService.toggleReplay()
                            }
                        }

                        Slider {
                            Layout.fillWidth: true
                            from: 0
                            to: Math.max(1, AgentAuditService.replayEvents.length)
                            value: AgentAuditService.replayIndex
                            onMoved: {
                                AgentAuditService.replaying = false;
                                AgentAuditService.replayIndex = Math.round(value);
                            }
                        }

                        StyledText {
                            text: `${AgentAuditService.replayIndex}/${AgentAuditService.replayEvents.length}`
                            color: root.textMuted
                            font: Tokens.font.mono.small
                        }
                    }
                }
            }
        }

        // --- Centre: one step, every field it carries -------------------

        StyledRect {
            SplitView.fillWidth: true
            SplitView.minimumWidth: 360
            radius: Tokens.rounding.medium
            color: root.panelColour
            border.width: 1
            border.color: root.hairline
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledRect {
                        visible: root.selectedEvent !== null
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: Tokens.rounding.small
                        color: Qt.alpha(root.selectedEvent ? root.eventColour(root.selectedEvent) : root.accentTool, 0.15)

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: root.selectedEvent ? root.eventIcon(root.selectedEvent) : "search"
                            color: root.selectedEvent ? root.eventColour(root.selectedEvent) : root.accentTool
                            fontStyle: Tokens.font.icon.medium
                            fill: 1
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.selectedEvent ? root.eventTitle(root.selectedEvent) : qsTr("Step inspector")
                            color: root.textPrimary
                            elide: Text.ElideRight
                            font: Tokens.font.title.small
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.selectedEvent ? root.eventKind(root.selectedEvent) : qsTr("Pick a step on the left")
                            color: root.textMuted
                            elide: Text.ElideRight
                            font: Tokens.font.label.small
                        }
                    }

                    TagChip {
                        visible: root.selectedEvent !== null
                        label: root.selectedEvent ? String(root.selectedEvent.status ?? "") : ""
                        accent: root.selectedEvent ? root.eventColour(root.selectedEvent) : root.accentTool
                        interactive: false
                    }
                }

                Divider {}

                // What the schema actually carries for this step. The
                // hooks record no tool input and no tool output, so there
                // is no payload pane here pretending otherwise.
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: detailColumn.implicitHeight
                    visible: root.selectedEvent !== null

                    ScrollBar.vertical: ScrollBar {}

                    ColumnLayout {
                        id: detailColumn

                        width: parent.width
                        spacing: Tokens.spacing.small

                        Repeater {
                            model: root.detailFields(root.selectedEvent)

                            delegate: RowLayout {
                                required property var modelData

                                Layout.fillWidth: true
                                spacing: Tokens.spacing.medium

                                StyledText {
                                    Layout.preferredWidth: 118
                                    text: modelData.label
                                    color: root.textMuted
                                    font: Tokens.font.label.small
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.value
                                    color: root.textPrimary
                                    wrapMode: Text.WrapAnywhere
                                    font: modelData.mono ? Tokens.font.mono.small : Tokens.font.body.small
                                }
                            }
                        }

                        SectionLabel {
                            Layout.topMargin: Tokens.spacing.small
                            text: qsTr("RAW EVENT")
                        }

                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: rawText.implicitHeight + Tokens.padding.large * 2
                            radius: Tokens.rounding.small
                            color: root.insetColour
                            border.width: 1
                            border.color: root.hairline

                            TextEdit {
                                id: rawText

                                anchors.fill: parent
                                anchors.margins: Tokens.padding.large
                                text: root.selectedEvent ? JSON.stringify(root.selectedEvent, null, 2) : ""
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                color: root.textPrimary
                                selectionColor: Qt.alpha(root.accentTool, 0.35)
                                selectedTextColor: root.textPrimary
                                font: Tokens.font.mono.small
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.selectedEvent === null

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - Tokens.padding.extraLarge * 2, 320)
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            text: "frame_inspect"
                            color: Qt.alpha(root.textMuted, 0.5)
                            fontStyle: Tokens.font.icon.extraLarge
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: qsTr("Select a step to read every field the harness recorded for it.")
                            color: root.textMuted
                            wrapMode: Text.Wrap
                            font: Tokens.font.body.small
                        }
                    }
                }
            }
        }

        // --- Right: the run's shape, and the report ---------------------

        StyledRect {
            SplitView.preferredWidth: 296
            SplitView.minimumWidth: 250
            radius: Tokens.rounding.medium
            color: root.panelColour
            border.width: 1
            border.color: root.hairline
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: auditColumn.implicitHeight

                    ScrollBar.vertical: ScrollBar {}

                    ColumnLayout {
                        id: auditColumn

                        width: parent.width
                        spacing: Tokens.spacing.small

                        SectionLabel {
                            text: qsTr("THIS RUN")
                        }

                        MetricCard {
                            label: qsTr("Steps")
                            value: String(root.evidence.length)
                            icon: "list"
                            accent: root.accentTool
                        }

                        MetricCard {
                            label: qsTr("Tool calls")
                            value: String(root.toolCalls)
                            icon: "terminal"
                            accent: root.accentTool
                        }

                        MetricCard {
                            label: qsTr("Failures")
                            value: String(root.failures)
                            icon: "error"
                            accent: root.failures > 0 ? root.statusFail : root.statusPass
                        }

                        MetricCard {
                            label: qsTr("Subagents")
                            value: String(root.subagents)
                            icon: "account_tree"
                            accent: root.accentAgent
                        }

                        MetricCard {
                            label: qsTr("Time in tools")
                            value: root.toolMs > 0 ? root.msLabel(root.toolMs) : qsTr("none recorded")
                            icon: "timer"
                            accent: root.accentAgent
                        }

                        MetricCard {
                            label: qsTr("Elapsed")
                            value: root.spanMs > 0 ? root.msLabel(root.spanMs) : qsTr("n/a")
                            icon: "schedule"
                            accent: root.accentPrompt
                        }

                        SectionLabel {
                            Layout.topMargin: Tokens.spacing.small
                            visible: root.toolTally.length > 0
                            text: qsTr("BUSIEST TOOLS")
                        }

                        Repeater {
                            model: root.toolTally

                            delegate: ColumnLayout {
                                required property var modelData

                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        color: root.textPrimary
                                        elide: Text.ElideRight
                                        font: Tokens.font.mono.small
                                    }

                                    StyledText {
                                        text: String(modelData.count)
                                        color: root.textMuted
                                        font: Tokens.font.mono.small
                                    }
                                }

                                StyledRect {
                                    Layout.fillWidth: true
                                    implicitHeight: 4
                                    radius: Tokens.rounding.full
                                    color: Qt.alpha(root.accentTool, 0.16)

                                    StyledRect {
                                        width: parent.width * (root.busiestTool > 0 ? modelData.count / root.busiestTool : 0)
                                        height: parent.height
                                        radius: parent.radius
                                        color: root.accentTool
                                    }
                                }
                            }
                        }

                        SectionLabel {
                            Layout.topMargin: Tokens.spacing.small
                            text: qsTr("TAGS")
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.extraSmall

                            Repeater {
                                model: root.tags

                                delegate: TagChip {
                                    required property string modelData
                                    required property int index

                                    label: modelData
                                    accent: root.accentAgent
                                    removable: true
                                    onRemoved: root.removeTag(index)
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.tags.length === 0
                            text: qsTr("Tags are added from the header and last as long as this window.")
                            color: root.textMuted
                            wrapMode: Text.Wrap
                            font: Tokens.font.label.small
                        }
                    }
                }

                Divider {}

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        SectionLabel {
                            text: qsTr("AUDIT REPORT")
                        }

                        StyledText {
                            text: qsTr("%1 flagged").arg(root.failures)
                            color: root.failures > 0 ? root.statusFail : root.statusPass
                            font: Tokens.font.mono.small
                        }
                    }

                    StyledRect {
                        Layout.preferredWidth: 124
                        Layout.preferredHeight: 34
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3primary

                        StateLayer {
                            color: Colours.contrastOn(Colours.palette.m3primary)
                            onClicked: root.requestReport()
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: Tokens.spacing.extraSmall

                            MaterialIcon {
                                text: "summarize"
                                color: Colours.contrastOn(Colours.palette.m3primary)
                                fontStyle: Tokens.font.icon.small
                                fill: 1
                            }

                            StyledText {
                                text: qsTr("Generate")
                                color: Colours.contrastOn(Colours.palette.m3primary)
                                font: Tokens.font.label.medium
                            }
                        }
                    }
                }
            }
        }
    }
}
