// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick

// A sparse drift of bioluminescent motes.
//
// Every position is a pure function of `time`, not an accumulation, so a
// dropped tick loses nothing and there is no per-particle state to keep.
// The whole field is plain Rectangles: a Canvas would rasterise and
// re-upload the full surface on the CPU every tick, and a ShaderEffect
// would need a .qsb a plugin has no build step to produce.
//
// The motes are not a background. `emphasis` rises while the mark is
// resolving, and each mote answers it by brightening and easing away
// from the mark's own band -- so the field reads as water displaced by
// something surfacing through it.
Item {
    id: root

    required property int count
    required property real time
    required property real emphasis
    required property color tint
    required property real markCentre

    function seed(index: int, salt: int): real {
        const x = Math.sin(index * 12.9898 + salt * 78.233) * 43758.5453;
        return x - Math.floor(x);
    }

    Repeater {
        model: root.count

        Item {
            id: mote

            required property int index

            readonly property real sx: root.seed(mote.index, 1)
            readonly property real sy: root.seed(mote.index, 2)
            readonly property real phase: root.seed(mote.index, 3) * Math.PI * 2
            readonly property real drift: 0.1 + root.seed(mote.index, 4) * 0.35
            readonly property real bob: 4 + root.seed(mote.index, 5) * 14
            readonly property real scale: 0.5 + root.seed(mote.index, 6) * 1.1

            // Distance from the mark's band decides how much of the
            // emphasis this mote feels, so the response is a wave through
            // the field rather than every mote flashing at once.
            readonly property real proximity: 1 - Math.min(1, Math.abs(mote.sy - root.markCentre) * 3.2)
            readonly property real answer: root.emphasis * mote.proximity
            readonly property real breath: 0.5 + 0.5 * Math.sin(root.time * 0.5 + mote.phase)

            width: core.width
            height: core.height

            x: ((mote.sx + root.time * mote.drift * 0.012) % 1) * root.width
            y: mote.sy * root.height
             + Math.sin(root.time * 0.22 + mote.phase) * mote.bob
             - mote.answer * 30 * (mote.sy < root.markCentre ? 1 : -1)

            // Two circles rather than one: a small bright core inside a
            // wide faint halo is what separates a bioluminescent mote from
            // a dot. Cheaper than a blur and there are only a couple of
            // dozen of them.
            Rectangle {
                anchors.centerIn: core
                width: core.width * 4.5
                height: width
                radius: width / 2
                color: root.tint
                opacity: Math.min(0.42, (0.05 + 0.07 * mote.breath) * (1 + mote.answer * 2.2))
            }

            Rectangle {
                id: core

                width: Math.max(1.5, 2.9 * mote.scale * (1 + mote.answer * 0.6))
                height: width
                radius: width / 2
                color: root.tint
                opacity: Math.min(0.88, (0.3 + 0.32 * mote.breath) * (1 + mote.answer * 1.6))
            }
        }
    }
}
