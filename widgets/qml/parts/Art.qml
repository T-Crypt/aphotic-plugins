// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import qs.components
import qs.services

// Cover art, or a quiet glyph when the player gives none.
Item {
    id: root

    property string source: ""
    property real radius: 10

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Colours.signalStyle.raised
        border.width: 1
        border.color: Colours.signalStyle.hairline
        visible: image.status !== Image.Ready

        MaterialIcon {
            anchors.centerIn: parent
            text: "music_note"
            color: Colours.palette.m3onSurfaceVariant
            font.pixelSize: Math.min(parent.width, parent.height) * 0.4
        }
    }

    StyledClippingRect {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        visible: image.status === Image.Ready

        Image {
            id: image

            anchors.fill: parent
            source: root.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 512
            sourceSize.height: 512
        }
    }
}
