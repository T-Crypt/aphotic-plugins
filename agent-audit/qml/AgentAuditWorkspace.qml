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
    property var selectedEvent: null
    property string owner: `agent-audit-${Math.random()}`

    onVisibleChanged: AgentAuditService.setSurfaceVisible(root.owner, visible)
    Component.onCompleted: AgentAuditService.setSurfaceVisible(root.owner, visible)
    Component.onDestruction: AgentAuditService.setSurfaceVisible(root.owner, false)

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.fillHeight: true
            Layout.preferredWidth: 240
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainerHigh

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                StyledText {
                    text: qsTr("Agent Audit")
                    font: Tokens.font.title.medium
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: qsTr("%1 live sessions").arg(AgentAuditService.liveSessions.length)
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Repeater {
                    model: AgentAuditService.runs

                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: Tokens.rounding.medium
                        color: AgentAuditService.selectedRunId === modelData.id ? Colours.palette.m3secondaryContainer : "transparent"

                        StyledText {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.small
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: modelData.label
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: AgentAuditService.loadRun(parent.modelData.id)
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    visible: AgentAuditService.runs.length === 0
                    wrapMode: Text.Wrap
                    text: qsTr("No recorded runs yet. Agent activity appears here after the first tracked session.")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainerHigh

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: AgentAuditService.selectedRunId.length > 0 ? qsTr("Replay evidence") : qsTr("Live evidence")
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        text: qsTr("%1 events").arg(root.evidence.length)
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                ListView {
                    id: evidenceList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Tokens.spacing.extraSmall
                    model: root.evidence

                    delegate: Rectangle {
                        required property var modelData
                        width: evidenceList.width
                        height: 52
                        radius: Tokens.rounding.medium
                        color: root.selectedEvent === modelData ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.small
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: modelData.event === "post_tool_use_failure" ? "error" : modelData.event === "pre_tool_use" ? "build" : "timeline"
                                color: modelData.event === "post_tool_use_failure" ? Colours.palette.m3error : Colours.palette.m3primary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true

                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: modelData.tool || modelData.event
                                    font: Tokens.font.body.medium
                                    color: Colours.palette.m3onSurface
                                }

                                StyledText {
                                    text: modelData.agentType || modelData.event
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }

                            StyledText {
                                text: modelData.durationMs ? qsTr("%1 ms").arg(modelData.durationMs) : ""
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selectedEvent = parent.modelData
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: AgentAuditService.selectedRunId.length > 0

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

                    MaterialIcon {
                        text: AgentAuditService.replaying ? "pause" : "play_arrow"
                        color: Colours.palette.m3primary

                        MouseArea {
                            anchors.fill: parent
                            onClicked: AgentAuditService.toggleReplay()
                        }
                    }
                }
            }
        }

        StyledRect {
            Layout.fillHeight: true
            Layout.preferredWidth: 260
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainerHigh

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                StyledText {
                    text: qsTr("Evidence")
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.selectedEvent ? JSON.stringify(root.selectedEvent, null, 2) : qsTr("Select an event to inspect its local evidence.")
                    font: Tokens.font.mono.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}
