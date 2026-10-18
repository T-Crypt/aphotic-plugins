// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.components
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: (root.adapter?.devices?.values ?? []).filter(d => d.connected)

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true

            MaterialIcon {
                text: root.adapter?.enabled ? "bluetooth" : "bluetooth_disabled"
                color: root.adapter?.enabled ? root.accent : root.muted
                font.pixelSize: 18
            }

            WText {
                Layout.fillWidth: true
                text: !root.adapter ? qsTr("No Bluetooth adapter") : !root.adapter.enabled ? qsTr("Bluetooth is off") : root.devices.length === 0 ? qsTr("Nothing connected") : qsTr("%n connected", "", root.devices.length)
                color: root.muted
                font.pixelSize: 12
            }
        }

        Repeater {
            model: root.devices

            ColumnLayout {
                id: dev

                required property var modelData

                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true

                    MaterialIcon {
                        text: dev.modelData.icon && dev.modelData.icon.indexOf("headset") >= 0 ? "headphones" : dev.modelData.icon && dev.modelData.icon.indexOf("mouse") >= 0 ? "mouse" : dev.modelData.icon && dev.modelData.icon.indexOf("keyboard") >= 0 ? "keyboard" : "devices_other"
                        color: root.ink
                        font.pixelSize: 16
                    }

                    WText {
                        Layout.fillWidth: true
                        text: dev.modelData.name || dev.modelData.deviceName
                        font.pixelSize: 13
                    }

                    WText {
                        visible: dev.modelData.batteryAvailable === true
                        text: `${Math.round(dev.modelData.battery * 100)}%`
                        color: root.muted
                        font.family: "JetBrainsMono Nerd Font Mono"
                        font.pixelSize: 11
                    }
                }

                Meter {
                    Layout.fillWidth: true
                    visible: dev.modelData.batteryAvailable === true
                    value: dev.modelData.battery
                    colour: root.accent
                    thickness: 2
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
