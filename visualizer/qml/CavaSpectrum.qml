// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// One cava process for the whole session, whatever the overlay is
// mounted on. The host instantiates a PluginOverlayWindow per screen, so
// a per-item process would mean one cava, one pipe and one parse per
// monitor for a spectrum that is identical on all of them.
//
// Everything expensive here hangs off `_watchers`, the same
// registration-counted gate SystemUsage.detailedMonitoring uses: with
// nothing mounted there is no process, no timer and no frame, and the
// plugin costs what an uninstalled plugin costs.
Singleton {
    id: root

    readonly property int barCount: 96

    // Loudest normalised bar a frame may carry and still count as
    // silence. cava emits an exact 0 across the board on digital
    // silence, so this only has to clear rounding on a fading tail.
    readonly property real noiseFloor: 0.006

    // Three graces, coarsest last. `quietMs` hides the bars, `dozeMs`
    // stops cava, and once dozing the process runs `sampleMs` out of
    // every `sampleMs + dozeIntervalMs` so a source that resumes without
    // announcing itself on MPRIS or PipeWire is still picked up.
    readonly property int quietMs: 900
    readonly property int dozeMs: 12000
    readonly property int sampleMs: 1500
    readonly property int dozeIntervalMs: 6000

    // 0..1 per bar, low frequency first. Reassigned per frame only while
    // there is sound to show.
    property var levels: []

    // True whenever nothing has been above the noise floor recently. The
    // renderer stops drawing on this, which is what takes the idle cost
    // to zero rather than to "one cheap animation".
    property bool quiet: true

    // How many PipeWire nodes are playing something back. cava's own
    // capture node is an input stream, so it never counts here.
    readonly property int outputStreams: {
        let count = 0;
        for (const node of Audio.streams)
            if (root._isPlayback(node))
                count = count + 1;
        return count;
    }

    // Something has the overlay mounted, the session is usable, and the
    // machine has an audio path that could produce sound.
    readonly property bool wanted: root._watchers > 0 && !root.unavailable && !SessionLockState.locked && !Audio.muted && (root.outputStreams > 0 || (Players.active?.isPlaying ?? false))

    // Silent long enough that cava is not worth keeping alive.
    property bool dozing: false

    readonly property bool listening: root.wanted && (!root.dozing || root._sampling)

    readonly property bool unavailable: root._failures >= 3

    property int _watchers: 0
    property var _decay: []
    property real _lastSoundAt: 0
    property bool _sampling: false
    property int _failures: 0
    property int _seenStreams: 0

    // PluginRegistry already owns the one answer to where a plugin's
    // files live, so the config path is built from it rather than from a
    // second copy of that layout.
    readonly property string _configPath: `${PluginRegistry.pluginsDir}/visualizer/config/cava.conf`

    function subscribe(): void {
        root._failures = 0;
        root._watchers = root._watchers + 1;
    }

    function unsubscribe(): void {
        root._watchers = Math.max(0, root._watchers - 1);
    }

    // Only a node that says it is playback counts as one. A PwNode reaches
    // Audio.streams before its properties do, and cava's own capture node
    // spends that window indistinguishable from a player -- counting it
    // would have the plugin's own process wake the plugin. The binding
    // re-runs when the properties land, so the cost of the strict reading
    // is a fraction of a second of undercount.
    function _isPlayback(node: var): bool {
        return (node?.properties?.["media.class"] ?? "").indexOf("Output") >= 0;
    }

    function _silentFrame(): var {
        const frame = new Array(root.barCount);
        for (let i = 0; i < root.barCount; i++)
            frame[i] = 0;
        return frame;
    }

    function _hush(): void {
        root.quiet = true;
        root._decay = root._silentFrame();
        root.levels = root._decay;
    }

    function _wake(): void {
        root._lastSoundAt = Date.now();
        root.dozing = false;
    }

    function _ingest(line: string): void {
        const raw = line.split(";");
        if (raw.length < root.barCount)
            return;

        const prev = root._decay;
        const next = new Array(root.barCount);
        let peak = 0;

        for (let i = 0; i < root.barCount; i++) {
            const scaled = +raw[i] / 1000;
            const value = scaled > 0 ? (scaled > 1 ? 1 : scaled) : 0;
            if (value > peak)
                peak = value;
            const settled = prev[i] ?? 0;
            next[i] = value >= settled ? value : settled * 0.74 + value * 0.26;
        }

        root._failures = 0;

        if (peak > root.noiseFloor) {
            root._lastSoundAt = Date.now();
            root.quiet = false;
            root.dozing = false;
        }

        if (root.quiet)
            return;

        root._decay = next;
        root.levels = next;
    }

    onWantedChanged: {
        if (root.wanted)
            root._wake();
        else
            root._hush();
    }

    onDozingChanged: root._sampling = false

    onListeningChanged: proc.running = root.listening

    // A playback stream that was not there a moment ago is sound about
    // to happen, so leave the doze now rather than waiting up to 7.5s
    // for the next sample window. Only a rise counts; a stream going
    // away is the opposite news.
    onOutputStreamsChanged: {
        if (root.outputStreams > root._seenStreams && root.wanted)
            root._wake();
        root._seenStreams = root.outputStreams;
    }

    Component.onCompleted: root._hush()

    // The one clock, deliberately far below the frame rate and running
    // only while something is asking for a spectrum. It decides when to
    // hide and when to stop cava; waking is driven by the frames
    // themselves, so resuming never waits for a tick.
    Timer {
        interval: 500
        running: root.wanted
        repeat: true

        onTriggered: {
            const silentFor = Date.now() - root._lastSoundAt;
            if (!root.quiet && silentFor >= root.quietMs)
                root._hush();
            if (!root.dozing && silentFor >= root.dozeMs)
                root.dozing = true;
        }
    }

    Timer {
        interval: root._sampling ? root.sampleMs : root.dozeIntervalMs
        running: root.dozing && root.wanted
        repeat: true

        onTriggered: root._sampling = !root._sampling
    }

    Timer {
        id: relaunch

        interval: 2000

        onTriggered: {
            if (root.listening)
                proc.running = true;
        }
    }

    Process {
        id: proc

        command: ["cava", "-p", root._configPath]

        stdout: SplitParser {
            splitMarker: "\n"

            onRead: data => root._ingest(data)
        }

        onExited: {
            if (!root.listening)
                return;
            root._failures = root._failures + 1;
            if (!root.unavailable)
                relaunch.restart();
        }
    }

    // A player entering Playing is sound about to happen, so leave the
    // doze on it rather than waiting for the next sample window. The
    // matching signal for PipeWire is onOutputStreamsChanged above, not
    // Audio.streamsChanged: cava is itself a stream, so a handler on the
    // raw list fires every time this singleton starts or stops the
    // process and the plugin wakes itself out of every doze it enters.
    Connections {
        function onIsPlayingChanged(): void {
            if (root.wanted)
                root._wake();
        }

        target: Players.active
    }
}
