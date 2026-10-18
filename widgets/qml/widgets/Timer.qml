// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.plugins.widgets.parts

// Keeps its end time, not a count, so it is right after a restart or a
// stretch behind a fullscreen window.
WidgetBase {
    id: root

    readonly property real endsAt: Number(root.store.endsAt) || 0
    readonly property int pausedLeft: Number(root.store.pausedLeft) || 0
    readonly property int total: (root.config.minutes ?? 10) * 60
    property real now: Date.now()

    readonly property bool running: root.endsAt > 0
    readonly property int remainingSec: root.running ? Math.max(0, Math.ceil((root.endsAt - root.now) / 1000)) : (root.pausedLeft > 0 ? root.pausedLeft : root.total)

    Ticker {
        active: root.running
        interval: 250
        onTriggered: {
            root.now = Date.now();
            if (root.remainingSec === 0) {
                root.save("endsAt", 0);
                root.save("pausedLeft", 0);
                Quickshell.execDetached(["notify-send", "-a", "Aphotic", qsTr("Timer done"), qsTr("%1 minutes are up.").arg(root.config.minutes ?? 10)]);
            }
        }
    }

    function start(): void {
        root.now = Date.now();
        root.save("endsAt", root.now + root.remainingSec * 1000);
        root.save("pausedLeft", 0);
    }

    function pause(): void {
        root.save("pausedLeft", root.remainingSec);
        root.save("endsAt", 0);
    }

    function reset(): void {
        root.save("endsAt", 0);
        root.save("pausedLeft", 0);
    }

    Ring {
        id: ring

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(root.height, root.width * 0.5)
        height: width
        thickness: Math.max(3, width * 0.05)
        value: root.remainingSec / Math.max(1, root.total)
        colour: root.accent

        WText {
            anchors.centerIn: parent
            text: `${Math.floor(root.remainingSec / 60)}:${root.pad(root.remainingSec % 60)}`
            font.family: "JetBrainsMono Nerd Font Mono"
            font.pixelSize: ring.width * 0.2
        }
    }

    ColumnLayout {
        anchors.left: ring.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        IconButton {
            icon: root.running ? "pause" : "play_arrow"
            size: Math.min(40, root.height * 0.3)
            filled: true
            colour: root.accent
            onClicked: root.running ? root.pause() : root.start()
        }

        IconButton {
            icon: "restart_alt"
            size: Math.min(32, root.height * 0.24)
            onClicked: root.reset()
        }
    }
}
