// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors
//
// Aphotic desktop pet, runtime
// Copyright (C) 2023-2026 Trevin Tindall. Licensed GPL-3.0-or-later.
//
// The creature's own behaviour: what state it is in, when it moves, when it
// reacts, and how a harness event turns into a pose. The art is separate
// and carries its own terms; this file is the part that makes it a pet
// rather than a sprite on a wallpaper.

pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.services.ai
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
// Core builds one of these per screen, but there is only ever one pet.
// Every instance asks PetLibrary whether it is the one on duty; the rest
// draw nothing, run no timer and mask to nothing, so on a three-monitor
// desk two of the three surfaces are inert and the whole of those two
// outputs stays the desktop's. Ownership is a property of the shared
// singleton rather than of any surface, which is what lets it move: drag
// the pet off the right-hand edge and the surface on the next monitor
// takes over mid-drag.
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
    // so the desktop keeps its clicks everywhere the pet is not. Ordinarily
    // just the creature's own hitbox -- but the host's `Region` only ever
    // covers one item's bounds (`PluginOverlayWindow.qml`'s `mask: Region {
    // item: content.item?.maskItem }`), so while the action menu is open
    // this points at `menuRegion` instead: the bounding box around both the
    // menu and the hitbox, computed below. Anything in that box that is
    // neither the pet nor the menu (there is very little, since the menu
    // sits flush against the hitbox with no gap) is desktop the user
    // briefly can't click through -- a small, deliberate cost, not a bug.
    readonly property Item maskItem: root.menuOpen ? menuRegion : hitbox

    // Which output this instance is drawing on. The only thing the host
    // tells a plugin about its screen is what QtQuick's attached Screen
    // says, and `name` is the connector ("DP-1") -- the same string
    // Quickshell's own ShellScreen carries, because both read it off the
    // one QScreen.
    readonly property string screenName: Screen.name

    // Exactly one instance answers true. Everything below is gated on it:
    // what draws, what takes input, what subscribes to the clock and what
    // runs a timer, so an idle second monitor costs nothing at all.
    //
    // An unnamed screen fails open rather than shut. Ownership is decided
    // by comparing names, so a platform that hands out empty ones would
    // otherwise match nowhere and leave the desktop with no pet at all --
    // where drawing one per screen is merely the behaviour this plugin had
    // before it knew what a second monitor was.
    readonly property bool owns: root.screenName.length === 0 || PetLibrary.activeScreen === root.screenName

    // While a drag is in flight the pet's position comes from the shared
    // singleton rather than from this instance, because the instance
    // drawing it may not be the instance being dragged -- see the drag
    // handling further down.
    readonly property bool carried: PetLibrary.dragging && root.owns
    readonly property real drawX: root.carried ? root.clampX(PetLibrary.dragX * root.width - creature.width / 2) : root.petX
    readonly property real drawY: root.carried ? root.clampY(PetLibrary.dragY * root.height - creature.height / 2) : root.petY

    // What a harness session wants shown, or "" on a quiet desktop
    // (`PET-03`). Held above the pet's own idle/walk/react/fidget/sleep
    // vocabulary whenever it is non-empty: an agent doing something is
    // more worth showing than a pet that happens to be mid-fidget, and
    // being carried outranks both.
    readonly property string agentMood: PetAgentState.mood
    readonly property string agentCwd: PetAgentState.cwd
    readonly property string drawMood: root.carried ? "held" : (root.agentMood.length > 0 ? root.agentMood : root.mood)

    // The pet's own action list (PETS.md §7.1/§8) -- terminal + VS Code
    // today, any domain sibling's entries appended after, all from the
    // one registry every other surface kind already normalizes into.
    readonly property var petActions: PluginRegistry.surfacesFor("pet_action")

    // Whether the menu is open. A plain click toggles this instead of
    // poking once something is registered here -- see `onReleased` below.
    property bool menuOpen: false

    // Where the user put the pet, in this surface's pixels. Stored
    // normalised, so the same spot lands in the same place on a different
    // monitor, and turned back into a top-left corner here.
    readonly property real homePx: root.clampX(PetLibrary.homeX * root.width - creature.width / 2)
    readonly property real homePy: root.clampY(PetLibrary.homeY * root.height - creature.height / 2)

    readonly property real roamMin: root.clampX(root.homePx - PetLibrary.roam)
    readonly property real roamMax: root.clampX(root.homePx + PetLibrary.roam)

    readonly property bool held: root.mood === "held"
    readonly property bool animating: root.owns && (root.agentMood.length > 0 || root.mood === "walk" || root.mood === "react" || root.mood === "fidget")
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

    // Set on the instance holding the pointer grab, which keeps tracking
    // after the pet has left its screen. `dragCx`/`dragCy` are the pet's
    // centre in the pixels of whichever surface it is currently over --
    // not of this one.
    property string dragScreenName: ""
    property real dragCx: 0
    property real dragCy: 0

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

    // Dropping is the one moment the pet's own position has to catch up
    // with the shared one. Through the whole drag `petX`/`petY` sit where
    // the drag started, because what is drawn comes off the singleton
    // instead -- so letting go without placing leaves the pet drawn from
    // a position the drag never touched, and it snaps back to where it
    // was picked up.
    //
    // Placing has to come after settling, not before: place() refuses to
    // move a pet that is still held, which is what the write inside
    // commitDrag() would otherwise run into on its way through homePx.
    function endHold(): void {
        PetLibrary.commitDrag();
        root.dragScreenName = "";
        root.settle();
        root.place();
    }

    // Seeds a drag from where the pet actually is on this surface, and
    // hands the shared singleton the first position.
    function beginDrag(): void {
        root.menuOpen = false;
        root.dragScreenName = root.screenName;
        root.dragCx = root.petX + creature.width / 2;
        root.dragCy = root.petY + creature.height / 2;
        root.publishDrag();
        root.startHold();
    }

    // Advances a drag by one pointer delta, measured in this surface's
    // pixels. The pet's centre is kept in the pixels of whichever surface
    // it is currently over, so crossing an edge is just a matter of
    // subtracting that surface's width and naming the neighbour -- after
    // which the same raw pointer deltas keep moving it, because a pixel of
    // pointer travel is a pixel wherever the pointer happens to be.
    //
    // One hop per axis per event. A single motion event crossing two whole
    // monitors is not a thing a pointer does, and looping until it stops
    // crossing would be a loop over compositor-supplied geometry.
    function stepDrag(ddx: real, ddy: real): void {
        let size = PetLibrary.surfaceSize(root.dragScreenName);
        root.dragCx += ddx;
        root.dragCy += ddy;

        if (root.dragCx > size.w) {
            const right = PetLibrary.neighbour(root.dragScreenName, 1, 0);
            if (right) {
                root.dragCx -= size.w;
                root.dragScreenName = right.name;
                size = PetLibrary.surfaceSize(right.name);
            }
        } else if (root.dragCx < 0) {
            const left = PetLibrary.neighbour(root.dragScreenName, -1, 0);
            if (left) {
                root.dragScreenName = left.name;
                size = PetLibrary.surfaceSize(left.name);
                root.dragCx += size.w;
            }
        }

        if (root.dragCy > size.h) {
            const below = PetLibrary.neighbour(root.dragScreenName, 0, 1);
            if (below) {
                root.dragCy -= size.h;
                root.dragScreenName = below.name;
                size = PetLibrary.surfaceSize(below.name);
            }
        } else if (root.dragCy < 0) {
            const above = PetLibrary.neighbour(root.dragScreenName, 0, -1);
            if (above) {
                root.dragScreenName = above.name;
                size = PetLibrary.surfaceSize(above.name);
                root.dragCy += size.h;
            }
        }

        // At the end of the row there is nowhere to hand the pet to, so it
        // stops against the edge rather than being dragged off the desktop.
        root.dragCx = Math.max(0, Math.min(size.w, root.dragCx));
        root.dragCy = Math.max(0, Math.min(size.h, root.dragCy));
        root.publishDrag();
    }

    function publishDrag(): void {
        const size = PetLibrary.surfaceSize(root.dragScreenName);
        PetLibrary.moveDrag(root.dragScreenName, root.dragCx / size.w, root.dragCy / size.h);
    }

    // Every surface tells the singleton how big it is, because a drag
    // landing the pet on another monitor has to place it in that monitor's
    // surface and only the surface there knows its own size.
    function report(): void {
        PetLibrary.reportSurface(root.screenName, root.width, root.height);
    }

    function advance(dt: real): void {
        root.phase += dt;
        // A harness state loops in place for as long as it lasts, which
        // may be an arbitrary length of time -- unlike react/fidget, there
        // is no fixed duration to settle back from, so it only ever stops
        // because `agentMood` itself goes back to "".
        if (root.agentMood.length > 0)
            root.frame = root.frameOf(root.agentMood, true);
        else if (root.mood === "walk")
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

    onWidthChanged: root.report()
    onHeightChanged: root.report()
    onScreenNameChanged: root.report()

    // Taking over means placing the pet at the saved spot on this surface.
    // Handing over means standing down -- unless this is the surface
    // driving the drag, which keeps its state until the pointer is
    // released even though the pet has already moved on.
    onOwnsChanged: {
        if (root.owns)
            root.place();
        else if (root.dragScreenName.length === 0)
            root.settle();
    }

    Component.onCompleted: {
        root.report();
        root.place();
    }

    onAnimatingChanged: {
        if (root.animating)
            PetClock.subscribe();
        else
            PetClock.release();
    }

    // A monitor unplugged mid-drag takes this surface with it, so the
    // shared drag has to be let go of here or no other surface would ever
    // get the pet back.
    Component.onDestruction: {
        if (root.animating)
            PetClock.release();
        if (root.dragScreenName.length > 0)
            PetLibrary.cancelDrag();
    }

    PetView {
        id: creature

        // Only the surface on duty draws. The others keep the item, so its
        // size still answers for the mask and for the clamps, and simply
        // never show it.
        visible: root.owns
        mood: root.drawMood
        facing: root.facing
        frame: root.frame
        x: root.drawX
        y: root.drawY - root.lift
    }

    // What core masks the window to. On the screen holding the pet it
    // tracks the creature; everywhere else it parks off the surface, so
    // the mask comes out empty and that whole output stays the desktop's
    // to click. It stays live on the surface holding a pointer grab even
    // after the pet has moved to another screen, because pulling the input
    // region out from under a grab in flight is not worth finding out
    // about.
    Item {
        id: hitbox

        readonly property bool live: root.owns || root.dragScreenName.length > 0

        x: hitbox.live ? creature.x : -creature.width - 1
        y: hitbox.live ? creature.y : -creature.height - 1
        width: creature.width
        height: creature.height
    }

    PetActionMenu {
        id: menu

        visible: root.menuOpen
        actions: root.petActions
        // Flush against the hitbox's top edge, zero gap -- same reasoning
        // BarWindow.qml's own popout gives for its zero-gap flyout: a real
        // gap here is a dead zone neither this rect nor the hitbox covers,
        // and this window has no bridge-region trick to paper over it with.
        x: Math.max(0, Math.min(root.width - menu.width, hitbox.x + hitbox.width / 2 - menu.width / 2))
        y: hitbox.y - menu.height

        onTriggered: root.menuOpen = false
    }

    // Only consulted while `menuOpen`, see `maskItem` above -- the bounding
    // box around both the menu and the hitbox, since the host can mask to
    // exactly one item's rectangle and the menu sits above the pet rather
    // than inside it.
    Item {
        id: menuRegion

        x: Math.min(hitbox.x, menu.x)
        y: menu.y
        width: Math.max(hitbox.x + hitbox.width, menu.x + menu.width) - menuRegion.x
        height: hitbox.y + hitbox.height - menuRegion.y
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
        property real lastX: 0
        property real lastY: 0
        property bool dragged: false

        x: hitbox.x
        y: hitbox.y
        width: hitbox.width
        height: hitbox.height
        enabled: hitbox.live
        hoverEnabled: true
        preventStealing: true
        cursorShape: PetLibrary.locked ? Qt.PointingHandCursor : (root.held ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

        onEntered: {
            if (root.owns && root.agentMood.length === 0 && (root.mood === "idle" || root.mood === "sleep")) {
                root.lastPoke = Date.now();
                root.startFidget();
            }
        }

        onPressed: mouse => {
            const scene = grip.mapToItem(root, mouse.x, mouse.y);
            grip.pressX = scene.x;
            grip.pressY = scene.y;
            grip.lastX = scene.x;
            grip.lastY = scene.y;
            grip.dragged = false;
        }

        onPositionChanged: mouse => {
            if (!grip.pressed || PetLibrary.locked)
                return;
            const scene = grip.mapToItem(root, mouse.x, mouse.y);
            if (!grip.dragged) {
                if (Math.abs(scene.x - grip.pressX) < root.dragThreshold && Math.abs(scene.y - grip.pressY) < root.dragThreshold)
                    return;
                grip.dragged = true;
                root.beginDrag();
            }
            root.stepDrag(scene.x - grip.lastX, scene.y - grip.lastY);
            grip.lastX = scene.x;
            grip.lastY = scene.y;
        }

        // Priority, in order: a drag release always settles the drag.
        // Otherwise, a session waiting on the user outranks the action
        // menu -- clicking through to whatever it's waiting on is more
        // useful than a menu in the way of it -- which outranks the menu,
        // which outranks the plain poke reaction an install with nothing
        // registered still gets. Clicking the pet again while the menu is
        // already open closes it; there is no other way to dismiss it
        // (see `menuRegion`'s comment on why an outside click can't).
        onReleased: {
            if (grip.dragged) {
                root.endHold();
            } else if (root.agentMood === "attentionRequired" && root.agentCwd.length > 0) {
                AgentWindowFocus.focusByCwd(root.agentCwd);
            } else if (root.petActions.length > 0) {
                root.menuOpen = !root.menuOpen;
            } else {
                root.poke();
            }
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
        // A harness with something to show is worth more than ambient
        // wandering -- the beat timer stands down for as long as
        // `agentMood` does, same reasoning as `animating` above.
        running: root.owns && root.agentMood.length === 0 && root.mood === "idle" && !SessionLockState.locked
        repeat: true
        onTriggered: {
            interval = root.beatInterval();
            root.beatNow();
        }
    }

    // A small always-legible signal that something is happening,
    // independent of which pet is drawn. A pet gets a real pose for most
    // of `agentMood` (`PetLibrary._standardStates()`), and falls back to
    // its plain idle look for a mood it does not recognise, which would
    // otherwise make a harness's state invisible. `compacting` has no
    // sprite row at all yet (`PETS.md` §4.3) -- its own colour and its own, faster
    // pulse are what keep it from reading as the same thing as a stalled
    // `waitingProcess`, which is the one thing it is not allowed to look
    // like.
    Rectangle {
        id: stateBadge

        readonly property bool shown: root.owns && root.agentMood.length > 0
        readonly property color tone: {
            switch (root.agentMood) {
            case "working": return "#4aa3ff";
            case "waitingProcess": return "#e0a72e";
            case "attentionRequired": return "#e5484d";
            case "compacting": return "#b478e0";
            case "complete": return "#39c979";
            case "error": return "#e5484d";
            default: return "transparent";
            }
        }
        readonly property int pulseMs: root.agentMood === "attentionRequired" ? 380 : (root.agentMood === "compacting" ? 260 : 700)

        visible: stateBadge.shown
        width: 10
        height: 10
        radius: 5
        color: stateBadge.tone
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.35)
        x: creature.x + creature.width - width * 0.6
        y: creature.y - height * 0.3 - root.lift

        SequentialAnimation {
            running: stateBadge.shown
            loops: Animation.Infinite

            NumberAnimation {
                target: stateBadge
                property: "opacity"
                from: 0.35
                to: 1
                duration: stateBadge.pulseMs
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: stateBadge
                property: "opacity"
                from: 1
                to: 0.35
                duration: stateBadge.pulseMs
                easing.type: Easing.InOutQuad
            }
        }
    }
}
