// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import qs.components
import qs.services

Item {
    id: root

    property string icon: ""
    property real size: 28
    property color colour: Colours.palette.m3onSurface
    property bool filled: false
    property bool enabled: true

    signal clicked

    implicitWidth: root.size
    implicitHeight: root.size
    opacity: root.enabled ? 1 : 0.4

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.filled ? Qt.alpha(root.colour, 0.14) : "transparent"
        border.width: root.filled ? 1 : 0
        border.color: Colours.signalStyle.hairline
    }

    MaterialIcon {
        anchors.centerIn: parent
        text: root.icon
        color: root.colour
        font.pixelSize: Math.round(root.size * 0.6)
        font.family: "Material Symbols Rounded"
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
