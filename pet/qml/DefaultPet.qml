// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.plugins.pet

// Whichever built-in pet is selected. Built-ins are vector paths drawn off
// the live palette rather than images, so they retint with the theme
// instead of sitting on the desktop as a foreign sprite -- which is also
// why there is one file per pet and not one sheet per pet.
//
// A Loader rather than three items behind `visible`, so only the selected
// pet's shape tree exists at all, and none of them exists while an
// imported sprite is drawing. Each pet is a pure function of `mood`,
// `phase`, `facing` and `excitement`, all pushed in by Pet.qml's brain;
// nothing below holds a timer or an animation.
Loader {
    id: root

    // Defaults to whichever built-in is selected. The settings pane sets
    // it per tile instead, which is what lets one picker show all three
    // pets live without a second copy of the switch below.
    property string petId: PetLibrary.builtin

    required property string mood
    required property real phase
    required property real excitement
    required property int facing

    active: root.visible

    sourceComponent: {
        switch (root.petId) {
        case "angler":
            return orbPet;
        case "clip":
            return clipPet;
        default:
            return mikoPet;
        }
    }

    Component {
        id: mikoPet

        MikoPet {
            mood: root.mood
            phase: root.phase
            excitement: root.excitement
            facing: root.facing
        }
    }

    Component {
        id: orbPet

        OrbPet {
            mood: root.mood
            phase: root.phase
            excitement: root.excitement
            facing: root.facing
        }
    }

    Component {
        id: clipPet

        ClipPet {
            mood: root.mood
            phase: root.phase
            excitement: root.excitement
            facing: root.facing
        }
    }
}
