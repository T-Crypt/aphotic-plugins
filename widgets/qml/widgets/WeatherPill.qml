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
        anchors.centerIn: parent
        spacing: 8

        MaterialIcon {
            text: Weather.hasData ? Weather.conditionIcon : "cloud_off"
            color: root.accent
            font.pixelSize: root.height * 0.55
        }

        WText {
            text: Weather.hasData ? `${Math.round(Weather.currentTemp)}° ${Weather.conditionText}` : "--"
            font.pixelSize: root.height * 0.36
        }
    }
}
