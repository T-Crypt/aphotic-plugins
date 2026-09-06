// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.services
import qs.modules.plugins.deepSignal

// The screensaver inside one plugin-hosted `fullscreen-overlay` surface
// (manifest v3.5). Core owns the window, takes the input and tears the
// whole thing down on the first real key or pointer event; this only ever
// draws.
//
// Every colour comes from the live palette, so the mark is whatever the
// current theme is rather than a fixed accent. Nothing here picks a hue.
//
// The cost model is the point. `progress` and `time` are stepped from the
// plugin's own 12 Hz clock, never animated, and that clock stops the
// moment there is nothing left moving -- which, with depth effects off,
// is a few seconds after the mark finishes resolving. From there the
// surface is a still picture submitting no frames at all.
Item {
    id: root

    readonly property real resolveDuration: 6.5

    // The mark never finishes arriving. After the initial resolve it
    // keeps breathing between roughly two-thirds and fully locked, on a
    // period slow enough to read as a signal drifting in and out rather
    // than as a pulse. A mark that settles is a logo on a black screen,
    // which is what the first calibration produced. The floor is set off
    // the measured brightness ramp: above about 0.75 the mark barely
    // changes, so a narrower breath is one nobody can see.
    readonly property real breathPeriod: 13
    readonly property int particleCount: DepthFx.particleCount
    readonly property real markCentre: 0.46

    // True for as long as the surface is on screen: the mark breathes and
    // the motes drift, so there is always something to step. It goes
    // false only on teardown, which is when the clock stops -- and the
    // surface is torn down, not hidden, so that is a real stop.
    readonly property bool animating: true

    property real elapsed: 0

    // Slow in, slow out. A linear ramp reads as a fade; this reads as
    // something rising the last few metres.
    readonly property real progress: {
        const t = Math.min(1, root.elapsed / root.resolveDuration);
        const arrived = t * t * (3 - 2 * t);
        const breath = 0.5 - Math.cos(root.elapsed * 2 * Math.PI / root.breathPeriod) / 2;
        return arrived * (0.68 + 0.32 * breath);
    }

    // The event the motes answer: nothing before the mark starts to
    // resolve, a peak through the middle of it, gone by the time it
    // settles.
    readonly property real emphasis: {
        const arrival = Math.sin(Math.min(1, root.elapsed / root.resolveDuration) * Math.PI);
        const swell = Math.max(0, Math.sin(root.elapsed * 2 * Math.PI / root.breathPeriod - 0.7)) * 0.4;
        return Math.max(arrival, swell);
    }

    // Tracked rather than inferred from `animating`, because the initial
    // binding pass reports a change into the state the surface was
    // already built in -- subscribing on both would take the clock's
    // count to two and leave it at one forever after, which is a 12 Hz
    // timer running on an idle machine with nothing left to draw.
    property bool subscribed: false

    function syncClock(): void {
        if (root.animating === root.subscribed)
            return;
        if (root.animating)
            SignalClock.subscribe();
        else
            SignalClock.release();
        root.subscribed = root.animating;
    }

    onAnimatingChanged: root.syncClock()
    Component.onCompleted: root.syncClock()

    Component.onDestruction: {
        if (root.subscribed)
            SignalClock.release();
    }

    Connections {
        target: SignalClock
        enabled: root.animating

        function onTick(dt: real): void {
            root.elapsed += dt;
        }
    }

    // Deep water, not a black rectangle: the palette's own surface colour
    // crushed almost to nothing, darkest at the edges.
    Rectangle {
        anchors.fill: parent

        gradient: Gradient {
            GradientStop {
                position: 0
                color: "#000000"
            }
            GradientStop {
                position: root.markCentre
                color: Qt.rgba(Colours.palette.m3primary.r * 0.16 + 0.012, Colours.palette.m3primary.g * 0.19 + 0.016, Colours.palette.m3primary.b * 0.26 + 0.022, 1)
            }
            GradientStop {
                position: 1
                color: "#000000"
            }
        }
    }

    ParticleField {
        anchors.fill: parent
        count: root.particleCount
        time: root.elapsed
        emphasis: root.emphasis
        markCentre: root.markCentre
        tint: Colours.palette.m3tertiary
    }

    SignalText {
        id: mark

        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * root.markCentre - height / 2

        text: Branding.text
        progress: root.progress
        time: root.elapsed
        grain: Branding.art ? 0.45 : 1
        bloom: root.emphasis * 0.35
        ink: Colours.palette.m3onSurface
        glow: Colours.palette.m3primary

        // A wordmark is one wide line sized off the screen; imported art
        // is a block that has to keep its own cell, so it drops the
        // letter spacing and takes a size that fits its widest line.
        pixelSize: Branding.art ? Math.max(8, Math.min(root.height / (Branding.text.split("\n").length + 2), root.width / (mark.artColumns * 0.62))) : Math.round(root.width * 0.075)
        letterSpacing: Branding.art ? 0 : Math.round(root.width * 0.018)

        readonly property int artColumns: {
            let widest = 1;
            for (const line of Branding.text.split("\n"))
                widest = Math.max(widest, line.length);
            return widest;
        }
    }
}
