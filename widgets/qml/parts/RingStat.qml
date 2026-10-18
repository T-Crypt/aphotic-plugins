// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.services

// A ring meter with a big figure inside and a label and detail under it.
Item {
    id: root

    property real value: 0
    property string figure: ""
    property string label: ""
    property string detail: ""
    property color colour: Colours.signal

    readonly property real u: Math.min(root.width, root.height)

    Ring {
        id: ring

        anchors.centerIn: parent
        width: root.u
        height: root.u
        thickness: Math.max(3, root.u * 0.05)
        value: root.value
        colour: root.value >= 0.9 ? Colours.palette.m3error : root.colour
        startAngle: 135
        sweep: 270
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 0

        WText {
            Layout.alignment: Qt.AlignHCenter
            text: root.figure
            font.pixelSize: root.u * 0.22
            font.weight: Font.Light
        }

        WText {
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            color: Colours.palette.m3onSurfaceVariant
            font.pixelSize: root.u * 0.09
            font.letterSpacing: 1
        }

        WText {
            Layout.alignment: Qt.AlignHCenter
            visible: root.detail !== ""
            text: root.detail
            color: Colours.palette.m3onSurfaceVariant
            font.family: "JetBrainsMono Nerd Font Mono"
            font.pixelSize: root.u * 0.075
        }
    }
}
