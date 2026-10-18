// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import qs.components
import qs.services
import qs.services.ai
import qs.modules.plugins.widgets.parts

// A hairline that carries a lit segment while the machine works. Dark at
// rest, as the shell is: light means something is alive.
WidgetBase {
    id: root

    readonly property real level: {
        switch (root.config.source) {
        case "gpu":
            return SystemUsage.gpuPerc;
        case "network":
            return Math.min(1, NetworkUsage.downloadSpeed / (10 * 1024 * 1024));
        case "agents":
            return AgentEvents.anyRunning ? 0.8 : (AgentEvents.anyWaiting ? 0.5 : 0);
        default:
            return SystemUsage.cpuPerc;
        }
    }
    readonly property bool moving: root.active && root.level > 0.02 && RenderGate.decorative

    Loader {
        active: root.active && (root.config.source === "cpu" || root.config.source === "gpu" || !root.config.source)
        sourceComponent: SystemUsageWatch {}
    }

    Loader {
        active: root.active && root.config.source === "network"
        sourceComponent: NetworkUsageWatch {}
    }

    onActiveChanged: if (root.config.source === "agents") AgentEvents.hold(`widget-${root.uid}`, root.active)
    Component.onDestruction: AgentEvents.hold(`widget-${root.uid}`, false)

    Rectangle {
        id: line

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 1
        color: root.faint
    }

    Rectangle {
        id: lit

        property real t: 0

        anchors.verticalCenter: parent.verticalCenter
        height: 2
        radius: 1
        width: Math.max(12, parent.width * (0.08 + root.level * 0.3))
        x: (parent.width - width) * lit.t
        color: root.accent
        opacity: 0.25 + root.level * 0.75
        visible: root.level > 0.02

        SequentialAnimation on t {
            running: root.moving
            loops: Animation.Infinite

            NumberAnimation {
                from: 0
                to: 1
                duration: Math.max(900, 4000 - root.level * 3000)
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                from: 1
                to: 0
                duration: Math.max(900, 4000 - root.level * 3000)
                easing.type: Easing.InOutSine
            }
        }
    }

    Rectangle {
        anchors.centerIn: lit
        width: lit.width * 1.6
        height: 10
        radius: 5
        visible: lit.visible
        color: Qt.alpha(root.accent, 0.12 * root.level)
    }
}
