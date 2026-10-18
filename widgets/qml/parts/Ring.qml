// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Shapes
import qs.services

// An arc meter: a faint full ring and a lit arc for `value` (0-1).
Shape {
    id: root

    property real value: 0
    property real thickness: 6
    property color colour: Colours.signal
    property color track: Colours.signalStyle.hairline
    property real startAngle: -90
    property real sweep: 360

    readonly property real radius: Math.max(0, Math.min(root.width, root.height) / 2 - root.thickness / 2)

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: root.track
        strokeWidth: root.thickness
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap

        PathAngleArc {
            centerX: root.width / 2
            centerY: root.height / 2
            radiusX: root.radius
            radiusY: root.radius
            startAngle: root.startAngle
            sweepAngle: root.sweep
        }
    }

    ShapePath {
        strokeColor: root.colour
        strokeWidth: root.thickness
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap

        PathAngleArc {
            centerX: root.width / 2
            centerY: root.height / 2
            radiusX: root.radius
            radiusY: root.radius
            startAngle: root.startAngle
            sweepAngle: root.sweep * Math.max(0, Math.min(1, root.value))
        }
    }
}
