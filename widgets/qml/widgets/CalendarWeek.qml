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

    readonly property int firstDay: root.config.weekStart === "sunday" ? 0 : 1
    readonly property var week: {
        const back = (root.now.getDay() - root.firstDay + 7) % 7;
        return [0, 1, 2, 3, 4, 5, 6].map(i => new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate() - back + i));
    }

    RowLayout {
        anchors.fill: parent
        spacing: 4

        Repeater {
            model: root.week

            Rectangle {
                id: cell

                required property var modelData
                readonly property bool today: cell.modelData.toDateString() === root.now.toDateString()

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: cell.today ? Qt.alpha(root.accent, 0.18) : "transparent"
                border.width: cell.today ? 1 : 0
                border.color: root.accent

                Column {
                    anchors.centerIn: parent
                    spacing: 2

                    WText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: cell.modelData.toLocaleDateString(Qt.locale(), "ddd")
                        color: cell.today ? root.accent : root.muted
                        font.pixelSize: Math.min(root.height * 0.18, root.width / 7 * 0.3)
                    }

                    WText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String(cell.modelData.getDate())
                        font.pixelSize: Math.min(root.height * 0.34, root.width / 7 * 0.5)
                        font.weight: cell.today ? Font.Medium : Font.Light
                    }
                }
            }
        }
    }
}
