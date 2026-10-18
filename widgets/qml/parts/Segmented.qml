// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.services

Flow {
    id: root

    property var values: []
    property var labels: []
    property var current

    signal picked(var value)

    spacing: 4

    Repeater {
        model: root.values

        Rectangle {
            id: seg

            required property var modelData
            required property int index
            readonly property bool on: seg.modelData === root.current

            width: segLabel.implicitWidth + 16
            height: 24
            radius: 12
            color: seg.on ? Qt.alpha(Colours.signal, 0.22) : "transparent"
            border.width: 1
            border.color: seg.on ? Colours.signal : Colours.signalStyle.hairline

            WText {
                id: segLabel

                anchors.centerIn: parent
                text: root.labels[seg.index] ?? String(seg.modelData)
                font.pixelSize: 11
                color: seg.on ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(seg.modelData)
            }
        }
    }
}
