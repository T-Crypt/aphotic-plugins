// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.modules.plugins.widgets.parts

// Six columns, one per digit of HH MM SS, each lit in binary from the
// bottom row (1) to the top (8).
WidgetBase {
    id: root

    property date now: new Date()

    Ticker {
        active: root.active
        interval: 1000
        onTriggered: root.now = new Date()
    }

    readonly property var digits: [root.now.getHours(), root.now.getMinutes(), root.now.getSeconds()].reduce((all, n) => all.concat([Math.floor(n / 10), n % 10]), [])
    readonly property var heights: [2, 4, 3, 4, 3, 4]
    readonly property real dot: Math.min(root.width / 9, (root.height - (root.config.labels ? root.px(0.16) : 0)) / 4.8)

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4

        Row {
            spacing: root.dot * 0.45

            Repeater {
                model: 6

                Column {
                    id: col

                    required property int index

                    spacing: root.dot * 0.25
                    anchors.bottom: parent.bottom

                    Repeater {
                        model: 4

                        Rectangle {
                            required property int index
                            readonly property int bit: 3 - index

                            width: root.dot
                            height: root.dot
                            radius: width / 2
                            opacity: bit < root.heights[col.index] ? 1 : 0
                            color: (root.digits[col.index] >> bit) & 1 ? root.accent : "transparent"
                            border.width: 1
                            border.color: (root.digits[col.index] >> bit) & 1 ? root.accent : root.faint
                        }
                    }

                    WText {
                        visible: root.config.labels === true
                        width: root.dot
                        horizontalAlignment: Text.AlignHCenter
                        text: String(root.digits[col.index])
                        color: root.muted
                        font.pixelSize: root.dot * 0.55
                        font.family: "JetBrainsMono Nerd Font Mono"
                    }
                }
            }
        }
    }
}
