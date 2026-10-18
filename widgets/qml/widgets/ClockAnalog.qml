// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Shapes
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    property date now: new Date()
    readonly property real r: root.u / 2

    Ticker {
        active: root.active
        interval: root.config.seconds ? 1000 : 1000 * (60 - new Date().getSeconds())
        onTriggered: root.now = new Date()
    }

    Item {
        id: dial

        width: root.u
        height: root.u
        anchors.centerIn: parent

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: root.faint
        }

        Repeater {
            model: root.config.marks === "none" ? 0 : 60

            Rectangle {
                required property int index
                readonly property bool major: index % 5 === 0

                visible: root.config.marks === "ticks" || major
                width: root.config.marks === "dots" ? (major ? 4 : 2) : (major ? 2 : 1)
                height: root.config.marks === "dots" ? width : (major ? root.r * 0.1 : root.r * 0.05)
                radius: root.config.marks === "dots" ? width / 2 : 0
                color: major ? root.ink : root.faint
                x: root.r - width / 2
                y: root.r * 0.06
                transform: Rotation {
                    origin.x: width / 2
                    origin.y: root.r - root.r * 0.06
                    angle: index * 6
                }
            }
        }

        Repeater {
            model: root.config.numerals ? 12 : 0

            WText {
                required property int index
                readonly property real a: (index + 1) * Math.PI / 6

                text: String(index + 1)
                color: root.muted
                font.pixelSize: root.r * 0.14
                x: root.r + Math.sin(a) * root.r * 0.72 - width / 2
                y: root.r - Math.cos(a) * root.r * 0.72 - height / 2
            }
        }

        component Hand: Rectangle {
            property real angle: 0
            property real length: 0.5

            width: 2
            height: root.r * length
            radius: width / 2
            x: root.r - width / 2
            y: root.r - height
            antialiasing: true
            rotation: angle
            transformOrigin: Item.Bottom
        }

        Hand {
            angle: (root.now.getHours() % 12) * 30 + root.now.getMinutes() * 0.5
            length: 0.5
            width: 4
            color: root.ink
        }

        Hand {
            angle: root.now.getMinutes() * 6 + (root.config.seconds ? root.now.getSeconds() * 0.1 : 0)
            length: 0.78
            width: 2.5
            color: root.ink
        }

        Hand {
            visible: root.config.seconds === true
            angle: root.now.getSeconds() * 6
            length: 0.86
            width: 1
            color: root.accent
        }

        Rectangle {
            width: 8
            height: 8
            radius: 4
            anchors.centerIn: parent
            color: root.accent
        }
    }
}
