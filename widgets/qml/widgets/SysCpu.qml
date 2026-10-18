// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import qs.components
import qs.services
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    Loader {
        active: root.active
        sourceComponent: SystemUsageWatch {}
    }

    RingStat {
        anchors.fill: parent
        value: SystemUsage.cpuPerc
        figure: `${Math.round(SystemUsage.cpuPerc * 100)}%`
        label: qsTr("CPU")
        detail: root.config.temp && SystemUsage.cpuTemp > 0 ? `${Math.round(SystemUsage.cpuTemp)}°C` : ""
        colour: root.accent
    }
}
