// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.plugins.pet

// Draws whichever pet is configured: an imported sprite sheet when one
// loads, a built-in vector pet otherwise. The fallback is unconditional
// -- a missing directory, a rejected manifest and an image that fails to
// decode all land in the same place, so the surface is never blank.
//
// The sheet is one Image behind a clipping viewport, offset to the wanted
// cell, rather than a re-clipped or re-decoded source per frame. Changing
// a frame then costs two coordinate writes on a node the GPU already
// holds.
//
// Cell size and draw scale are worked out here rather than read straight
// off the manifest, because a manifest whose format fixes the grid states
// neither. Dividing the loaded image by the grid is also what lets one of
// those sheets be exported at any resolution and still land right.
Item {
    id: root

    required property string mood
    required property real phase
    required property real excitement
    required property int facing
    required property int frame

    readonly property real cellWidth: PetLibrary.frameWidth > 0 ? PetLibrary.frameWidth : (PetLibrary.columns > 0 ? sheet.implicitWidth / PetLibrary.columns : 0)
    readonly property real cellHeight: PetLibrary.frameHeight > 0 ? PetLibrary.frameHeight : (PetLibrary.rows > 0 ? sheet.implicitHeight / PetLibrary.rows : 0)
    readonly property real drawScale: PetLibrary.scale > 0 ? PetLibrary.scale : (root.cellHeight > 0 ? PetLibrary.targetHeight / root.cellHeight : 1)

    readonly property bool usingSheet: PetLibrary.spriteReady && sheet.status === Image.Ready && root.cellWidth > 0 && root.cellHeight > 0

    implicitWidth: root.usingSheet ? root.cellWidth * root.drawScale : fallback.implicitWidth
    implicitHeight: root.usingSheet ? root.cellHeight * root.drawScale : fallback.implicitHeight

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
        width: root.cellWidth * root.drawScale
        height: root.cellHeight * root.drawScale
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
            width: sheet.implicitWidth * root.drawScale
            height: sheet.implicitHeight * root.drawScale
            x: -root.frame * root.cellWidth * root.drawScale
            y: -PetLibrary.stateFor(root.mood).row * root.cellHeight * root.drawScale
        }
    }
}
