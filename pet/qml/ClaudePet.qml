// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services
import qs.modules.plugins.pet

// A starburst that blinks: eleven tapered rays around a centre, in the
// primary accent, with a pair of eyes on top.
//
// One ray is drawn once and the Repeater rotates a copy of it into each
// slot, rather than eleven hand-placed paths: the mark is radially
// symmetric, so eleven sets of coordinates would be ten chances to get one
// of them slightly wrong.
//
// Everything visible is a pure function of `mood`, `phase`, `facing` and
// `excitement`. No timer, no animation.
Item {
    id: root

    required property string mood
    required property real phase
    required property real excitement
    required property int facing

    readonly property int rays: 11
    readonly property real centreX: 42
    readonly property real centreY: 44

    readonly property bool asleep: root.mood === "sleep"
    readonly property bool held: root.mood === "held"
    readonly property bool blinking: root.asleep || (root.mood === "fidget" && (root.phase < 0.15 || (root.phase > 0.3 && root.phase < 0.45)))
    readonly property real stride: root.mood === "walk" ? Math.sin(root.phase * 4) : 0

    readonly property color rayColour: root.asleep ? Qt.alpha(Colours.palette.m3primary, 0.55) : Colours.palette.m3primary
    readonly property color sclera: Colours.contrastOn(Colours.palette.m3primary)
    readonly property color pupil: Qt.darker(Colours.palette.m3primary, 2.6)

    implicitWidth: 84
    implicitHeight: 88

    Item {
        id: body

        width: root.width
        height: root.height
        rotation: root.stride * 10
        scale: 1 + root.excitement * 0.12 + (root.held ? 0.06 : 0)
        transformOrigin: Item.Center
        transform: Scale {
            origin.x: body.width / 2
            xScale: root.facing
        }

        Repeater {
            model: root.rays

            Item {
                id: ray

                required property int index

                anchors.fill: parent
                rotation: ray.index * (360 / root.rays)
                transformOrigin: Item.Center

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: root.rayColour
                        strokeWidth: 0
                        strokeColor: "transparent"
                        startX: root.centreX - 8
                        startY: root.centreY

                        PathQuad {
                            controlX: root.centreX - 7
                            controlY: root.centreY - 30
                            x: root.centreX
                            y: root.centreY - 38
                        }
                        PathQuad {
                            controlX: root.centreX + 7
                            controlY: root.centreY - 30
                            x: root.centreX + 8
                            y: root.centreY
                        }
                        PathLine {
                            x: root.centreX - 8
                            y: root.centreY
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: !root.blinking
            x: root.centreX - 12
            y: root.centreY - 8
            width: 9
            height: 11
            radius: 4.5
            color: root.sclera

            Rectangle {
                x: 2 + root.stride
                y: 3
                width: 5
                height: 6
                radius: 2.5
                color: root.pupil
            }
        }

        Rectangle {
            visible: !root.blinking
            x: root.centreX + 3
            y: root.centreY - 8
            width: 9
            height: 11
            radius: 4.5
            color: root.sclera

            Rectangle {
                x: 2 + root.stride
                y: 3
                width: 5
                height: 6
                radius: 2.5
                color: root.pupil
            }
        }

        Rectangle {
            visible: root.blinking
            x: root.centreX - 12
            y: root.centreY - 2
            width: 9
            height: 2.4
            radius: 1.2
            color: root.sclera
        }

        Rectangle {
            visible: root.blinking
            x: root.centreX + 3
            y: root.centreY - 2
            width: 9
            height: 2.4
            radius: 1.2
            color: root.sclera
        }
    }

    PetSnooze {
        x: 60
        y: -8
        asleep: root.asleep
    }
}
