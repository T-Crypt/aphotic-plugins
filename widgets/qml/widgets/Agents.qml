// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.ai
import qs.modules.plugins.widgets.parts

// Every live agent session from the shell's shared feed. Holds the feed
// only while it is on screen.
WidgetBase {
    id: root

    readonly property var sessions: AgentEvents.liveSessions.slice().sort((a, b) => (a.startedAt - b.startedAt) || (a.id < b.id ? -1 : 1))

    onActiveChanged: AgentEvents.hold(`widget-${root.uid}`, root.active)
    Component.onCompleted: AgentEvents.hold(`widget-${root.uid}`, root.active)
    Component.onDestruction: AgentEvents.hold(`widget-${root.uid}`, false)

    function labelFor(id: string): string {
        return AgentRoles.entries.find(e => e.id === id)?.label ?? id;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        RowLayout {
            Layout.fillWidth: true

            MaterialIcon {
                text: AgentEvents.anyWaiting ? "notifications_active" : "smart_toy"
                color: AgentEvents.anyWaiting ? Colours.signal : root.muted
                font.pixelSize: 18
            }

            WText {
                Layout.fillWidth: true
                text: root.sessions.length === 0 ? qsTr("No agents running") : qsTr("%n agent(s)", "", root.sessions.length)
                color: root.muted
                font.pixelSize: 12
            }
        }

        Repeater {
            model: root.sessions.slice(0, Math.max(1, Math.floor((root.height - 28) / 30)))

            Rectangle {
                id: row

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 26
                radius: 13
                color: row.modelData.status === "waiting" ? Qt.alpha(Colours.signal, 0.14) : "transparent"
                border.width: 1
                border.color: row.modelData.status === "waiting" ? Colours.signal : root.faint

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    Rectangle {
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: 3
                        color: row.modelData.status === "waiting" ? Colours.signal : (row.modelData.status === "running" || row.modelData.status === "compacting") ? Colours.palette.m3primary : root.faint
                    }

                    WText {
                        text: root.labelFor(row.modelData.harness)
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }

                    WText {
                        Layout.fillWidth: true
                        text: (row.modelData.cwd || "").split("/").pop() || row.modelData.tool || row.modelData.status
                        color: root.muted
                        font.pixelSize: 11
                    }

                    WText {
                        visible: (row.modelData.inputTokens ?? 0) + (row.modelData.outputTokens ?? 0) > 0
                        text: `${Math.round(((row.modelData.inputTokens ?? 0) + (row.modelData.outputTokens ?? 0)) / 1000)}k`
                        color: root.muted
                        font.family: "JetBrainsMono Nerd Font Mono"
                        font.pixelSize: 10
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AgentWindowFocus.focusByCwd(row.modelData.cwd ?? "")
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
