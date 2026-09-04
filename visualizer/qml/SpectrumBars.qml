// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick

// Plain Rectangles, one per band, geometry-only per frame.
//
// A Canvas would rasterise the whole strip on the CPU and re-upload a
// full-width texture every frame; a ShaderEffect would need a .qsb built
// ahead of time, which a plugin loaded from a file:// URL has no build
// step to produce. Rectangles keep the per-frame work as scene-graph
// node updates, and the bars stop changing the moment the source goes
// quiet, which is where the cost actually goes to zero.
Item {
    id: root

    required property var levels
    required property int count

    property color lowColour
    property color highColour

    readonly property real pitch: root.count > 0 ? root.width / root.count : 0
    readonly property real barWidth: Math.max(2, root.pitch * 0.6)

    function tintAt(ramp: real): color {
        return Qt.rgba(root.lowColour.r + (root.highColour.r - root.lowColour.r) * ramp, root.lowColour.g + (root.highColour.g - root.lowColour.g) * ramp, root.lowColour.b + (root.highColour.b - root.lowColour.b) * ramp, 1);
    }

    Repeater {
        model: root.count

        Rectangle {
            id: bar

            required property int index

            readonly property real level: root.levels[bar.index] ?? 0
            readonly property real span: Math.max(root.barWidth, bar.level * root.height)

            x: root.pitch * (bar.index + 0.5) - root.barWidth / 2
            y: root.height - bar.span
            width: root.barWidth
            // The extra bar-width below the baseline is what rounds the
            // cap without rounding the foot: it falls outside the
            // overlay surface and is clipped by the window edge.
            height: bar.span + root.barWidth
            radius: root.barWidth / 2
            antialiasing: true
            color: root.tintAt(root.count > 1 ? bar.index / (root.count - 1) : 0)
            opacity: 0.45 + 0.55 * bar.level
        }
    }
}
