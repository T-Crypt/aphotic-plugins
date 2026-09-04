// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.components
import qs.services

// The built-in pet: a small lantern fish, drawn as vector paths off the
// live palette so it retints with the theme instead of sitting on the
// desktop as a foreign sprite.
//
// Every visible property is a pure function of `mood`, `phase`,
// `facing` and `excitement`, all pushed in by Pet.qml's brain. Nothing
// here holds a timer or an animation, so this whole tree is silent
// between beats.
Item {
    id: root

    required property string mood
    required property real phase
    required property real excitement
    required property int facing

    readonly property bool asleep: root.mood === "sleep"
    readonly property bool blinking: root.asleep || (root.mood === "fidget" && (root.phase < 0.15 || (root.phase > 0.3 && root.phase < 0.45)))
    readonly property real swim: root.mood === "walk" ? Math.sin(root.phase * 7.5) : 0

    readonly property color bodyTop: Colours.palette.m3primary
    readonly property color bodyBottom: Qt.tint(Colours.palette.m3surfaceContainerHigh, Qt.alpha(Colours.palette.m3primary, 0.55))
    readonly property color finColour: Qt.alpha(Colours.palette.m3tertiary, 0.72)
    readonly property color rimColour: Qt.alpha(Colours.palette.m3outlineVariant, 0.55)
    readonly property color lureColour: Colours.palette.m3tertiaryOnSurface
    readonly property color eyeColour: Colours.contrastOn(root.bodyTop)
    readonly property color pupilColour: Colours.contrastOn(root.eyeColour)

    implicitWidth: 86
    implicitHeight: 78

    Item {
        id: body

        width: root.width
        height: root.height
        y: root.swim * 2.2
        rotation: root.swim * 2.5
        transformOrigin: Item.Center
        transform: Scale {
            origin.x: body.width / 2
            xScale: root.facing
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: root.finColour
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 28
                startY: 44

                PathLine {
                    x: 7
                    y: 22
                }

                PathQuad {
                    controlX: 19
                    controlY: 44
                    x: 7
                    y: 66
                }

                PathLine {
                    x: 28
                    y: 44
                }
            }

            ShapePath {
                fillColor: root.finColour
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 36
                startY: 26

                PathQuad {
                    controlX: 44
                    controlY: 5
                    x: 57
                    y: 22
                }

                PathLine {
                    x: 36
                    y: 26
                }
            }

            ShapePath {
                fillGradient: LinearGradient {
                    x1: 0
                    y1: 16
                    x2: 0
                    y2: 68

                    GradientStop {
                        position: 0
                        color: root.bodyTop
                    }

                    GradientStop {
                        position: 1
                        color: root.bodyBottom
                    }
                }
                strokeColor: root.rimColour
                strokeWidth: 1.5
                startX: 27
                startY: 44

                PathCubic {
                    control1X: 31
                    control1Y: 20
                    control2X: 58
                    control2Y: 15
                    x: 76
                    y: 39
                }

                PathCubic {
                    control1X: 81
                    control1Y: 44
                    control2X: 80
                    control2Y: 49
                    x: 73
                    y: 55
                }

                PathCubic {
                    control1X: 57
                    control1Y: 70
                    control2X: 33
                    control2Y: 63
                    x: 27
                    y: 44
                }
            }

            ShapePath {
                fillColor: root.finColour
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 43
                startY: 52

                PathQuad {
                    controlX: 51
                    controlY: 68
                    x: 62
                    y: 57
                }

                PathQuad {
                    controlX: 53
                    controlY: 56
                    x: 43
                    y: 52
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.lureColour
                strokeWidth: 2.5
                capStyle: ShapePath.RoundCap
                startX: 61
                startY: 24

                PathCubic {
                    control1X: 70
                    control1Y: 21
                    control2X: 76
                    control2Y: 18
                    x: 77
                    y: 11
                }
            }
        }

        Rectangle {
            x: 77 - width / 2
            y: 11 - height / 2
            width: 17 + root.excitement * 9
            height: width
            radius: width / 2
            color: Qt.alpha(root.lureColour, 0.14 + root.excitement * 0.3)
        }

        Rectangle {
            x: 77 - width / 2
            y: 11 - height / 2
            width: 8 + root.excitement * 2.5
            height: width
            radius: width / 2
            color: root.lureColour
        }

        Rectangle {
            visible: !root.blinking
            x: 58
            y: 34
            width: 11
            height: 11
            radius: width / 2
            color: root.eyeColour

            Rectangle {
                x: 3.6
                y: 3
                width: 5
                height: 5
                radius: width / 2
                color: root.pupilColour
            }
        }

        Rectangle {
            visible: root.blinking
            x: 58
            y: 39
            width: 11
            height: 2.4
            radius: 1.2
            color: root.eyeColour
        }
    }

    // Outside `body` on purpose: the facing flip is a horizontal mirror,
    // and a mirrored glyph reads as a rendering fault rather than a pet
    // facing the other way.
    Repeater {
        model: 3

        StyledText {
            id: snooze

            required property int index

            x: 46 + snooze.index * 9
            y: 18 - snooze.index * 9
            text: "z"
            color: Colours.palette.m3onSurfaceVariant
            opacity: root.asleep ? 0.8 - snooze.index * 0.22 : 0
            font.pixelSize: 11 + snooze.index * 2

            Behavior on opacity {
                Anim {
                    type: Anim.SlowEffects
                }
            }
        }
    }
}
