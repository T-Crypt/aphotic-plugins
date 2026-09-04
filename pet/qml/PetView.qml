// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.plugins.pet

// Draws whichever pet is configured: an imported sprite sheet when one
// loads, the built-in vector pet otherwise. The fallback is unconditional
// -- a missing directory, a rejected manifest and a PNG that fails to
// decode all land in the same place, so the surface is never blank.
//
// The sheet is one Image behind a clipping viewport, offset to the wanted
// cell, rather than a re-clipped or re-decoded source per frame. Changing
// a frame then costs two coordinate writes on a node the GPU already
// holds.
Item {
    id: root

    required property string mood
    required property real phase
    required property real excitement
    required property int facing
    required property int frame

    readonly property bool usingSheet: PetLibrary.spriteReady && sheet.status === Image.Ready

    implicitWidth: root.usingSheet ? PetLibrary.frameWidth * PetLibrary.scale : fallback.implicitWidth
    implicitHeight: root.usingSheet ? PetLibrary.frameHeight * PetLibrary.scale : fallback.implicitHeight

    DefaultPet {
        id: fallback

        visible: !root.usingSheet
        mood: root.mood
        phase: root.phase
        excitement: root.excitement
        facing: root.facing
    }

    Item {
        id: viewport

        visible: root.usingSheet
        width: PetLibrary.frameWidth * PetLibrary.scale
        height: PetLibrary.frameHeight * PetLibrary.scale
        clip: true
        transform: Scale {
            origin.x: viewport.width / 2
            xScale: root.facing
        }

        Image {
            id: sheet

            source: PetLibrary.sheetUrl
            asynchronous: true
            cache: true
            smooth: PetLibrary.smooth
            width: sheet.implicitWidth * PetLibrary.scale
            height: sheet.implicitHeight * PetLibrary.scale
            x: -root.frame * PetLibrary.frameWidth * PetLibrary.scale
            y: -PetLibrary.stateFor(root.mood).row * PetLibrary.frameHeight * PetLibrary.scale
        }
    }
}
