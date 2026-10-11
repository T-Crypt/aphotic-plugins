// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.gameLauncher

// The in-surface big picture mode: one large card, keyboard walk.
// The workspace root swaps it for the grid; it resizes nothing the
// host owns.
Item {
    id: root

    required property var games
    required property int index


    readonly property var current: root.games.length > 0 ? root.games[root.index] : null

    StyledRect {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.8, 760)
        height: Math.min(parent.height * 0.86, 560)
        radius: Tokens.rounding.extraLarge
        color: Colours.palette.m3surfaceContainer
        border.width: 1
        border.color: Colours.signalStyle.hairline

        AnimatedImage {
            id: cover

            anchors.fill: parent
            clip: true
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            source: root.current ? root.current.cover : ""
            visible: root.current !== null && root.current.cover.length > 0
            cache: false
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            Row {
                spacing: Tokens.spacing.small

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.current ? root.current.name : ""
                    font: Tokens.font.title.large
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.current !== null
                    text: root.current ? root.current.source : ""
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            Row {
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: launchLabel.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: 44
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primary

                    StyledText {
                        id: launchLabel
                        anchors.centerIn: parent
                        text: qsTr("Launch")
                        color: Colours.contrastOn(Colours.palette.m3primary)
                        font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        onClicked: root.current ? GameLauncherService.launch(root.current) : undefined
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("←/→ walk · Enter launch · Esc back")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}
