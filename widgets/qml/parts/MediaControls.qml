// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import Quickshell.Services.Mpris
import qs.services

Row {
    id: root

    property MprisPlayer player: Players.active
    property real size: 32
    property color colour: Colours.palette.m3onSurface

    spacing: root.size * 0.2

    IconButton {
        icon: "skip_previous"
        size: root.size * 0.8
        colour: root.colour
        enabled: root.player?.canGoPrevious ?? false
        anchors.verticalCenter: parent.verticalCenter
        onClicked: root.player.previous()
    }

    IconButton {
        icon: root.player?.isPlaying ? "pause" : "play_arrow"
        size: root.size
        filled: true
        colour: root.colour
        enabled: root.player !== null
        onClicked: root.player.togglePlaying()
    }

    IconButton {
        icon: "skip_next"
        size: root.size * 0.8
        colour: root.colour
        enabled: root.player?.canGoNext ?? false
        anchors.verticalCenter: parent.verticalCenter
        onClicked: root.player.next()
    }
}
