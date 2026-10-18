// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    property date now: new Date()

    Ticker {
        active: root.active
        interval: 60000
        onTriggered: root.now = new Date()
    }

    WText {
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        text: root.now.toLocaleDateString(Qt.locale(), root.config.year ? "dddd, d MMMM yyyy" : "dddd, d MMMM")
        fontSizeMode: Text.Fit
        minimumPixelSize: 10
        font.pixelSize: root.height * 0.6
        font.weight: Font.Light
    }

    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: Math.min(parent.width, 48)
        height: 2
        radius: 1
        color: root.accent
    }
}
