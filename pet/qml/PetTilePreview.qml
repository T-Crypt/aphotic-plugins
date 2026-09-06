// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.plugins.pet

// One imported pet's first idle frame, for a tile in the settings picker.
// A folder name is not a pet: "guga" and "rx93" next to each other say
// nothing about which is which, and a picker of identical placeholder
// icons is a list you have to try one at a time.
//
// Reads the folder's own manifest through PetLibrary.normalise(), the
// same parser the desktop pet uses, so a pet that draws here draws there
// and one this rejects shows its placeholder instead of a broken tile.
//
// `sourceSize` is the whole reason this is affordable. These sheets are
// commonly 1536x1872, which is 11 MB of RGBA decoded, and a pane with a
// dozen pets in it would ask for all of them at once. Asking for the
// sheet at tile resolution decodes about a tenth of that, and the pane is
// only alive while it is open.
Item {
    id: root

    required property string petName

    readonly property bool ready: root._manifest !== null && sheet.status === Image.Ready && root.cellWidth > 0 && root.cellHeight > 0

    readonly property real cellWidth: {
        const explicit = root._manifest?.frame?.width ?? 0;
        if (explicit > 0)
            return explicit;
        const columns = root._manifest?.columns ?? 0;
        return columns > 0 ? sheet.implicitWidth / columns : 0;
    }

    readonly property real cellHeight: {
        const explicit = root._manifest?.frame?.height ?? 0;
        if (explicit > 0)
            return explicit;
        const rows = root._manifest?.rows ?? 0;
        return rows > 0 ? sheet.implicitHeight / rows : 0;
    }

    readonly property real fit: root.cellHeight > 0 ? Math.min(root.width / root.cellWidth, root.height / root.cellHeight) : 1

    property var _manifest: null

    FileView {
        path: `${PetLibrary.petsDir}/${root.petName}/pet.json`
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

    Item {
        anchors.centerIn: parent
        width: root.cellWidth * root.fit
        height: root.cellHeight * root.fit
        clip: true
        visible: root.ready

        Image {
            id: sheet

            source: root._manifest ? PetLibrary.sheetUrlFor(root.petName, root._manifest) : ""
            asynchronous: true
            cache: true
            smooth: true
            // Enough to draw one cell at tile size, not the sheet at full
            // resolution. Height only, so the aspect ratio is Qt's problem
            // and implicitWidth still divides by the column count.
            sourceSize.height: root._manifest?.rows > 0 ? Math.round(root._manifest.rows * root.height) : 0
            width: sheet.implicitWidth * root.fit
            height: sheet.implicitHeight * root.fit
            x: 0
            y: 0
        }
    }
}
