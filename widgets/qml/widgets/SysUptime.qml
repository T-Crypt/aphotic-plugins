// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    property real seconds: 0

    Ticker {
        active: root.active
        interval: 60000
        onTriggered: uptime.reload()
    }

    FileView {
        id: uptime

        path: "/proc/uptime"
        onLoaded: root.seconds = parseFloat(uptime.text().split(" ")[0]) || 0
    }

    readonly property string pretty: {
        const m = Math.floor(root.seconds / 60);
        const d = Math.floor(m / 1440);
        const h = Math.floor((m % 1440) / 60);
        return d > 0 ? qsTr("%1d %2h %3m").arg(d).arg(h).arg(m % 60) : qsTr("%1h %2m").arg(h).arg(m % 60);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 2

        WText {
            Layout.fillWidth: true
            text: HostInfo.hostname || qsTr("This machine")
            font.pixelSize: root.px(0.2)
            font.weight: Font.Medium
        }

        WText {
            Layout.fillWidth: true
            visible: root.config.address === true && HostInfo.ipAddress !== ""
            text: HostInfo.ipAddress
            color: root.muted
            font.family: "JetBrainsMono Nerd Font Mono"
            font.pixelSize: root.px(0.12)
        }

        Item {
            Layout.fillHeight: true
        }

        WText {
            text: qsTr("up %1").arg(root.pretty)
            color: root.accent
            font.pixelSize: root.px(0.14)
        }
    }
}
