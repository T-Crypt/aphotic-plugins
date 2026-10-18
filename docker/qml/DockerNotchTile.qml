// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.docker

ColumnLayout {
    id: root

    readonly property string owner: `docker-tile-${Math.random()}`
    readonly property bool attention: DockerService.daemonState === "no-permission"
    property bool confirmPrune: false

    spacing: Tokens.spacing.small

    onVisibleChanged: DockerService.setSurfaceVisible(root.owner, visible)
    Component.onCompleted: DockerService.setSurfaceVisible(root.owner, visible)
    Component.onDestruction: DockerService.setSurfaceVisible(root.owner, false)

    component IconButton: StyledRect {
        id: button

        required property string icon
        property string tip: ""
        property bool danger: false
        property bool enabled: true

        signal activated

        implicitWidth: 24
        implicitHeight: 24
        radius: Tokens.rounding.full
        color: "transparent"
        opacity: button.enabled ? 1 : 0.4

        MaterialIcon {
            anchors.centerIn: parent
            text: button.icon
            color: button.danger ? Colours.alert : Colours.inkMuted
            fontStyle: Tokens.font.icon.small
        }

        StateLayer {
            radius: parent.radius
            disabled: !button.enabled
            onClicked: button.activated()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "deployed_code"
            color: DockerService.daemonOk ? Colours.signal : Colours.inkMuted
            fontStyle: Tokens.font.icon.large
            fill: DockerService.daemonOk ? 1 : 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: qsTr("Docker")
                color: Colours.ink
                font: Tokens.font.title.builders.medium.weight(Font.Medium).build()
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    switch (DockerService.daemonState) {
                    case "running":
                        return qsTr("%1 of %2 containers running").arg(DockerService.runningCount).arg(DockerService.containers.length);
                    case "no-permission":
                        return qsTr("The Docker socket refused this user");
                    case "stopped":
                        return qsTr("The daemon is not running");
                    default:
                        return qsTr("Checking…");
                    }
                }
                color: root.attention ? Colours.alert : Colours.inkMuted
                elide: Text.ElideRight
                font: Tokens.font.label.small
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: DockerService.daemonState === "no-permission"
        text: qsTr("Add yourself to the docker group with sudo usermod -aG docker $USER, then log out and back in.")
        wrapMode: Text.Wrap
        color: Colours.inkMuted
        font: Tokens.font.body.small
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(list.contentHeight, 360)
        visible: DockerService.daemonOk && DockerService.containers.length > 0

        Flickable {
            id: list

            anchors.fill: parent
            anchors.rightMargin: bar.visible ? bar.width + Tokens.spacing.extraSmall : 0
            contentHeight: groups.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: groups

                width: list.width
                spacing: Tokens.spacing.small

                Repeater {
                    model: DockerService.groups

                    ColumnLayout {
                        id: group

                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            StyledText {
                                Layout.fillWidth: true
                                text: group.modelData.name
                                color: Colours.inkMuted
                                elide: Text.ElideRight
                                font: Tokens.font.label.builders.small.weight(Font.Medium).letterSpacing(1).build()
                            }

                            StyledText {
                                text: `${group.modelData.running}/${group.modelData.total}`
                                color: Colours.inkMuted
                                font: Tokens.font.mono.small
                            }

                            IconButton {
                                visible: group.modelData.compose
                                icon: group.modelData.running > 0 ? "stop" : "play_arrow"
                                enabled: !group.modelData.busy
                                onActivated: group.modelData.running > 0 ? DockerService.stopProject(group.modelData.name) : DockerService.startProject(group.modelData.name)
                            }
                        }

                        Repeater {
                            model: group.modelData.containers

                            StyledRect {
                                id: row

                                required property var modelData
                                readonly property bool running: row.modelData.state === "running"

                                Layout.fillWidth: true
                                implicitHeight: rowLayout.implicitHeight + Tokens.padding.small * 2
                                radius: Tokens.rounding.small
                                color: hover.hovered ? Colours.signalStyle.hover : "transparent"
                                border.width: 1
                                border.color: Colours.signalStyle.hairline

                                HoverHandler {
                                    id: hover
                                }

                                RowLayout {
                                    id: rowLayout

                                    anchors.fill: parent
                                    anchors.margins: Tokens.padding.small
                                    spacing: Tokens.spacing.small

                                    StyledRect {
                                        implicitWidth: 7
                                        implicitHeight: 7
                                        radius: Tokens.rounding.full
                                        color: row.modelData.busy ? Colours.warn : row.running ? Colours.signal : Colours.outline
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: row.modelData.name
                                            color: Colours.ink
                                            elide: Text.ElideRight
                                            font: Tokens.font.label.medium
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: [row.modelData.image, row.modelData.status, row.modelData.ports].filter(s => s).join(" · ")
                                            color: Colours.inkMuted
                                            elide: Text.ElideRight
                                            font: Tokens.font.label.small
                                        }
                                    }

                                    StyledText {
                                        visible: row.running && !hover.hovered && row.modelData.memText !== ""
                                        text: `${row.modelData.cpuPerc.toFixed(1)}% · ${row.modelData.memText}`
                                        color: Colours.inkMuted
                                        font: Tokens.font.mono.small
                                    }

                                    RowLayout {
                                        visible: hover.hovered && !row.modelData.busy
                                        spacing: 0

                                        IconButton {
                                            icon: row.running ? "stop" : "play_arrow"
                                            onActivated: row.running ? DockerService.stopContainer(row.modelData.id) : DockerService.startContainer(row.modelData.id)
                                        }

                                        IconButton {
                                            icon: "restart_alt"
                                            visible: row.running
                                            onActivated: DockerService.restartContainer(row.modelData.id)
                                        }

                                        IconButton {
                                            icon: "article"
                                            onActivated: DockerService.openLogs(row.modelData.id)
                                        }

                                        IconButton {
                                            icon: "terminal"
                                            visible: row.running
                                            onActivated: DockerService.openShell(row.modelData.id)
                                        }
                                    }

                                    StyledText {
                                        visible: row.modelData.busy
                                        text: qsTr("working…")
                                        color: Colours.warn
                                        font: Tokens.font.label.small
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        FlickScrollBar {
            id: bar

            flickable: list
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: DockerService.daemonOk && DockerService.containers.length === 0
        text: qsTr("No containers yet.")
        color: Colours.inkMuted
        font: Tokens.font.body.small
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Colours.signalStyle.hairline
        visible: DockerService.daemonOk && DockerService.df.length > 0
    }

    RowLayout {
        Layout.fillWidth: true
        visible: DockerService.daemonOk && DockerService.df.length > 0
        spacing: Tokens.spacing.small

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: DockerService.df

                StyledText {
                    required property var modelData

                    Layout.fillWidth: true
                    text: `${modelData.type}: ${DockerService.dfLine(modelData)}`
                    color: Colours.inkMuted
                    elide: Text.ElideRight
                    font: Tokens.font.label.small
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: DockerService.pruneResult !== ""
                text: DockerService.pruneResult
                color: Colours.ink
                elide: Text.ElideRight
                font: Tokens.font.label.small
            }
        }

        // Two clicks: the first arms it, the second prunes. It disarms on
        // its own after a few seconds.
        StyledRect {
            implicitWidth: pruneLabel.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: 26
            radius: Tokens.rounding.full
            color: root.confirmPrune ? Qt.alpha(Colours.alert, 0.18) : "transparent"
            border.width: 1
            border.color: root.confirmPrune ? Colours.alert : Colours.signalStyle.hairline

            StyledText {
                id: pruneLabel

                anchors.centerIn: parent
                text: root.confirmPrune ? qsTr("Prune now?") : qsTr("Prune")
                color: root.confirmPrune ? Colours.alert : Colours.ink
                font: Tokens.font.label.small
            }

            StateLayer {
                radius: parent.radius
                onClicked: {
                    if (root.confirmPrune) {
                        root.confirmPrune = false;
                        DockerService.prune();
                    } else {
                        root.confirmPrune = true;
                        disarm.restart();
                    }
                }
            }

            Timer {
                id: disarm

                interval: 4000
                onTriggered: root.confirmPrune = false
            }
        }
    }
}
