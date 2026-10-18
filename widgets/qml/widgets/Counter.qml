// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.modules.plugins.widgets.parts

// Resets on its own at midnight: the count is stored with its date.
WidgetBase {
    id: root

    property date now: new Date()

    Ticker {
        active: root.active
        interval: 60000
        onTriggered: root.now = new Date()
    }

    readonly property string today: root.now.toDateString()
    readonly property int count: root.store.day === root.today ? (Number(root.store.count) || 0) : 0
    readonly property int goal: root.config.goal ?? 8

    function bump(by: int): void {
        root.save("day", root.today);
        root.save("count", Math.max(0, root.count + by));
    }

    RowLayout {
        anchors.fill: parent
        spacing: 10

        Ring {
            Layout.preferredWidth: Math.min(root.height, root.width * 0.5)
            Layout.preferredHeight: Layout.preferredWidth
            thickness: Math.max(3, width * 0.06)
            value: root.count / Math.max(1, root.goal)
            colour: root.accent

            WText {
                anchors.centerIn: parent
                text: `${root.count}/${root.goal}`
                font.pixelSize: parent.width * 0.2
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            WText {
                Layout.fillWidth: true
                text: root.config.title || qsTr("Count")
                font.pixelSize: root.px(0.13)
            }

            RowLayout {
                spacing: 6

                IconButton {
                    icon: "remove"
                    size: 26
                    enabled: root.count > 0
                    onClicked: root.bump(-1)
                }

                IconButton {
                    icon: "add"
                    size: 32
                    filled: true
                    colour: root.accent
                    onClicked: root.bump(1)
                }
            }
        }
    }
}
