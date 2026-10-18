// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.services
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    readonly property MprisPlayer player: Players.active
    property real position: 0

    Ticker {
        active: root.active && (root.player?.isPlaying ?? false) && root.config.progress === true
        interval: 1000
        onTriggered: {
            root.player.positionChanged();
            root.position = root.player.position;
        }
    }

    function clock(s: real): string {
        const t = Math.max(0, Math.floor(s));
        return `${Math.floor(t / 60)}:${root.pad(t % 60)}`;
    }

    RowLayout {
        anchors.fill: parent
        spacing: root.px(0.1)

        Art {
            Layout.preferredWidth: root.height
            Layout.preferredHeight: root.height
            source: root.player?.trackArtUrl ?? ""
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2

            WText {
                Layout.fillWidth: true
                text: root.player?.trackTitle || qsTr("Nothing playing")
                font.pixelSize: root.px(0.14)
                font.weight: Font.Medium
            }

            WText {
                Layout.fillWidth: true
                text: root.player?.trackArtist ?? ""
                color: root.muted
                font.pixelSize: root.px(0.11)
            }

            Item {
                Layout.fillHeight: true
            }

            Meter {
                Layout.fillWidth: true
                visible: root.config.progress === true && (root.player?.lengthSupported ?? false)
                value: root.player && root.player.length > 0 ? root.position / root.player.length : 0
                colour: root.accent
                thickness: 3
            }

            RowLayout {
                Layout.fillWidth: true

                WText {
                    visible: root.config.progress === true && (root.player?.lengthSupported ?? false)
                    text: `${root.clock(root.position)} / ${root.clock(root.player?.length ?? 0)}`
                    color: root.muted
                    font.family: "JetBrainsMono Nerd Font Mono"
                    font.pixelSize: root.px(0.08)
                }

                Item {
                    Layout.fillWidth: true
                }

                MediaControls {
                    size: root.px(0.24)
                    colour: root.ink
                }
            }
        }
    }
}
