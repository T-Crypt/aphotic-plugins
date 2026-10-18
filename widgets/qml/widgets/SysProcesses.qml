// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    Loader {
        active: root.active
        sourceComponent: ProcessUsageWatch {}
    }

    readonly property var rows: ProcessUsage.processes.slice(0, root.config.count ?? 5)
    readonly property real peak: root.rows.reduce((m, p) => Math.max(m, p.cpu), 1)

    ColumnLayout {
        anchors.fill: parent
        spacing: 2

        RowLayout {
            Layout.fillWidth: true

            WText {
                Layout.fillWidth: true
                text: qsTr("Busiest")
                color: root.muted
                font.pixelSize: 12
            }

            WText {
                text: qsTr("CPU · RAM")
                color: root.muted
                font.pixelSize: 11
            }
        }

        Repeater {
            model: root.rows

            ColumnLayout {
                id: proc

                required property var modelData

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true

                    WText {
                        Layout.fillWidth: true
                        text: proc.modelData.name
                        font.pixelSize: 12
                    }

                    WText {
                        text: `${proc.modelData.cpu.toFixed(0)}% · ${(proc.modelData.rssKib / 1048576).toFixed(1)}G`
                        color: root.muted
                        font.family: "JetBrainsMono Nerd Font Mono"
                        font.pixelSize: 11
                    }
                }

                Meter {
                    Layout.fillWidth: true
                    value: proc.modelData.cpu / root.peak
                    colour: root.accent
                    thickness: 2
                }
            }
        }

        WText {
            visible: root.rows.length === 0
            text: qsTr("Sampling…")
            color: root.muted
        }
    }
}
