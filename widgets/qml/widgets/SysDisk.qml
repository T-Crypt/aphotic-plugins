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

    function gib(kib: real): string {
        const g = kib / 1048576;
        return g >= 1024 ? `${(g / 1024).toFixed(1)}T` : `${Math.round(g)}G`;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        WText {
            text: qsTr("Disks")
            color: root.muted
            font.pixelSize: 12
        }

        Repeater {
            model: SystemUsage.disks

            ColumnLayout {
                id: disk

                required property var modelData

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true

                    WText {
                        Layout.fillWidth: true
                        text: disk.modelData.mount
                        font.pixelSize: 13
                    }

                    WText {
                        text: `${root.gib(disk.modelData.used)} / ${root.gib(disk.modelData.total)}`
                        color: root.muted
                        font.family: "JetBrainsMono Nerd Font Mono"
                        font.pixelSize: 11
                    }
                }

                Meter {
                    Layout.fillWidth: true
                    value: disk.modelData.perc
                    colour: root.accent
                }
            }
        }

        WText {
            visible: SystemUsage.disks.length === 0
            text: qsTr("Reading drives…")
            color: root.muted
        }
    }
}
