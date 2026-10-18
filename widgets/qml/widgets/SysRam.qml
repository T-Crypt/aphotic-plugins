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
        value: SystemUsage.memPerc
        figure: `${Math.round(SystemUsage.memPerc * 100)}%`
        label: qsTr("MEMORY")
        detail: SystemUsage.memTotal > 0 ? `${(SystemUsage.memUsed / 1048576).toFixed(1)} / ${(SystemUsage.memTotal / 1048576).toFixed(0)} GiB` : ""
        colour: root.accent
    }
}
