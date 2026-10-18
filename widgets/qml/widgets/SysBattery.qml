// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.components
import qs.services
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool present: root.device?.isLaptopBattery ?? false
    readonly property real level: root.device?.percentage ?? 0
    readonly property bool charging: root.device?.state === UPowerDeviceState.Charging || root.device?.state === UPowerDeviceState.FullyCharged

    function timeLeft(seconds: real): string {
        if (!(seconds > 0))
            return "";
        const m = Math.round(seconds / 60);
        return m >= 60 ? qsTr("%1 h %2 min left").arg(Math.floor(m / 60)).arg(m % 60) : qsTr("%1 min left").arg(m);
    }

    RowLayout {
        anchors.fill: parent
        spacing: 12

        MaterialIcon {
            text: !root.present ? "power" : root.charging ? "battery_charging_full" : root.level > 0.8 ? "battery_full" : root.level > 0.5 ? "battery_5_bar" : root.level > 0.2 ? "battery_3_bar" : "battery_alert"
            color: root.present && root.level <= 0.2 && !root.charging ? Colours.palette.m3error : root.accent
            font.pixelSize: root.height * 0.55
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            WText {
                text: root.present ? `${Math.round(root.level * 100)}%` : qsTr("On AC power")
                font.pixelSize: root.present ? root.height * 0.36 : root.height * 0.22
                font.weight: Font.Light
            }

            WText {
                Layout.fillWidth: true
                visible: root.present
                text: root.charging ? qsTr("Charging") : root.timeLeft(root.device?.timeToEmpty ?? 0)
                color: root.muted
                font.pixelSize: root.height * 0.14
            }

            Meter {
                Layout.fillWidth: true
                visible: root.present
                value: root.level
                colour: root.accent
                thickness: 3
            }
        }
    }
}
