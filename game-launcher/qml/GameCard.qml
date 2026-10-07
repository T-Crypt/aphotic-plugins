// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.gameLauncher

// One grid cell. The cover loads asynchronously (local path or the
// Steam CDN URL the scanner handed over) and the card is fully usable
// while it is still the placeholder. AnimatedImage is the one image
// type used: it plays gif/webp (animated covers, only with the SGDB
// opt-ins on) and shows a still frame for everything else.
Item {
    id: root

    required property var game

    implicitWidth: 200
    implicitHeight: 280
    width: parent ? parent.width : 200
    height: parent ? parent.height : 280

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer
        border.width: 1
        border.color: Colours.signalStyle.hairline

        AnimatedImage {
            id: cover

            anchors.fill: parent
            clip: true
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            source: root.game.cover
            visible: root.game.cover.length > 0
            cache: false
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 84
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.transparent
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Colours.palette.m3surfaceContainerLow, 0.92)
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                spacing: 2

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.game.name
                    font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: root.game.source
                    opacity: 0.7
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        // Placeholder over an empty cover slot.
        StyledRect {
            anchors.centerIn: parent
            width: 64
            height: 64
            visible: root.game.cover.length === 0
            radius: Tokens.rounding.medium
            color: Colours.palette.m3surfaceContainerHigh

            MaterialIcon {
                anchors.centerIn: parent
                text: "sports_esports"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.large
            }
        }

        // Favorite star: a small chip, click toggles, does not launch.
        StyledRect {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            implicitWidth: 30
            implicitHeight: 30
            radius: Tokens.rounding.full
            color: Qt.alpha(Colours.palette.m3surfaceContainerLow, 0.8)

            MaterialIcon {
                anchors.centerIn: parent
                text: root.game.favorite ? "star" : "star_outline"
                color: root.game.favorite ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
                fill: root.game.favorite ? 1 : 0
            }

            MouseArea {
                anchors.fill: parent
                onClicked: (mouse) => {
                    mouse.accepted = true;
                    GameLauncherService.toggleFavorite(root.game.name, root.game.source);
                }
            }
        }

        StateLayer {
            anchors.fill: parent
            radius: parent.radius
            showHoverBackground: true
            onClicked: GameLauncherWorkspace.launchSelected(root.game)
        }
    }
}
