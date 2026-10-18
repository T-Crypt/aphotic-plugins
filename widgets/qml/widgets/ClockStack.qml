// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    property date now: new Date()

    Ticker {
        active: root.active
        interval: 1000 * (60 - new Date().getSeconds())
        onTriggered: root.now = new Date()
    }

    readonly property int hour: root.hour24() ? root.now.getHours() : ((root.now.getHours() + 11) % 12) + 1
    readonly property real big: Math.min(root.height * (root.config.weekday ? 0.4 : 0.47), root.width * 0.62)

    ColumnLayout {
        anchors.centerIn: parent
        spacing: -root.big * 0.18

        WText {
            Layout.alignment: Qt.AlignHCenter
            text: root.pad(root.hour)
            font.pixelSize: root.big
            font.weight: Font.Bold
        }

        WText {
            Layout.alignment: Qt.AlignHCenter
            text: root.pad(root.now.getMinutes())
            color: root.accent
            font.pixelSize: root.big
            font.weight: Font.Light
        }

        WText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: root.big * 0.22
            visible: root.config.weekday === true
            text: root.now.toLocaleDateString(Qt.locale(), "dddd").toUpperCase()
            color: root.muted
            font.pixelSize: root.big * 0.16
            font.letterSpacing: 2
        }
    }
}
