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

    Art {
        anchors.fill: parent
        radius: 12
        source: root.player?.trackArtUrl ?? ""
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * 0.42
        radius: 12
        opacity: hover.hovered ? 1 : 0
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Qt.alpha(Colours.signalStyle.surface, 0.95) }
        }

        Behavior on opacity {
            NumberAnimation { duration: 160 }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 2

            Item {
                Layout.fillHeight: true
            }

            WText {
                Layout.fillWidth: true
                text: root.player?.trackTitle ?? ""
                font.pixelSize: root.px(0.07)
                font.weight: Font.Medium
            }

            RowLayout {
                Layout.fillWidth: true

                WText {
                    Layout.fillWidth: true
                    text: root.player?.trackArtist ?? ""
                    color: root.muted
                    font.pixelSize: root.px(0.06)
                }

                MediaControls {
                    size: root.px(0.13)
                }
            }
        }
    }

    HoverHandler {
        id: hover
    }
}
