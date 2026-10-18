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

    RowLayout {
        anchors.fill: parent
        spacing: 10

        Art {
            Layout.preferredWidth: root.height
            Layout.preferredHeight: root.height
            radius: root.height / 2
            source: root.player?.trackArtUrl ?? ""
        }

        WText {
            Layout.fillWidth: true
            text: root.player ? `${root.player.trackTitle}${root.player.trackArtist ? " · " + root.player.trackArtist : ""}` : qsTr("Nothing playing")
            font.pixelSize: root.height * 0.3
        }

        IconButton {
            icon: root.player?.isPlaying ? "pause" : "play_arrow"
            size: root.height * 0.8
            filled: true
            colour: root.accent
            enabled: root.player !== null
            onClicked: root.player.togglePlaying()
        }
    }
}
