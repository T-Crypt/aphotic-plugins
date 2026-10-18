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
        sourceComponent: NetworkUsageWatch {}
    }

    function rate(bytes: real): string {
        const f = NetworkUsage.formatBytes(bytes);
        return `${f.value < 10 ? f.value.toFixed(1) : Math.round(f.value)} ${f.unit}`;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            RowLayout {
                spacing: 4

                MaterialIcon {
                    text: "south"
                    color: root.accent
                    font.pixelSize: root.px(0.14)
                }

                WText {
                    text: root.rate(NetworkUsage.downloadSpeed)
                    font.pixelSize: root.px(0.15)
                }
            }

            RowLayout {
                spacing: 4

                MaterialIcon {
                    text: "north"
                    color: root.muted
                    font.pixelSize: root.px(0.14)
                }

                WText {
                    text: root.rate(NetworkUsage.uploadSpeed)
                    color: root.muted
                    font.pixelSize: root.px(0.15)
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.config.graph === true

            Spark {
                anchors.fill: parent
                values: NetworkUsage.downloadBuffer.values
                colour: root.accent
                floor: 1024
            }

            Spark {
                anchors.fill: parent
                values: NetworkUsage.uploadBuffer.values
                colour: root.muted
                lineWidth: 1
                floor: 1024
            }
        }
    }
}
