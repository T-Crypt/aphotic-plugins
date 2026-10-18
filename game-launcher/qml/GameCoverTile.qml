// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services

// One cover cell in the notch tile's recent/pinned rows. The cover loads
// lazily and the cell works while it is still the placeholder, where the
// icon stands in and the name is the information. The whole cell is the
// click target, so there is no star here -- pinning happens on the plane.
Item {
    id: root

    required property var game

    signal activated

    readonly property int radius: Tokens.rounding.small

    implicitWidth: 94
    implicitHeight: 88

    StyledRect {
        anchors.fill: parent
        radius: root.radius
        color: Colours.palette.m3surfaceContainer
        border.width: 1
        border.color: Colours.signalStyle.hairline

        AnimatedImage {
            anchors.fill: parent
            clip: true
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            source: root.game.cover ?? ""
            visible: (root.game.cover ?? "").length > 0
            cache: false
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: (root.game.cover ?? "").length === 0
            text: "sports_esports"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.medium
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 26
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
        }

        StyledText {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.padding.extraSmall
            elide: Text.ElideRight
            text: root.game.name
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurface
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: root.radius
        showHoverBackground: true
        onClicked: root.activated()
    }
}
