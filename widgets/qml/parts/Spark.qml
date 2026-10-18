// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Shapes
import qs.services

// A line through `values`, scaled to the largest of them.
Shape {
    id: root

    property var values: []
    property color colour: Colours.signal
    property real lineWidth: 1.5
    property real floor: 1

    readonly property real peak: root.values.reduce((m, v) => Math.max(m, v), root.floor)

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: root.colour
        strokeWidth: root.lineWidth
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin

        PathPolyline {
            path: {
                const n = root.values.length;
                if (n < 2)
                    return [Qt.point(0, root.height), Qt.point(root.width, root.height)];
                const step = root.width / (n - 1);
                return root.values.map((v, i) => Qt.point(i * step, root.height - (v / root.peak) * (root.height - root.lineWidth) - root.lineWidth / 2));
            }
        }
    }
}
