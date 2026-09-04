// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.services
import qs.modules.plugins.visualizer

// The plugin side of one `overlay` surface. Core owns the
// PluginOverlayWindow and its geometry; this is only what is drawn
// inside it, so the root is an Item and nothing here resizes anything.
Item {
    id: root

    // The host masks its window to this. A zero-size item means an empty
    // input region, so the full-width strip along the bottom of every
    // screen keeps handing its clicks to the desktop underneath. The
    // spectrum has nothing to click and the bars come and go with the
    // music, so masking to them would only make the dead zone flicker.
    readonly property Item maskItem: passthrough

    Item {
        id: passthrough

        width: 0
        height: 0
    }

    Loader {
        active: root.visible

        sourceComponent: SpectrumWatch {}
    }

    SpectrumBars {
        anchors.fill: parent

        count: CavaSpectrum.barCount
        levels: CavaSpectrum.levels
        lowColour: Colours.palette.m3primary
        highColour: Colours.palette.m3tertiary

        opacity: CavaSpectrum.quiet ? 0 : 1
        visible: opacity > 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
