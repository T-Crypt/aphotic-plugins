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
        value: SystemUsage.gpuPerc
        figure: SystemUsage.gpuStatsAvailable ? `${Math.round(SystemUsage.gpuPerc * 100)}%` : "--"
        label: qsTr("GPU")
        detail: !SystemUsage.gpuDetected ? qsTr("none found") : (root.config.temp && SystemUsage.gpuTemp > 0 ? `${Math.round(SystemUsage.gpuTemp)}°C` : "")
        colour: root.accent
    }
}
