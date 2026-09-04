// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.plugins.pet

// A pet inside one plugin-hosted `overlay` surface (manifest v3.4). Core
// owns the window and sized it once from the manifest, so the pet roams
// its own budgeted patch of the desktop and never asks for more.
//
// The behaviour loop is deliberately lazy. `mood` is "idle" nearly all
// the time, and "idle" means a still picture: no timer, no animation, no
// repaint. A beat timer wakes every 9-24 s and either sends the pet for a
// short walk or plays one small fidget, both of which subscribe to the
// shared 12 Hz PetClock for their few seconds and then let it stop again.
// After six quiet minutes the pet sleeps and even the beat timer stops.
Item {
    id: root

    readonly property int floorMargin: 8
    readonly property real speed: 34
    readonly property int sleepAfterMs: 6 * 60 * 1000

    // The host masks its window to this rather than to the whole surface,
    // so the desktop keeps its clicks everywhere the pet is not.
    readonly property Item maskItem: creature

    readonly property real roamMax: Math.max(0, root.width - creature.width)
    readonly property bool animating: root.mood === "walk" || root.mood === "react" || root.mood === "fidget"
    readonly property real fidgetDuration: root.durationOf("fidget", 0.62)
    readonly property real reactDuration: root.durationOf("react", 0.9)

    property string mood: "idle"
    property real phase: 0
    property real petX: 0
    property real targetX: 0
    property real lift: 0
    property real excitement: 0
    property int facing: 1
    property int frame: 0
    property bool placed: false
    property real lastPoke: Date.now()

    function durationOf(name: string, fallback: real): real {
        if (!PetLibrary.spriteReady)
            return fallback;
        const state = PetLibrary.stateFor(name);
        return Math.max(fallback, state.frames / state.fps);
    }

    function frameOf(name: string, loop: bool): int {
        if (!PetLibrary.spriteReady)
            return 0;
        const state = PetLibrary.stateFor(name);
        const index = Math.floor(root.phase * state.fps);
        return loop ? index % state.frames : Math.min(state.frames - 1, index);
    }

    function settle(): void {
        root.mood = "idle";
        root.phase = 0;
        root.frame = 0;
        root.lift = 0;
        root.excitement = 0;
    }

    function beatInterval(): int {
        return 9000 + Math.floor(Math.random() * 15000);
    }

    function beatNow(): void {
        if (Date.now() - root.lastPoke > root.sleepAfterMs) {
            root.mood = "sleep";
            root.frame = 0;
            return;
        }
        if (root.roamMax > 16 && Math.random() < 0.55)
            root.startWalk();
        else
            root.startFidget();
    }

    function startWalk(): void {
        const span = root.roamMax;
        let target = Math.random() * span;
        if (Math.abs(target - root.petX) < span * 0.25)
            target = root.petX + (root.petX > span / 2 ? -1 : 1) * span * 0.45;
        root.targetX = Math.max(0, Math.min(span, target));
        root.facing = root.targetX >= root.petX ? 1 : -1;
        root.phase = 0;
        root.mood = "walk";
    }

    function startFidget(): void {
        root.phase = 0;
        root.mood = "fidget";
    }

    function poke(): void {
        root.lastPoke = Date.now();
        root.phase = 0;
        root.excitement = 1;
        root.mood = "react";
    }

    function advance(dt: real): void {
        root.phase += dt;
        if (root.mood === "walk")
            root.stepWalk(dt);
        else if (root.mood === "react")
            root.stepReact();
        else if (root.mood === "fidget")
            root.stepFidget();
    }

    function stepWalk(dt: real): void {
        const remaining = root.targetX - root.petX;
        const step = root.speed * dt;
        if (Math.abs(remaining) <= step) {
            root.petX = root.targetX;
            root.settle();
            return;
        }
        root.petX += remaining > 0 ? step : -step;
        root.frame = root.frameOf("walk", true);
    }

    function stepFidget(): void {
        root.frame = root.frameOf("fidget", false);
        if (root.phase >= root.fidgetDuration)
            root.settle();
    }

    function stepReact(): void {
        const t = Math.min(1, root.phase / root.reactDuration);
        root.lift = Math.abs(Math.sin(t * Math.PI * 2)) * 16 * (1 - t * 0.35);
        root.excitement = 1 - t;
        root.frame = root.frameOf("react", false);
        if (root.phase >= root.reactDuration)
            root.settle();
    }

    onRoamMaxChanged: {
        if (!root.placed && root.roamMax > 0) {
            root.petX = Math.round(root.roamMax / 2);
            root.placed = true;
        } else if (root.petX > root.roamMax) {
            root.petX = root.roamMax;
        }
    }

    onAnimatingChanged: {
        if (root.animating)
            PetClock.subscribe();
        else
            PetClock.release();
    }

    Component.onDestruction: {
        if (root.animating)
            PetClock.release();
    }

    PetView {
        id: creature

        mood: root.mood
        phase: root.phase
        excitement: root.excitement
        facing: root.facing
        frame: root.frame
        x: root.petX
        y: root.height - creature.height - root.floorMargin - root.lift
    }

    // Sized to the pet, matching the maskItem above so the clickable area
    // and the input region are the same rectangle.
    MouseArea {
        x: creature.x
        y: creature.y
        width: creature.width
        height: creature.height
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            if (root.mood === "idle" || root.mood === "sleep") {
                root.lastPoke = Date.now();
                root.startFidget();
            }
        }
        onClicked: root.poke()
    }

    Connections {
        target: PetClock
        enabled: root.animating

        function onTick(dt: real): void {
            root.advance(dt);
        }
    }

    Timer {
        interval: root.beatInterval()
        running: root.mood === "idle" && !SessionLockState.locked
        repeat: true
        onTriggered: {
            interval = root.beatInterval();
            root.beatNow();
        }
    }
}
