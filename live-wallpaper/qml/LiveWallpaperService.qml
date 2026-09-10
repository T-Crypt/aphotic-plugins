pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.services

// When a video wallpaper should actually be playing.
//
// Decoding video forever behind every window is the expensive thing this
// plugin does, and it is worth almost nothing while something covers the
// desktop. The policy lives here rather than in the surface so that every
// screen's surface agrees, and so the Settings pane has one place to read.
Singleton {
    id: root

    readonly property string videoPath: Themes.activeVideoPath

    // Any window on the focused workspace means the desktop is covered.
    // This is a coarse test on purpose: a precise occlusion query would
    // need per-window geometry against each output, and the coarse answer
    // is right in the overwhelmingly common cases -- an empty workspace or
    // a working one.
    readonly property bool desktopCovered: (Hypr.focusedWorkspace?.toplevels?.values?.length ?? 0) > 0

    readonly property bool batterySaving: Settings.liveWallpaperPauseOnBattery && UPower.onBattery

    readonly property bool occlusionSaving: Settings.liveWallpaperPauseWhenOccluded && root.desktopCovered

    // The reason playback is held, for the Settings pane to explain
    // itself with. Order matters: this reports the first reason that
    // applies, and "no video" is not a pause, it is nothing to play.
    readonly property string holdReason: {
        if (!root.videoPath)
            return "";
        if (root.batterySaving)
            return qsTr("Paused to save battery");
        if (root.occlusionSaving)
            return qsTr("Paused while windows cover the desktop");
        return "";
    }

    readonly property bool shouldPlay: root.videoPath.length > 0 && !root.batterySaving && !root.occlusionSaving
}
