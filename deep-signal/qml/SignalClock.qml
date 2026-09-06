// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// One low-rate clock for every screen this screensaver is drawn on,
// running only while something is actually moving.
//
// Nothing in this plugin animates a property. A QML animation ticks once
// per frame, so a window holding a running one repaints at the display
// rate for as long as it runs, whether or not the picture changed --
// which on a screensaver means burning the GPU on an idle machine for
// however long the user is away. Motion here is integrated from this
// timer at 12 Hz instead, and the timer stops outright when the last
// subscriber releases it.
//
// Deliberately this plugin's own clock rather than a shared one. A
// sibling plugin's singleton is not something to reach into, and core's
// DepthFx pulse answers a different question at a different rate.
Singleton {
    id: root

    readonly property int rate: 12
    readonly property bool running: root.subscribers > 0

    property int subscribers: 0

    signal tick(dt: real)

    function subscribe(): void {
        root.subscribers++;
    }

    function release(): void {
        root.subscribers = Math.max(0, root.subscribers - 1);
    }

    readonly property Timer _clock: Timer {
        interval: Math.round(1000 / root.rate)
        running: root.running
        repeat: true
        onTriggered: root.tick(interval / 1000)
    }
}
