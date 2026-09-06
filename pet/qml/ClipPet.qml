// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services
import qs.modules.plugins.pet

// A bent paperclip with eyebrows, for anyone who has missed being watched
// while they type.
//
// One stroked path, no fills: a paperclip is wire, and drawing it as wire
// is what keeps it recognisable at 50 pixels across where a filled
// silhouette turns into a blob. The wire takes the primary accent; the
// eyes stay near-white with a little of the accent tinted through them,
// because googly eyes that follow the theme into dark grey stop reading as
// eyes.
//
// Everything visible is a pure function of `mood`, `phase`, `facing` and
// `excitement`. No timer, no animation.
Item {
    id: root

    required property string mood
    required property real phase
    required property real excitement
    required property int facing

    readonly property bool asleep: root.mood === "sleep"
    readonly property bool held: root.mood === "held"
    readonly property bool blinking: root.asleep || (root.mood === "fidget" && (root.phase < 0.15 || (root.phase > 0.3 && root.phase < 0.45)))
    readonly property real stride: root.mood === "walk" ? Math.sin(root.phase * 7.5) : 0
    readonly property real brow: root.excitement * 4 + (root.held ? 3 : 0)

    readonly property color wire: Colours.palette.m3primary
    readonly property color sclera: Qt.tint("#f4f4f6", Qt.alpha(Colours.palette.m3primary, 0.1))
    readonly property color pupil: Qt.darker(Colours.palette.m3primary, 3)

    implicitWidth: 50
    implicitHeight: 100

    Item {
        id: body

        width: root.width
        height: root.height
        rotation: root.held ? -6 : root.stride * 5
        transformOrigin: Item.Bottom
        transform: Scale {
            origin.x: body.width / 2
            xScale: root.facing
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.wire
                strokeWidth: 4.5
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: 10
                startY: 62

                PathLine {
                    x: 10
                    y: 22
                }
                PathQuad {
                    controlX: 10
                    controlY: 8
                    x: 25
                    y: 8
                }
                PathQuad {
                    controlX: 40
                    controlY: 8
                    x: 40
                    y: 22
                }
                PathLine {
                    x: 40
                    y: 74
                }
                PathQuad {
                    controlX: 40
                    controlY: 88
                    x: 29
                    y: 88
                }
                PathQuad {
                    controlX: 18
                    controlY: 88
                    x: 18
                    y: 76
                }
                PathLine {
                    x: 18
                    y: 26
                }
                PathQuad {
                    controlX: 18
                    controlY: 15
                    x: 25
                    y: 15
                }
                PathQuad {
                    controlX: 32
                    controlY: 15
                    x: 32
                    y: 26
                }
                PathLine {
                    x: 32
                    y: 60
                }
            }
        }

        // Brows, over the wire and above each eye. They lift on a poke and
        // stay lifted while the pet is in hand, which is the whole of this
        // pet's expression.
        Rectangle {
            visible: !root.asleep
            x: 9
            y: 17 - root.brow
            width: 11
            height: 2.6
            radius: 1.3
            color: root.pupil
            rotation: -14
        }

        Rectangle {
            visible: !root.asleep
            x: 30
            y: 17 - root.brow
            width: 11
            height: 2.6
            radius: 1.3
            color: root.pupil
            rotation: 14
        }

        Rectangle {
            x: 8
            y: 26
            width: 15
            height: 17
            radius: 8
            color: root.sclera
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

            Rectangle {
                visible: !root.blinking
                x: 5 + root.stride * 1.5
                y: 6
                width: 6
                height: 7
                radius: 3
                color: root.pupil
            }
        }

        Rectangle {
            x: 27
            y: 26
            width: 15
            height: 17
            radius: 8
            color: root.sclera
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

            Rectangle {
                visible: !root.blinking
                x: 5 + root.stride * 1.5
                y: 6
                width: 6
                height: 7
                radius: 3
                color: root.pupil
            }
        }

        Rectangle {
            visible: root.blinking
            x: 10
            y: 33
            width: 11
            height: 2.4
            radius: 1.2
            color: root.pupil
        }

        Rectangle {
            visible: root.blinking
            x: 29
            y: 33
            width: 11
            height: 2.4
            radius: 1.2
            color: root.pupil
        }
    }

    PetSnooze {
        x: 36
        y: -12
        asleep: root.asleep
    }
}
