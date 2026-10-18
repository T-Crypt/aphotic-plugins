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
        sourceComponent: SystemUsageWatch {}
    }

    readonly property var stats: [
        { label: "CPU", value: SystemUsage.cpuPerc },
        { label: "RAM", value: SystemUsage.memPerc },
        { label: "GPU", value: SystemUsage.gpuStatsAvailable ? SystemUsage.gpuPerc : -1 },
        { label: "DISK", value: SystemUsage.disks[0]?.perc ?? -1 }
    ].filter(s => s.value >= 0)

    GridLayout {
        anchors.fill: parent
        columns: root.config.layout === "rows" ? 1 : root.stats.length
        rowSpacing: 8
        columnSpacing: 10

        Repeater {
            model: root.stats

            Item {
                id: stat

                required property var modelData

                Layout.fillWidth: true
                Layout.fillHeight: true

                // Columns: a vertical bar that fills from the bottom.
                ColumnLayout {
                    anchors.fill: parent
                    visible: root.config.layout !== "rows"
                    spacing: 4

                    WText {
                        Layout.alignment: Qt.AlignHCenter
                        text: `${Math.round(stat.modelData.value * 100)}`
                        font.pixelSize: Math.min(22, stat.width * 0.32)
                        font.weight: Font.Light
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillHeight: true
                        implicitWidth: Math.min(14, stat.width * 0.3)
                        radius: width / 2
                        color: root.faint

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Math.max(width, parent.height * stat.modelData.value)
                            radius: width / 2
                            color: stat.modelData.value >= 0.9 ? Colours.palette.m3error : root.accent
                        }
                    }

                    WText {
                        Layout.alignment: Qt.AlignHCenter
                        text: stat.modelData.label
                        color: root.muted
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    visible: root.config.layout === "rows"
                    spacing: 8

                    WText {
                        Layout.preferredWidth: 40
                        text: stat.modelData.label
                        color: root.muted
                        font.pixelSize: 11
                        font.letterSpacing: 1
                    }

                    Meter {
                        Layout.fillWidth: true
                        value: stat.modelData.value
                        colour: root.accent
                    }

                    WText {
                        Layout.preferredWidth: 36
                        horizontalAlignment: Text.AlignRight
                        text: `${Math.round(stat.modelData.value * 100)}%`
                        font.family: "JetBrainsMono Nerd Font Mono"
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
