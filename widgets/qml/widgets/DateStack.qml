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
        interval: 60000
        onTriggered: root.now = new Date()
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 0

        WText {
            Layout.alignment: Qt.AlignHCenter
            text: root.now.toLocaleDateString(Qt.locale(), "dddd").toUpperCase()
            color: root.accent
            font.pixelSize: root.px(0.11)
            font.letterSpacing: 2
            font.weight: Font.Medium
        }

        WText {
            Layout.alignment: Qt.AlignHCenter
            text: String(root.now.getDate())
            font.pixelSize: Math.min(root.height * 0.5, root.width * 0.6)
            font.weight: Font.Light
        }

        WText {
            Layout.alignment: Qt.AlignHCenter
            text: root.now.toLocaleDateString(Qt.locale(), "MMMM")
            color: root.muted
            font.pixelSize: root.px(0.1)
        }
    }
}
