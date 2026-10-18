// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import Quickshell.Services.Mpris
import qs.components
import qs.services
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    readonly property MprisPlayer player: Players.active
    readonly property bool spinning: root.config.spin === true && root.active && (root.player?.isPlaying ?? false) && RenderGate.decorative

    Item {
        id: disc

        anchors.centerIn: parent
        width: root.u
        height: root.u

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Colours.signalStyle.raised
            border.width: 1
            border.color: Colours.signalStyle.hairline
        }

        Repeater {
            model: 4

            Rectangle {
                required property int index

                anchors.centerIn: parent
                width: disc.width * (0.92 - index * 0.06)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(root.ink, 0.06)
            }
        }

        StyledClippingRect {
            anchors.centerIn: parent
            width: disc.width * 0.6
            height: width
            radius: width / 2
            color: "transparent"

            Image {
                anchors.fill: parent
                source: root.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 384
                sourceSize.height: 384
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: disc.width * 0.07
            height: width
            radius: width / 2
            color: Colours.signalStyle.surface
            border.width: 1
            border.color: root.accent
        }

        RotationAnimation on rotation {
            running: root.spinning
            loops: Animation.Infinite
            from: disc.rotation
            to: disc.rotation + 360
            duration: 8000
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: root.player !== null
        onClicked: root.player.togglePlaying()
    }
}
