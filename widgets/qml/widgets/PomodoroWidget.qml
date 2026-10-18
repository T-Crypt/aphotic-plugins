// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    readonly property int span: Pomodoro.isBreak ? Pomodoro.breakSeconds : Pomodoro.workSeconds

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        Ring {
            id: ring

            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(root.width, root.height - 44)
            Layout.preferredHeight: Layout.preferredWidth
            thickness: Math.max(3, width * 0.05)
            value: Pomodoro.remaining / Math.max(1, root.span)
            colour: Pomodoro.isBreak ? Colours.palette.m3tertiary : root.accent

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                WText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Pomodoro.formatTime(Pomodoro.remaining)
                    font.family: "JetBrainsMono Nerd Font Mono"
                    font.pixelSize: ring.width * 0.2
                }

                WText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Pomodoro.isBreak ? qsTr("break") : qsTr("focus")
                    color: root.muted
                    font.pixelSize: ring.width * 0.08
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            IconButton {
                icon: Pomodoro.running ? "pause" : "play_arrow"
                size: 32
                filled: true
                colour: root.accent
                onClicked: Pomodoro.toggle()
            }

            IconButton {
                icon: "skip_next"
                size: 28
                onClicked: Pomodoro.skip()
            }

            IconButton {
                icon: "restart_alt"
                size: 28
                onClicked: Pomodoro.reset()
            }
        }
    }
}
