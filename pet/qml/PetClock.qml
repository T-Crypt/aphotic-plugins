// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// One low-rate clock for every pet on every screen, running only while at
// least one of them has something to move.
//
// Nothing in this plugin animates a property. The shell's idle-GPU
// regression (E2-08) came from exactly that: a QML animation ticks once
// per frame, so any window holding a running one repaints at the display
// rate forever whether or not the picture changed. Motion here is
// integrated from this timer instead, at 12 Hz rather than 60-165, and
// the timer stops outright the moment the last pet goes back to standing
// still -- which is where a pet spends almost all of its life. An idle
// pet submits no frames at all.
//
// Same shape as services/DepthFx.qml's shared pulse clock, with the
// subscriber count added: DepthFx runs whenever glow is on, this runs
// only while somebody is mid-animation.
Singleton {
    id: root

    readonly property int rate: 12
    readonly property bool running: root.subscribers > 0 && !SessionLockState.locked

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
