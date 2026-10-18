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
        interval: root.config.seconds ? 1000 : 1000 * (60 - new Date().getSeconds())
        onTriggered: root.now = new Date()
    }

    readonly property bool h24: root.hour24()
    readonly property int hour: root.h24 ? root.now.getHours() : ((root.now.getHours() + 11) % 12) + 1
    readonly property int align: root.config.align === "center" ? Text.AlignHCenter : root.config.align === "right" ? Text.AlignRight : Text.AlignLeft

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillHeight: true
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: root.config.align === "center" ? Qt.AlignHCenter : root.config.align === "right" ? Qt.AlignRight : Qt.AlignLeft
            spacing: root.px(0.04)

            WText {
                text: `${root.h24 ? root.pad(root.hour) : root.hour}:${root.pad(root.now.getMinutes())}`
                font.pixelSize: Math.min(root.height * (root.config.date ? 0.62 : 0.85), root.width * (root.config.seconds ? 0.28 : 0.36))
                font.weight: Font.Light
                font.letterSpacing: -1
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: root.px(0.08)
                spacing: 0

                WText {
                    visible: !root.h24
                    text: root.now.getHours() < 12 ? "AM" : "PM"
                    color: root.accent
                    font.pixelSize: root.px(0.12)
                    font.weight: Font.Medium
                }

                WText {
                    visible: root.config.seconds === true
                    text: root.pad(root.now.getSeconds())
                    color: root.accent
                    font.family: "JetBrainsMono Nerd Font Mono"
                    font.pixelSize: root.px(0.16)
                }
            }
        }

        WText {
            Layout.fillWidth: true
            visible: root.config.date === true
            horizontalAlignment: root.align
            text: root.now.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
            color: root.muted
            font.pixelSize: root.px(0.13)
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
