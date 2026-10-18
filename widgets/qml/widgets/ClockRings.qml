// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    property date now: new Date()

    Ticker {
        active: root.active
        interval: root.config.seconds ? 1000 : 1000 * (60 - new Date().getSeconds())
        onTriggered: root.now = new Date()
    }

    readonly property real t: Math.max(4, root.u * 0.055)

    Ring {
        anchors.centerIn: parent
        width: root.u
        height: root.u
        thickness: root.t
        value: ((root.now.getHours() % 12) + root.now.getMinutes() / 60) / 12
        colour: root.accent
    }

    Ring {
        anchors.centerIn: parent
        width: root.u - root.t * 3
        height: width
        thickness: root.t
        value: root.now.getMinutes() / 60
        colour: Qt.alpha(root.ink, 0.85)
    }

    Ring {
        visible: root.config.seconds === true
        anchors.centerIn: parent
        width: root.u - root.t * 6
        height: width
        thickness: root.t * 0.6
        value: root.now.getSeconds() / 60
        colour: root.muted
    }

    WText {
        visible: root.config.label === true
        anchors.centerIn: parent
        text: `${root.pad(root.now.getHours())}:${root.pad(root.now.getMinutes())}`
        font.pixelSize: root.u * 0.16
        font.weight: Font.Light
    }
}
