// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    readonly property var toggles: [
        { icon: Audio.muted ? "volume_off" : "volume_up", label: qsTr("Sound"), on: !Audio.muted, act: () => { if (Audio.sink?.audio) Audio.sink.audio.muted = !Audio.sink.audio.muted; } },
        { icon: Audio.sourceMuted ? "mic_off" : "mic", label: qsTr("Mic"), on: !Audio.sourceMuted, act: () => { if (Audio.source?.audio) Audio.source.audio.muted = !Audio.source.audio.muted; } },
        { icon: DoNotDisturb.enabled ? "do_not_disturb_on" : "do_not_disturb_off", label: qsTr("Quiet"), on: DoNotDisturb.enabled === true, act: () => DoNotDisturb.toggle() }
    ]

    RowLayout {
        anchors.fill: parent
        spacing: 8

        Repeater {
            model: root.toggles

            Rectangle {
                id: t

                required property var modelData

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Math.min(height, 24) / 2
                color: t.modelData.on ? Qt.alpha(root.accent, 0.18) : "transparent"
                border.width: 1
                border.color: t.modelData.on ? root.accent : root.faint

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialIcon {
                        text: t.modelData.icon
                        color: t.modelData.on ? root.accent : root.muted
                        font.pixelSize: Math.min(22, t.height * 0.45)
                    }

                    WText {
                        visible: t.width > 80
                        text: t.modelData.label
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: t.modelData.act()
                }
            }
        }
    }
}
