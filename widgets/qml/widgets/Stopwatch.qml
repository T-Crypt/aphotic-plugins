// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    readonly property real startedAt: Number(root.store.startedAt) || 0
    readonly property real banked: Number(root.store.banked) || 0
    readonly property var laps: root.store.laps ?? []
    property real now: Date.now()

    readonly property bool running: root.startedAt > 0
    readonly property real elapsed: root.banked + (root.running ? root.now - root.startedAt : 0)

    Ticker {
        active: root.running && root.active
        interval: 100
        onTriggered: root.now = Date.now()
    }

    function fmt(ms: real): string {
        const t = Math.floor(ms / 100);
        const s = Math.floor(t / 10);
        return `${Math.floor(s / 60)}:${root.pad(s % 60)}.${t % 10}`;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        WText {
            text: root.fmt(root.elapsed)
            font.family: "JetBrainsMono Nerd Font Mono"
            font.pixelSize: Math.min(root.height * 0.3, root.width * 0.16)
        }

        RowLayout {
            spacing: 8

            IconButton {
                icon: root.running ? "pause" : "play_arrow"
                size: 32
                filled: true
                colour: root.accent
                onClicked: {
                    if (root.running) {
                        root.save("banked", root.elapsed);
                        root.save("startedAt", 0);
                    } else {
                        root.now = Date.now();
                        root.save("startedAt", root.now);
                    }
                }
            }

            IconButton {
                icon: "flag"
                size: 28
                enabled: root.running
                onClicked: root.save("laps", [root.elapsed].concat(root.laps).slice(0, 20))
            }

            IconButton {
                icon: "restart_alt"
                size: 28
                onClicked: {
                    root.save("startedAt", 0);
                    root.save("banked", 0);
                    root.save("laps", []);
                }
            }
        }

        Repeater {
            model: root.laps.slice(0, Math.max(0, Math.floor((root.height - 90) / 16)))

            WText {
                required property var modelData
                required property int index

                text: `${root.laps.length - index}  ${root.fmt(modelData)}`
                color: root.muted
                font.family: "JetBrainsMono Nerd Font Mono"
                font.pixelSize: 11
            }
        }
    }
}
