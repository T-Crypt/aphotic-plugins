pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services
import qs.modules.plugins.agentAudit

Item {
    id: root

    readonly property var evidence: AgentAuditService.selectedRunId.length > 0 ? AgentAuditService.replayedEvents : AgentAuditService.liveEvents
    readonly property var selectedFields: root.evidenceFields(root.selectedEvent)
    property var selectedEvent: null
    property string owner: `agent-audit-${Math.random()}`

    function eventFailed(event: var): bool {
        return event?.event === "post_tool_use_failure" || event?.error?.length > 0;
    }

    function eventColour(event: var): color {
        if (root.eventFailed(event))
            return Colours.palette.m3error;
        if (event?.event === "post_tool_use")
            return Colours.palette.m3tertiaryOnSurface;
        return Colours.palette.m3primaryOnSurface;
    }

    function eventIcon(event: var): string {
        if (root.eventFailed(event))
            return "error";
        if (event?.event === "post_tool_use")
            return "check_circle";
        if (event?.event === "pre_tool_use")
            return "build";
        return "timeline";
    }

    function eventLabel(event: var): string {
        if (root.eventFailed(event))
            return qsTr("Tool issue");
        if (event?.event === "post_tool_use")
            return qsTr("Tool complete");
        if (event?.event === "pre_tool_use")
            return qsTr("Tool started");
        return event?.event ?? qsTr("Activity");
    }

    function evidenceFields(event: var): var {
        if (!event)
            return [];
        const fields = [
            { label: qsTr("Activity"), value: root.eventLabel(event) },
            { label: qsTr("Tool"), value: event.tool ?? qsTr("No tool recorded") },
            { label: qsTr("Agent"), value: event.agentType ?? event.agent_type ?? qsTr("Primary session") },
            { label: qsTr("Outcome"), value: root.eventFailed(event) ? qsTr("Needs attention") : qsTr("Recorded") }
        ];
        if (event.durationMs)
            fields.push({ label: qsTr("Duration"), value: qsTr("%1 ms").arg(event.durationMs) });
        if (event.sessionId || event.session_id)
            fields.push({ label: qsTr("Session"), value: event.sessionId ?? event.session_id });
        if (event.timestamp || event.time)
            fields.push({ label: qsTr("Time"), value: event.timestamp ?? event.time });
        const detail = event.error ?? event.message ?? event.summary ?? event.command ?? "";
        if (detail.length > 0)
            fields.push({ label: root.eventFailed(event) ? qsTr("Reason") : qsTr("Detail"), value: detail });
        return fields;
    }

    onVisibleChanged: AgentAuditService.setSurfaceVisible(root.owner, visible)
    Component.onCompleted: AgentAuditService.setSurfaceVisible(root.owner, visible)
    Component.onDestruction: AgentAuditService.setSurfaceVisible(root.owner, false)

    component EventRow: StyledRect {
        id: eventRow
        required property var eventData
        readonly property bool selected: root.selectedEvent === eventRow.eventData

        width: evidenceList.width
        height: 60
        radius: Tokens.rounding.medium
        color: eventRow.selected ? Colours.palette.m3secondaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHigh, 1)
        clip: true

        StyledRect {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 3
            radius: Tokens.rounding.full
            color: root.eventColour(eventRow.eventData)
        }

        StateLayer {
            anchors.fill: parent
            radius: parent.radius
            onClicked: root.selectedEvent = eventRow.eventData
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            StyledRect {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: Tokens.rounding.small
                color: Qt.tint(Colours.palette.m3surfaceContainer, Qt.alpha(root.eventColour(eventRow.eventData), 0.18))

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.eventIcon(eventRow.eventData)
                    color: root.eventColour(eventRow.eventData)
                    fontStyle: Tokens.font.icon.small
                    fill: 1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: eventRow.eventData.tool || root.eventLabel(eventRow.eventData)
                    font: Tokens.font.body.medium
                    color: eventRow.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: `${root.eventLabel(eventRow.eventData)} · ${eventRow.eventData.agentType || eventRow.eventData.agent_type || qsTr("primary")}`
                    font: Tokens.font.label.small
                    color: eventRow.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                }
            }

            StyledText {
                visible: !!eventRow.eventData.durationMs
                text: qsTr("%1 ms").arg(eventRow.eventData.durationMs || 0)
                font: Tokens.font.mono.small
                color: eventRow.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
            }
        }
    }

    component EvidenceField: StyledRect {
        required property string label
        required property string value

        Layout.fillWidth: true
        implicitHeight: valueText.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.medium
        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 1)

        Column {
            anchors.fill: parent
            anchors.margins: Tokens.padding.small
            spacing: 2

            StyledText {
                text: parent.parent.label.toUpperCase()
                font: Tokens.font.label.builders.small.weight(Font.Medium).build()
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                id: valueText
                width: parent.width
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                text: parent.parent.value
                font: Tokens.font.mono.small
                color: Colours.palette.m3onSurface
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacing.medium
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.fillHeight: true
            Layout.preferredWidth: 236
            radius: Tokens.rounding.large
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    StyledRect {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3primary

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "fact_check"
                            color: Colours.contrastOn(Colours.palette.m3primary)
                            fontStyle: Tokens.font.icon.small
                            fill: 1
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: qsTr("Agent Audit")
                            font: Tokens.font.title.small
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            text: qsTr("Local session evidence")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: Tokens.rounding.full
                    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 1)

                    Row {
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        StyledRect {
                            width: 7
                            height: 7
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Tokens.rounding.full
                            color: AgentAuditService.liveSessions.length > 0 ? Colours.palette.m3tertiaryOnSurface : Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("%1 live sessions").arg(AgentAuditService.liveSessions.length)
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.small
                    text: qsTr("RUNS")
                    font: Tokens.font.label.builders.small.weight(Font.Medium).build()
                    color: Colours.palette.m3onSurfaceVariant
                }

                ListView {
                    id: runsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Tokens.spacing.extraSmall
                    model: AgentAuditService.runs

                    delegate: StyledRect {
                        id: runRow
                        required property var modelData
                        width: runsList.width
                        height: 44
                        radius: Tokens.rounding.medium
                        color: AgentAuditService.selectedRunId === runRow.modelData.id ? Colours.palette.m3secondaryContainer : "transparent"

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            onClicked: AgentAuditService.loadRun(runRow.modelData.id)
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.small
                            anchors.rightMargin: Tokens.padding.small
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "history"
                                color: AgentAuditService.selectedRunId === runRow.modelData.id ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.small
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 32
                                elide: Text.ElideRight
                                text: runRow.modelData.label
                                font: Tokens.font.label.small
                                color: AgentAuditService.selectedRunId === runRow.modelData.id ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: AgentAuditService.runs.length === 0
                    wrapMode: Text.Wrap
                    text: qsTr("Recorded sessions appear here after the first tracked run.")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Tokens.rounding.large
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: AgentAuditService.selectedRunId.length > 0 ? qsTr("Replay timeline") : qsTr("Live timeline")
                            font: Tokens.font.title.small
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            text: AgentAuditService.selectedRunId.length > 0 ? qsTr("Step through a recorded session") : qsTr("Evidence recorded on this device")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    StyledRect {
                        implicitWidth: countText.implicitWidth + Tokens.padding.small * 2
                        implicitHeight: 26
                        radius: Tokens.rounding.full
                        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 1)

                        StyledText {
                            id: countText
                            anchors.centerIn: parent
                            text: qsTr("%1 events").arg(root.evidence.length)
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                ListView {
                    id: evidenceList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Tokens.spacing.extraSmall
                    model: root.evidence

                    delegate: EventRow {
                        eventData: modelData
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    visible: AgentAuditService.selectedRunId.length > 0
                    implicitHeight: 44
                    radius: Tokens.rounding.medium
                    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 1)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.small
                        anchors.rightMargin: Tokens.padding.small
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: AgentAuditService.replaying ? "pause" : "play_arrow"
                            color: Colours.palette.m3primaryOnSurface
                            fontStyle: Tokens.font.icon.small

                            MouseArea {
                                anchors.fill: parent
                                onClicked: AgentAuditService.toggleReplay()
                            }
                        }

                        StyledText {
                            text: AgentAuditService.replaying ? qsTr("Replaying") : qsTr("Paused")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
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
                    }
                }
            }
        }

        StyledRect {
            Layout.fillHeight: true
            Layout.preferredWidth: 272
            radius: Tokens.rounding.large
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Evidence")
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }

                    MaterialIcon {
                        visible: root.selectedEvent !== null
                        text: root.selectedEvent ? root.eventIcon(root.selectedEvent) : ""
                        color: root.selectedEvent ? root.eventColour(root.selectedEvent) : "transparent"
                        fontStyle: Tokens.font.icon.small
                        fill: 1
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.selectedEvent === null
                    wrapMode: Text.Wrap
                    text: qsTr("Choose an event to inspect its local evidence.")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.selectedEvent !== null
                    clip: true
                    contentHeight: evidenceFieldsColumn.implicitHeight

                    ColumnLayout {
                        id: evidenceFieldsColumn
                        width: parent.width
                        spacing: Tokens.spacing.extraSmall

                        Repeater {
                            model: root.selectedFields

                            delegate: EvidenceField {
                                required property var modelData
                                label: modelData.label
                                value: String(modelData.value)
                            }
                        }
                    }
                }
            }
        }
    }
}
