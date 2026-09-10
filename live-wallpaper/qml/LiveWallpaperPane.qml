pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.liveWallpaper

ColumnLayout {
    id: root

    spacing: Tokens.spacing.small

    StyledText {
        Layout.fillWidth: true
        text: Themes.activeWallpaperIsVideo ? qsTr("Playing %1").arg(Themes.activeWallpaper) : qsTr("The current wallpaper is a still image. Pick a video wallpaper to see this do anything.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
        wrapMode: Text.WordWrap
    }

    StyledText {
        Layout.fillWidth: true
        visible: LiveWallpaperService.holdReason.length > 0
        text: LiveWallpaperService.holdReason
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
        wrapMode: Text.WordWrap
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsToggleRow {
            icon: "battery_saver"
            label: qsTr("Pause on battery")
            description: qsTr("Decoding video is the most expensive thing this plugin does")
            checked: Settings.liveWallpaperPauseOnBattery
            onToggled: state => Settings.liveWallpaperPauseOnBattery = state
        }

        SettingsToggleRow {
            icon: "layers"
            label: qsTr("Pause when covered")
            description: qsTr("Stops playback while any window is on the focused workspace")
            checked: Settings.liveWallpaperPauseWhenOccluded
            onToggled: state => Settings.liveWallpaperPauseWhenOccluded = state
        }

        SettingsToggleRow {
            icon: "volume_off"
            label: qsTr("Mute")
            description: qsTr("Wallpaper audio is off by default")
            checked: Settings.liveWallpaperMuted
            onToggled: state => Settings.liveWallpaperMuted = state
        }
    }
}
