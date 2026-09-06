// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.plugins.pet

// A pet inside one plugin-hosted `overlay` surface declaring
// `anchor = "free"`, so the surface is the whole usable output and the
// pet places itself anywhere in it. Core still owns the window and never
// resizes it: dragging the pet moves content inside a static surface, not
// the surface itself.
//
// The window is masked to the creature, so everywhere the pet is not is
// still the desktop's to click. That is what makes a screen-sized surface
// tolerable at all.
//
// The behaviour loop is deliberately lazy. `mood` is "idle" nearly all
// the time, and "idle" means a still picture: no timer, no animation, no
// repaint. A beat timer wakes every 9-24 s and either sends the pet for a
// short walk around wherever the user put it or plays one small fidget,
// both of which subscribe to the shared 12 Hz PetClock for their few
// seconds and then let it stop again. After six quiet minutes the pet
// sleeps and even the beat timer stops. Dragging drives no clock at all;
// the position comes straight off the pointer events.
Item {
    id: root

    readonly property real speed: 34
    readonly property int sleepAfterMs: 6 * 60 * 1000
    readonly property int dragThreshold: 6

    // The host masks its window to this rather than to the whole surface,
    // so the desktop keeps its clicks everywhere the pet is not.
    readonly property Item maskItem: creature

    // Where the user put the pet, in this surface's pixels. Stored
    // normalised, so the same spot lands in the same place on a different
    // monitor, and turned back into a top-left corner here.
    readonly property real homePx: root.clampX(PetLibrary.homeX * root.width - creature.width / 2)
    readonly property real homePy: root.clampY(PetLibrary.homeY * root.height - creature.height / 2)

    readonly property real roamMin: root.clampX(root.homePx - PetLibrary.roam)
    readonly property real roamMax: root.clampX(root.homePx + PetLibrary.roam)

    readonly property bool held: root.mood === "held"
    readonly property bool animating: root.mood === "walk" || root.mood === "react" || root.mood === "fidget"
    readonly property real fidgetDuration: root.durationOf("fidget", 0.62)
    readonly property real reactDuration: root.durationOf("react", 0.9)

    property string mood: "idle"
    property real phase: 0
    property real petX: 0
    property real petY: 0
    property real targetX: 0
    property real lift: 0
    property real excitement: 0
    property int facing: 1
    property int frame: 0
    property real lastPoke: Date.now()

    function clampX(value: real): real {
        return Math.max(0, Math.min(Math.max(0, root.width - creature.width), value));
    }

    function clampY(value: real): real {
        return Math.max(0, Math.min(Math.max(0, root.height - creature.height), value));
    }

    // Called whenever the saved spot or the surface changes, which covers
    // the first placement, a monitor swap, the settings pane's reset, and
    // a drag on another screen. Never while the pet is in hand.
    function place(): void {
        if (root.held)
            return;
        root.petX = root.homePx;
        root.petY = root.homePy;
    }

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
        if (root.roamMax - root.roamMin > 16 && Math.random() < 0.55)
            root.startWalk();
        else
            root.startFidget();
    }

    function startWalk(): void {
        const span = root.roamMax - root.roamMin;
        let target = root.roamMin + Math.random() * span;
        if (Math.abs(target - root.petX) < span * 0.25)
            target = root.petX + (root.petX > root.roamMin + span / 2 ? -1 : 1) * span * 0.45;
        root.targetX = Math.max(root.roamMin, Math.min(root.roamMax, target));
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

    function startHold(): void {
        root.lastPoke = Date.now();
        root.phase = 0;
        root.lift = 0;
        root.excitement = 0;
        root.mood = "held";
    }

    function endHold(): void {
        if (root.width > 0 && root.height > 0)
            PetLibrary.setHome((root.petX + creature.width / 2) / root.width, (root.petY + creature.height / 2) / root.height);
        root.settle();
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

    onHomePxChanged: root.place()
    onHomePyChanged: root.place()
    Component.onCompleted: root.place()

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
        y: root.petY - root.lift
    }

    // Sized to the pet, matching the maskItem above so the clickable area
    // and the input region are the same rectangle.
    //
    // Press-and-move drags, press-and-release poke. Deltas are taken in
    // the surface's own coordinates rather than the handler's, because the
    // handler moves with the pet: measuring in a frame that is itself
    // being dragged is how a drag ends up chasing its own tail.
    MouseArea {
        id: grip

        property real pressX: 0
        property real pressY: 0
        property real grabX: 0
        property real grabY: 0
        property bool dragged: false

        x: creature.x
        y: creature.y
        width: creature.width
        height: creature.height
        hoverEnabled: true
        preventStealing: true
        cursorShape: PetLibrary.locked ? Qt.PointingHandCursor : (root.held ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

        onEntered: {
            if (root.mood === "idle" || root.mood === "sleep") {
                root.lastPoke = Date.now();
                root.startFidget();
            }
        }

        onPressed: mouse => {
            const scene = grip.mapToItem(root, mouse.x, mouse.y);
            grip.pressX = scene.x;
            grip.pressY = scene.y;
            grip.grabX = root.petX;
            grip.grabY = root.petY;
            grip.dragged = false;
        }

        onPositionChanged: mouse => {
            if (!grip.pressed || PetLibrary.locked)
                return;
            const scene = grip.mapToItem(root, mouse.x, mouse.y);
            const dx = scene.x - grip.pressX;
            const dy = scene.y - grip.pressY;
            if (!grip.dragged) {
                if (Math.abs(dx) < root.dragThreshold && Math.abs(dy) < root.dragThreshold)
                    return;
                grip.dragged = true;
                root.startHold();
            }
            root.petX = root.clampX(grip.grabX + dx);
            root.petY = root.clampY(grip.grabY + dy);
        }

        onReleased: {
            if (grip.dragged)
                root.endHold();
            else
                root.poke();
            grip.dragged = false;
        }
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
