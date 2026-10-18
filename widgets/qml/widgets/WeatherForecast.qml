// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    readonly property var days: Weather.forecast.slice(0, root.config.days ?? 3)

    RowLayout {
        anchors.fill: parent
        spacing: 6

        Repeater {
            model: root.days

            ColumnLayout {
                id: day

                required property var modelData
                required property int index

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2

                WText {
                    Layout.alignment: Qt.AlignHCenter
                    text: day.index === 0 ? qsTr("Today") : new Date(day.modelData.day).toLocaleDateString(Qt.locale(), "ddd")
                    color: day.index === 0 ? root.accent : root.muted
                    font.pixelSize: root.px(0.11)
                }

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: Weather._iconFor(day.modelData.code)
                    color: root.ink
                    font.pixelSize: root.height * 0.3
                }

                WText {
                    Layout.alignment: Qt.AlignHCenter
                    text: `${Math.round(day.modelData.high)}° ${Math.round(day.modelData.low)}°`
                    font.pixelSize: root.px(0.12)
                }
            }
        }

        WText {
            visible: root.days.length === 0
            text: qsTr("No forecast yet")
            color: root.muted
        }
    }
}
