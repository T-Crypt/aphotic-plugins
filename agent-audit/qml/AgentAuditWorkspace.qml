pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.modules.plugins.agentAudit

Item {
    id: root

    readonly property color applicationBackground: Colours.palette.m3surfaceContainer
    readonly property color cardBackground: Qt.alpha(Colours.layer(Colours.palette.m3surfaceContainerHigh, 2), 0.78)
    readonly property color insetBackground: Colours.layer(Colours.palette.m3surfaceContainer, 2)
    readonly property color panelBorder: Qt.alpha(Colours.palette.m3onSurface, 0.08)
    readonly property color textPrimary: Colours.palette.m3onSurface
    readonly property color textMuted: Colours.palette.m3onSurfaceVariant
    readonly property color success: Colours.palette.m3tertiaryOnSurface
    readonly property color error: Colours.palette.m3error
    readonly property color warning: Colours.palette.m3secondaryOnSurface
    readonly property color toolAccent: Colours.palette.m3primaryOnSurface
    readonly property color agentAccent: Colours.palette.m3secondaryOnSurface
    readonly property string uiFont: "Inter, Noto Sans, Sans-Serif"
    readonly property string monoFont: "JetBrains Mono, Fira Code, monospace"

    readonly property var evidence: AgentAuditService.selectedRunId.length > 0 ? AgentAuditService.replayedEvents : AgentAuditService.liveEvents
    readonly property int flaggedSteps: root.evidence.filter(event => root.eventFailed(event) || root.eventWarning(event)).length
    readonly property int totalTokens: root.evidence.reduce((sum, event) => sum + Number(event.tokens ?? event.tokenCount ?? event.usage?.total_tokens ?? 0), 0)
    readonly property int totalDurationMs: root.evidence.reduce((sum, event) => sum + Number(event.durationMs ?? 0), 0)

    property var selectedEvent: null
    property var tags: []
    property bool editingTag: false
    property string owner: `agent-audit-${Math.random()}`

    signal reportRequested(var report)

    onEvidenceChanged: {
        if (root.selectedEvent !== null && !root.evidence.includes(root.selectedEvent))
            root.selectedEvent = null;
    }

    function eventFailed(event: var): bool {
        return event?.event === "post_tool_use_failure" || String(event?.error ?? "").length > 0;
    }

    function eventWarning(event: var): bool {
        return String(event?.event ?? "").toLowerCase().includes("warning") || String(event?.level ?? "").toLowerCase() === "warning";
    }

    function eventColour(event: var): color {
        if (root.eventFailed(event))
            return root.error;
        if (root.eventWarning(event))
            return root.warning;
        if (event?.event === "post_tool_use")
            return root.success;
        if (event?.tool)
            return root.toolAccent;
        return root.agentAccent;
    }

    function stepKind(event: var): string {
        const name = String(event?.event ?? "").toLowerCase();
        if (name.includes("memory"))
            return qsTr("Memory access");
        if (event?.tool || name.includes("tool"))
            return qsTr("Tool call");
        if (name.includes("output") || name.includes("stop") || name.includes("complete"))
            return qsTr("Output");
        return qsTr("Thought");
    }

    function stepIcon(event: var): string {
        const kind = root.stepKind(event);
        if (kind === qsTr("Memory access"))
            return "memory";
        if (kind === qsTr("Tool call"))
            return "terminal";
        if (kind === qsTr("Output"))
            return "output";
        return "psychology";
    }

    function stepTitle(event: var): string {
        return event?.tool ?? event?.summary ?? event?.event ?? qsTr("Agent activity");
    }

    function payloadText(event: var): string {
        return event ? JSON.stringify(event, null, 2) : qsTr("Select an execution step to inspect its payload.");
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
            flaggedSteps: root.flaggedSteps,
            eventCount: root.evidence.length,
            tags: root.tags.slice()
        });
    }

    onVisibleChanged: AgentAuditService.setSurfaceVisible(root.owner, visible)
    Component.onCompleted: AgentAuditService.setSurfaceVisible(root.owner, visible)
    Component.onDestruction: AgentAuditService.setSurfaceVisible(root.owner, false)

    component StepDelegate: Rectangle {
        id: stepRow

        required property var eventData
        readonly property bool selected: root.selectedEvent === stepRow.eventData
        property bool hovered: false

        width: stepList.width
        height: 58
        radius: 8
        color: stepRow.selected ? Qt.alpha(root.toolAccent, 0.12) : stepRow.hovered ? Qt.alpha(root.textPrimary, 0.05) : "transparent"
        border.width: stepRow.selected ? 1 : 0
        border.color: root.toolAccent

        Behavior on color { ColorAnimation { duration: 120 } }

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: parent.height - 16
            radius: 999
            color: root.eventColour(stepRow.eventData)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 8
                color: Qt.alpha(root.eventColour(stepRow.eventData), 0.13)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.stepIcon(stepRow.eventData)
                    color: root.eventColour(stepRow.eventData)
                    font.pixelSize: 16
                    fill: 1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: root.stepTitle(stepRow.eventData)
                    color: root.textPrimary
                    elide: Text.ElideRight
                    font.family: root.uiFont
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }

                Text {
                    Layout.fillWidth: true
                    text: root.stepKind(stepRow.eventData)
                    color: root.textMuted
                    elide: Text.ElideRight
                    font.family: root.uiFont
                    font.pixelSize: 10
                }
            }

            Text {
                visible: !!stepRow.eventData.durationMs
                text: `${stepRow.eventData.durationMs ?? 0} ms`
                color: root.textMuted
                font.family: root.monoFont
                font.pixelSize: 10
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: stepRow.hovered = containsMouse
            onClicked: root.selectedEvent = stepRow.eventData
        }
    }

    component MetricCard: Rectangle {
        required property string label
        required property string value
        required property string icon
        required property color accent

        Layout.fillWidth: true
        implicitHeight: 66
        radius: 8
        color: root.insetBackground
        border.width: 1
        border.color: root.panelBorder

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 8
                color: Qt.alpha(parent.parent.accent, 0.13)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: parent.parent.parent.icon
                    color: parent.parent.parent.accent
                    font.pixelSize: 17
                    fill: 1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: parent.parent.parent.label.toUpperCase()
                    color: root.textMuted
                    font.family: root.uiFont
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.7
                }

                Text {
                    text: parent.parent.parent.value
                    color: root.textPrimary
                    font.family: root.monoFont
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: root.applicationBackground
        border.width: 1
        border.color: root.panelBorder
    }

    Rectangle {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        height: 72
        radius: 12
        color: root.cardBackground
        border.width: 1
        border.color: root.panelBorder

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 8
                color: Qt.alpha(root.toolAccent, 0.14)
                border.width: 1
                border.color: Qt.alpha(root.toolAccent, 0.42)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "fact_check"
                    color: root.toolAccent
                    font.pixelSize: 20
                    fill: 1
                }
            }

            ColumnLayout {
                spacing: 1

                Text {
                    text: qsTr("Agent Audit")
                    color: root.textPrimary
                    font.family: root.uiFont
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                Text {
                    text: AgentAuditService.selectedRunId.length > 0 ? AgentAuditService.selectedRunId : qsTr("Live execution stream")
                    color: root.textMuted
                    elide: Text.ElideMiddle
                    font.family: root.monoFont
                    font.pixelSize: 10
                    Layout.maximumWidth: 230
                }
            }

            Rectangle {
                implicitWidth: statusRow.implicitWidth + 18
                implicitHeight: 26
                radius: 999
                color: Qt.alpha(AgentAuditService.liveSessions.length > 0 ? root.success : root.textMuted, 0.12)
                border.width: 1
                border.color: Qt.alpha(AgentAuditService.liveSessions.length > 0 ? root.success : root.textMuted, 0.32)

                RowLayout {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 6

                    Rectangle {
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        radius: 999
                        color: AgentAuditService.liveSessions.length > 0 ? root.success : root.textMuted
                    }

                    Text {
                        text: AgentAuditService.liveSessions.length > 0 ? qsTr("RUNNING") : qsTr("IDLE")
                        color: AgentAuditService.liveSessions.length > 0 ? root.success : root.textMuted
                        font.family: root.uiFont
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.6
                    }
                }
            }

            ListView {
                id: headerTags

                Layout.fillWidth: true
                Layout.preferredHeight: 28
                orientation: ListView.Horizontal
                spacing: 6
                clip: true
                model: root.tags

                delegate: TagChip {
                    required property string modelData
                    label: modelData
                    accent: root.agentAccent
                    interactive: false
                }
            }

            TagChip {
                visible: !root.editingTag
                label: qsTr("+ Add tag")
                accent: root.toolAccent
                onClicked: {
                    root.editingTag = true;
                    tagInput.forceActiveFocus();
                }
            }

            TextField {
                id: tagInput

                visible: root.editingTag
                Layout.preferredWidth: 150
                Layout.preferredHeight: 28
                color: root.textPrimary
                placeholderText: qsTr("tag-name")
                placeholderTextColor: root.textMuted
                selectByMouse: true
                font.family: root.monoFont
                font.pixelSize: 11
                leftPadding: 10
                rightPadding: 10
                topPadding: 4
                bottomPadding: 4

                background: Rectangle {
                    radius: 999
                    color: root.insetBackground
                    border.width: 1
                    border.color: tagInput.activeFocus ? root.toolAccent : root.panelBorder
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

            Text {
                text: qsTr("%1 steps").arg(root.evidence.length)
                color: root.textMuted
                font.family: root.monoFont
                font.pixelSize: 11
            }
        }
    }

    SplitView {
        id: workbench

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: 12
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: 86
        orientation: Qt.Horizontal

        handle: Rectangle {
            implicitWidth: 12
            color: "transparent"

            Rectangle {
                anchors.centerIn: parent
                width: 1
                height: parent.height - 20
                color: root.panelBorder
            }
        }

        Rectangle {
            SplitView.preferredWidth: 270
            SplitView.minimumWidth: 220
            radius: 12
            color: root.cardBackground
            border.width: 1
            border.color: root.panelBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("RUN TREE")
                        color: root.textMuted
                        font.family: root.uiFont
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.8
                    }

                    Text {
                        text: AgentAuditService.selectedRunId.length > 0 ? qsTr("REPLAY") : qsTr("LIVE")
                        color: root.toolAccent
                        font.family: root.monoFont
                        font.pixelSize: 9
                    }
                }

                ListView {
                    id: stepList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: root.evidence

                    delegate: StepDelegate {
                        eventData: modelData
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.evidence.length === 0
                    text: qsTr("Execution steps appear here when a tracked session produces evidence.")
                    color: root.textMuted
                    wrapMode: Text.Wrap
                    font.family: root.uiFont
                    font.pixelSize: 11
                    lineHeight: 1.35
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: AgentAuditService.selectedRunId.length > 0
                    implicitHeight: 42
                    radius: 8
                    color: root.insetBackground
                    border.width: 1
                    border.color: root.panelBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        MaterialIcon {
                            text: AgentAuditService.replaying ? "pause" : "play_arrow"
                            color: root.toolAccent
                            font.pixelSize: 17

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -5
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

                        Text {
                            text: `${AgentAuditService.replayIndex}/${AgentAuditService.replayEvents.length}`
                            color: root.textMuted
                            font.family: root.monoFont
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }

        Rectangle {
            SplitView.fillWidth: true
            SplitView.minimumWidth: 380
            radius: 12
            color: root.cardBackground
            border.width: 1
            border.color: root.panelBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: qsTr("Payload inspector")
                            color: root.textPrimary
                            font.family: root.uiFont
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: root.selectedEvent ? root.stepKind(root.selectedEvent) : qsTr("No step selected")
                            color: root.textMuted
                            font.family: root.uiFont
                            font.pixelSize: 10
                        }
                    }

                    TagChip {
                        visible: root.selectedEvent !== null
                        label: root.selectedEvent ? root.stepKind(root.selectedEvent) : ""
                        accent: root.selectedEvent ? root.eventColour(root.selectedEvent) : root.toolAccent
                        interactive: false
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: root.insetBackground
                    border.width: 1
                    border.color: root.selectedEvent ? Qt.alpha(root.eventColour(root.selectedEvent), 0.42) : root.panelBorder

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 16
                        clip: true

                        TextArea {
                            text: root.payloadText(root.selectedEvent)
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.NoWrap
                            color: root.selectedEvent ? root.textPrimary : root.textMuted
                            selectionColor: Qt.alpha(root.toolAccent, 0.35)
                            selectedTextColor: root.textPrimary
                            font.family: root.monoFont
                            font.pixelSize: 12
                            padding: 0
                            background: null
                        }
                    }
                }
            }
        }

        Rectangle {
            id: auditPanel

            SplitView.preferredWidth: 300
            SplitView.minimumWidth: 260
            radius: 12
            color: root.cardBackground
            border.width: 1
            border.color: root.panelBorder

            Flickable {
                anchors.fill: parent
                anchors.margins: 12
                clip: true
                contentHeight: auditColumn.implicitHeight

                ColumnLayout {
                    id: auditColumn
                    width: parent.width
                    spacing: 10

                    Text {
                        text: qsTr("AUDIT CONTROLS")
                        color: root.textMuted
                        font.family: root.uiFont
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.8
                    }

                    MetricCard {
                        label: qsTr("Tokens")
                        value: root.totalTokens > 0 ? root.totalTokens.toLocaleString() : qsTr("n/a")
                        icon: "data_usage"
                        accent: root.toolAccent
                    }

                    MetricCard {
                        label: qsTr("Execution time")
                        value: root.totalDurationMs > 0 ? `${(root.totalDurationMs / 1000).toFixed(2)} s` : qsTr("n/a")
                        icon: "timer"
                        accent: root.agentAccent
                    }

                    MetricCard {
                        label: qsTr("Flagged steps")
                        value: String(root.flaggedSteps)
                        icon: "flag"
                        accent: root.flaggedSteps > 0 ? root.warning : root.success
                    }

                    Text {
                        Layout.topMargin: 6
                        text: qsTr("TAGS")
                        color: root.textMuted
                        font.family: root.uiFont
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.8
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: root.tags

                            delegate: TagChip {
                                required property string modelData
                                required property int index
                                label: modelData
                                accent: root.agentAccent
                                removable: true
                                onRemoved: root.removeTag(index)
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.tags.length === 0
                        text: qsTr("Add session-local tags from the header. They are not persisted.")
                        color: root.textMuted
                        wrapMode: Text.Wrap
                        font.family: root.uiFont
                        font.pixelSize: 10
                        lineHeight: 1.3
                    }
                }
            }
        }
    }

    Rectangle {
        id: reportBar

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 16
        width: 300
        height: 58
        radius: 12
        color: root.cardBackground
        border.width: 1
        border.color: root.panelBorder

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: qsTr("AUDIT REPORT")
                    color: root.textMuted
                    font.family: root.uiFont
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.6
                }

                Text {
                    text: qsTr("%1 flagged steps").arg(root.flaggedSteps)
                    color: root.flaggedSteps > 0 ? root.warning : root.success
                    font.family: root.monoFont
                    font.pixelSize: 11
                }
            }

            Rectangle {
                id: reportButton

                property bool hovered: false

                Layout.preferredWidth: 126
                Layout.fillHeight: true
                radius: 8
                scale: reportButton.hovered ? 1.02 : 1
                border.width: 1
                border.color: Qt.alpha(root.toolAccent, 0.62)
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.alpha(root.toolAccent, 0.30) }
                    GradientStop { position: 1; color: Qt.alpha(Qt.tint(root.toolAccent, root.success), 0.18) }
                }

                Behavior on scale { NumberAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Generate Report")
                    color: root.textPrimary
                    font.family: root.uiFont
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: reportButton.hovered = containsMouse
                    onClicked: root.requestReport()
                }
            }
        }
    }
}
