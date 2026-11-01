// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// What a widget shows when it has nothing to show: one icon, one line,
// an optional hint, centred and sized to the space it is given.
Item {
    id: root

    property string icon: ""
    property string text: ""
    property string hint: ""
    property color colour: Colours.palette.m3onSurfaceVariant

    readonly property real u: Math.min(root.width, root.height)

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width, 320)
        spacing: Math.max(2, root.u * 0.04)

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            visible: root.icon !== ""
            text: root.icon
            color: Qt.alpha(root.colour, 0.7)
            font.pixelSize: Math.max(18, Math.min(40, root.u * 0.24))
        }

        WText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.text
            color: root.colour
            font.pixelSize: Math.max(12, Math.min(16, root.u * 0.11))
        }

        WText {
            Layout.fillWidth: true
            visible: root.hint !== ""
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.hint
            color: Qt.alpha(root.colour, 0.7)
            font.pixelSize: Math.max(10, Math.min(13, root.u * 0.08))
        }
    }
}
