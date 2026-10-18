// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    RowLayout {
        anchors.fill: parent
        spacing: root.px(0.08)

        MaterialIcon {
            text: Weather.hasData ? Weather.conditionIcon : "cloud_off"
            color: root.accent
            font.pixelSize: root.height * 0.55
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            WText {
                text: Weather.hasData ? `${Math.round(Weather.currentTemp)}°` : "--"
                font.pixelSize: root.height * 0.4
                font.weight: Font.Light
            }

            WText {
                Layout.fillWidth: true
                text: Weather.hasData ? Weather.conditionText : (Weather.errorText || qsTr("Set a location in Settings"))
                color: root.muted
                font.pixelSize: root.px(0.12)
            }

            WText {
                Layout.fillWidth: true
                visible: root.config.place === true && Weather.resolvedLocationName !== ""
                text: Weather.resolvedLocationName
                color: root.muted
                font.pixelSize: root.px(0.1)
            }
        }
    }
}
