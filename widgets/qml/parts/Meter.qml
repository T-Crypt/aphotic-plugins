// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import qs.services

// A thin horizontal bar for `value` (0-1).
Item {
    id: root

    property real value: 0
    property color colour: Colours.signal
    property real thickness: 4

    implicitHeight: root.thickness

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Colours.signalStyle.hairline
    }

    Rectangle {
        width: Math.max(root.thickness, parent.width * Math.max(0, Math.min(1, root.value)))
        height: parent.height
        radius: height / 2
        color: root.value >= 0.9 ? Colours.palette.m3error : root.colour
    }
}
