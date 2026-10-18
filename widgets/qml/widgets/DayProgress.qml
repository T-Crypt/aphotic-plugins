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

    readonly property real day: {
        const mins = root.now.getHours() * 60 + root.now.getMinutes();
        if (!root.config.workday)
            return mins / 1440;
        const start = (root.config.start ?? 9) * 60;
        const end = Math.max(start + 1, (root.config.end ?? 17) * 60);
        return Math.max(0, Math.min(1, (mins - start) / (end - start)));
    }
    readonly property real week: (((root.now.getDay() + 6) % 7) + root.now.getHours() / 24) / 7
    readonly property real month: (root.now.getDate() - 1 + root.now.getHours() / 24) / new Date(root.now.getFullYear(), root.now.getMonth() + 1, 0).getDate()
    readonly property real year: {
        const start = new Date(root.now.getFullYear(), 0, 1);
        const end = new Date(root.now.getFullYear() + 1, 0, 1);
        return (root.now - start) / (end - start);
    }

    readonly property var rows: [
        { label: root.config.workday ? qsTr("Workday") : qsTr("Day"), value: root.day },
        { label: qsTr("Week"), value: root.week },
        { label: qsTr("Month"), value: root.month }
    ].concat(root.config.year ? [{ label: qsTr("Year"), value: root.year }] : [])

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Repeater {
            model: root.rows

            ColumnLayout {
                id: row

                required property var modelData

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true

                    WText {
                        Layout.fillWidth: true
                        text: row.modelData.label
                        color: root.muted
                        font.pixelSize: Math.min(13, root.height / root.rows.length * 0.3)
                    }

                    WText {
                        text: `${Math.floor(row.modelData.value * 100)}%`
                        font.family: "JetBrainsMono Nerd Font Mono"
                        font.pixelSize: Math.min(13, root.height / root.rows.length * 0.3)
                    }
                }

                Meter {
                    Layout.fillWidth: true
                    value: row.modelData.value
                    colour: root.accent
                    thickness: 3
                }
            }
        }
    }
}
