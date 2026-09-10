pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import qs.services
import qs.modules.plugins.liveWallpaper

// The [ui.background] surface. Core owns the window and has already put
// the poster frame on screen underneath this; all this does is fade a
// looping video over the top of it when there is one to play.
//
// Fading rather than switching is what makes pausing invisible: the still
// underneath is the same frame the video holds, so stopping playback
// settles onto the poster instead of blanking.
Item {
    id: root

    readonly property bool playing: LiveWallpaperService.shouldPlay

    // Sibling files in a plugin must import each other explicitly --
    // directory-implicit typing silently resolves a pragma Singleton to
    // undefined when the root file was reached through a dynamic Loader.

    Video {
        id: video

        anchors.fill: parent
        source: LiveWallpaperService.videoPath ? `file://${LiveWallpaperService.videoPath}` : ""
        fillMode: VideoOutput.PreserveAspectCrop
        muted: Settings.liveWallpaperMuted
        loops: MediaPlayer.Infinite

        opacity: 0

        // Only opaque once a frame has actually been decoded. Fading in on
        // `playing` alone showed a black rectangle over the poster for as
        // long as the first decode took.
        states: State {
            name: "shown"
            when: root.playing && video.playbackState === MediaPlayer.PlayingState && video.hasVideo

            PropertyChanges {
                video.opacity: 1
            }
        }

        transitions: Transition {
            NumberAnimation {
                property: "opacity"
                duration: 400
                easing.type: Easing.OutCubic
            }
        }
    }

    // Play/pause is driven from one place rather than bound to `playing`,
    // because MediaPlayer's state is not a property you can assign.
    function _sync(): void {
        if (root.playing)
            video.play();
        else
            video.pause();
    }

    onPlayingChanged: root._sync()
    Component.onCompleted: root._sync()

    Connections {
        target: video

        // A source change resets the player to Stopped, so the sync has to
        // run again on the new media rather than only when policy changes.
        function onSourceChanged(): void {
            Qt.callLater(root._sync);
        }
    }
}
