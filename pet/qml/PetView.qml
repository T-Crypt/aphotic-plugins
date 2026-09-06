// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.plugins.pet

// Draws whichever pet is configured: a sprite sheet when one loads, a
// built-in vector pet otherwise. The fallback is unconditional -- a
// missing directory, a rejected manifest and an image that fails to
// decode all land in the same place, so the surface is never blank.
//
// PetSheetCell does the drawing, and the picker's tiles use it too, so a
// pet looks the same in Settings as it does on the desktop.
Item {
    id: root

    required property string mood
    required property real phase
    required property real excitement
    required property int facing
    required property int frame

    // What the sheet asks to be drawn at, times what the user asked for.
    // The built-in pets take the same multiplier below, so the size slider
    // means the same thing whichever kind of pet is on the desktop.
    readonly property real sheetScale: PetLibrary.scale > 0 ? PetLibrary.scale : (cell.cellHeight > 0 ? PetLibrary.targetHeight / cell.cellHeight : 1)

    readonly property bool usingSheet: cell.ready

    implicitWidth: root.usingSheet ? cell.implicitWidth : fallback.implicitWidth * PetLibrary.userScale
    implicitHeight: root.usingSheet ? cell.implicitHeight : fallback.implicitHeight * PetLibrary.userScale

    DefaultPet {
        id: fallback

        visible: !root.usingSheet
        mood: root.mood
        phase: root.phase
        excitement: root.excitement
        facing: root.facing
        // Vector pets have no sheet to scale, so the multiplier goes on
        // the item. Origin at the top left, so the pet grows down and
        // right out of its own corner -- which is the corner the implicit
        // size above has already accounted for.
        scale: PetLibrary.userScale
        transformOrigin: Item.TopLeft
    }

    PetSheetCell {
        id: cell

        manifest: PetLibrary.manifest
        petName: PetLibrary.spriteName
        column: root.frame
        row: PetLibrary.stateFor(root.mood).row
        facing: root.facing
        cellScale: root.sheetScale * PetLibrary.userScale
    }
}
