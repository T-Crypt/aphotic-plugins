// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.plugins.pet

// One sprite pet's first idle frame, for a tile in the settings picker.
// A folder name is not a pet: "guga" and "rx93" next to each other say
// nothing about which is which, and a picker of identical placeholder
// icons is a list you have to try one at a time.
//
// A bundled pet's manifest comes from PetLibrary directly. An imported
// one is read here through PetLibrary.normalise(), the same parser the
// desktop pet uses, so a pet that draws here draws there and one this
// rejects shows its placeholder instead of a broken tile.
Item {
    id: root

    // Set for an imported pet: the folder under the pets directory.
    property string petName: ""

    // Set instead for a pet shipped with the plugin, straight out of
    // PetLibrary.bundled.
    property var bundledPet: null

    readonly property var manifest: root.bundledPet ? PetLibrary.bundledManifest(root.bundledPet) : root._manifest
    readonly property bool ready: cell.ready

    readonly property real fit: cell.cellHeight > 0 ? Math.min(root.width / cell.cellWidth, root.height / cell.cellHeight) : 1

    property var _manifest: null

    // Held at an empty path for a bundled pet, which has no pet.json on
    // disk to read.
    FileView {
        path: root.bundledPet || root.petName.length === 0 ? "" : `${PetLibrary.petsDir}/${root.petName}/pet.json`
        printErrors: false
        onLoaded: {
            try {
                root._manifest = PetLibrary.normalise(JSON.parse(text()));
            } catch (e) {
                root._manifest = null;
            }
        }
        onLoadFailed: root._manifest = null
    }

    PetSheetCell {
        id: cell

        anchors.centerIn: parent
        manifest: root.manifest
        petName: root.petName
        cellScale: root.fit
        // Enough to draw one cell at tile size, not the sheet at full
        // resolution.
        sourceHeight: root.manifest?.rows > 0 ? Math.round(root.manifest.rows * root.height) : 0
    }
}
