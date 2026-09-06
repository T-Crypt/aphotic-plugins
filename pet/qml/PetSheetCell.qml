// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.plugins.pet

// One cell of one sprite sheet, retinted to the live palette if the pet
// declares an accent hue window. The desktop pet and the settings picker
// both draw through this, so a tile shows the same pet in the same
// colours the desktop is about to.
//
// The sheet is one Image behind a clipping viewport, offset to the wanted
// cell, rather than a re-clipped or re-decoded source per frame. Changing
// a frame costs two coordinate writes on a node the GPU already holds.
//
// The tinted path samples that same viewport through a
// ShaderEffectSource, so the cell is cut out once either way and the
// texture the shader reads is one cell rather than the whole sheet.
Item {
    id: root

    // In normalise()'s shape, or null. Everything here stays inert until
    // one arrives.
    required property var manifest

    // The folder under the pets directory this manifest came from, used
    // to build its sheet URL. Empty for a bundled pet, whose manifest
    // carries an already-resolved one.
    property string petName: ""

    property int column: 0
    property int row: 0
    property int facing: 1

    // Multiplies the cell's own pixel size. The desktop pet passes the
    // sheet's authored scale times the user's; a picker tile passes
    // whatever fits its box.
    property real cellScale: 1

    // Cap on the decoded image, in sheet pixels. These sheets are commonly
    // 1536x2288, which is 14 MB of RGBA decoded, and a picker with a dozen
    // pets in it would otherwise ask for all of them at full size at once.
    // Zero asks for the sheet as authored, which is what the desktop pet
    // wants because the size slider can ask for it.
    property int sourceHeight: 0

    // Cell size is worked out here rather than read straight off the
    // manifest, because a manifest whose format fixes the grid states
    // neither. Dividing the loaded image by the grid is also what lets one
    // of those sheets be exported at any resolution and still land right.
    readonly property real cellWidth: {
        const explicit = root.manifest?.frame?.width ?? 0;
        if (explicit > 0)
            return explicit;
        const columns = root.manifest?.columns ?? 0;
        return columns > 0 ? sheet.implicitWidth / columns : 0;
    }

    readonly property real cellHeight: {
        const explicit = root.manifest?.frame?.height ?? 0;
        if (explicit > 0)
            return explicit;
        const rows = root.manifest?.rows ?? 0;
        return rows > 0 ? sheet.implicitHeight / rows : 0;
    }

    readonly property bool ready: root.manifest !== null && sheet.status === Image.Ready && root.cellWidth > 0 && root.cellHeight > 0

    readonly property var accent: root.manifest?.accent ?? null

    // The shader draws whenever it is usable, tinting or not: `strength`
    // at 0 is an exact passthrough, so a pet with no accent and a pet
    // whose retint is switched off both go the same way and there is no
    // second draw path to keep in step.
    //
    // A .qsb missing from the plugin, or built against a different Qt than
    // the one running, reports Error instead of Compiled, and the plain
    // viewport below draws untinted. `status` is not Compiled until the
    // item has rendered once, so this is never read from
    // Component.onCompleted.
    readonly property bool shaded: root.ready && tint.status === ShaderEffect.Compiled

    implicitWidth: root.cellWidth * root.cellScale
    implicitHeight: root.cellHeight * root.cellScale

    // Drawn directly when there is no shader, and sampled into the effect
    // below when there is -- in which case it is marked invisible,
    // because a ShaderEffectSource does not hide a source it is only
    // sampling and the sheet would otherwise paint underneath the tinted
    // copy at full size.
    Item {
        id: viewport

        visible: root.ready && !root.shaded
        width: root.cellWidth * root.cellScale
        height: root.cellHeight * root.cellScale
        clip: true
        transform: Scale {
            origin.x: viewport.width / 2
            xScale: root.facing
        }

        Image {
            id: sheet

            source: root.manifest ? PetLibrary.urlFor(root.petName, root.manifest) : ""
            asynchronous: true
            cache: true
            smooth: root.manifest?.smooth ?? true
            // Height only, so the aspect ratio is Qt's problem and
            // implicitWidth still divides by the column count.
            sourceSize.height: root.sourceHeight
            width: sheet.implicitWidth * root.cellScale
            height: sheet.implicitHeight * root.cellScale
            x: -root.column * root.cellWidth * root.cellScale
            y: -root.row * root.cellHeight * root.cellScale
        }
    }

    // A ShaderEffectSource renders its source item's own subtree, and the
    // source item's transform is not part of that -- so the mirror is
    // applied again on the way out rather than inherited from the
    // viewport.
    ShaderEffectSource {
        id: cell

        width: viewport.width
        height: viewport.height
        sourceItem: viewport
        live: true
        visible: false
    }

    ShaderEffect {
        id: tint

        width: viewport.width
        height: viewport.height
        visible: root.shaded
        blending: true
        fragmentShader: Qt.resolvedUrl("shaders/pet-accent.frag.qsb")
        transform: Scale {
            origin.x: tint.width / 2
            xScale: root.facing
        }

        readonly property var source: cell
        readonly property color accent: Colours.palette.m3primary
        readonly property real hueFrom: root.accent?.from ?? 0
        readonly property real hueTo: root.accent?.to ?? 0
        readonly property real hueFeather: root.accent?.feather ?? 0
        readonly property real minSat: root.accent?.minSat ?? 1
        readonly property real refSat: root.accent?.refSat ?? 1
        readonly property real strength: root.accent && PetLibrary.tinted ? 1 : 0
    }
}
