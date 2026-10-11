// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.gameLauncher

// The Games tile: one button per installed store client. It reads the
// service's last scan (boot or the last Rescan); it never runs a scan
// itself, so opening the notch costs nothing.
ColumnLayout {
    id: root

    implicitWidth: parent ? parent.width : 240
    spacing: Tokens.spacing.small
    visible: GameLauncherService.settings.tile_enabled

    readonly property var clientNames: ["steam", "lutris", "heroic", "cartridges"]

    readonly property var presentClients: root.clientNames.filter(
        name => typeof GameLauncherService.clients[name] === "string"
            && GameLauncherService.clients[name].length > 0)

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "sports_esports"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.small
        }

        StyledText {
            text: qsTr("Games")
            font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
            color: Colours.palette.m3onSurface
        }

        Item {
            Layout.fillWidth: true
        }

        StyledText {
            visible: GameLauncherService.games.length > 0
            text: qsTr("%1").arg(GameLauncherService.games.length)
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }
    }

    // One row of client buttons, laid out to fill the tile width.
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: root.presentClients

            delegate: StyledRect {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Tokens.rounding.medium
                color: Colours.palette.m3surfaceContainer
                border.width: 1
                border.color: Colours.signalStyle.hairline

                StyledText {
                    anchors.centerIn: parent
                    text: root._clientLabel(modelData)
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: GameLauncherService.launchClient(modelData)
                }
            }
        }
    }

    // No store client at all: one honest line, the rest of the tile
    // stays empty.
    StyledText {
        Layout.fillWidth: true
        visible: root.presentClients.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: qsTr("No store clients found. Steam, Lutris, Heroic or Cartridges will appear here once installed.")
        wrapMode: Text.Wrap
        font: Tokens.font.label.small
        color: Colours.palette.m3onSurfaceVariant
    }

    function _clientLabel(name) {
        const labels = ({ steam: "Steam", lutris: "Lutris", heroic: "Heroic", cartridges: "Cartridges" });
        return labels[name] ?? name;
    }
}
