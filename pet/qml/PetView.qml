// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.plugins.pet

// Draws whichever pet is configured. Every pet is a sprite sheet, so
// there is one draw path here and nothing behind it: PetLibrary hands
// back a bundled pet's manifest when an imported one does not load, and
// PetSheetCell falls back to the PNG copy when a sheet will not decode,
// so the blank case is handled before it reaches this file.
//
// PetSheetCell does the drawing, and the picker's tiles use it too, so a
// pet looks the same in Settings as it does on the desktop.
Item {
    id: root

    required property string mood
    required property int facing
    required property int frame

    // What the sheet asks to be drawn at, times what the user asked for.
    readonly property real sheetScale: PetLibrary.scale > 0 ? PetLibrary.scale : (cell.cellHeight > 0 ? PetLibrary.targetHeight / cell.cellHeight : 1)

    readonly property bool usingSheet: cell.ready

    implicitWidth: cell.implicitWidth
    implicitHeight: cell.implicitHeight

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
