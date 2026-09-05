// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.components
import qs.services

// The built-in pet: an anglerfish, drawn as vector paths off the live
// palette so it retints with the theme instead of sitting on the
// desktop as a foreign sprite.
//
// Silhouette is deliberately front-heavy (a big rounded head tapering
// to a short tail) rather than the symmetric oval a generic fish
// reads as, with an open, toothed mouth and a few spiny dorsal rays
// instead of a flowing fin -- those three details are what actually
// separate "anglerfish" from "fish" at this size, more than the lure
// alone (the previous version had the lure and still read as a
// regular fish).
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
    readonly property color toothColour: root.eyeColour
    readonly property color mouthColour: Qt.darker(root.bodyBottom, 1.7)

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

            // Three short dorsal spines rather than one flowing fin --
            // deep-sea anglerfish carry bony rays, not the sweeping
            // dorsal a goldfish silhouette reads as.
            ShapePath {
                fillColor: root.finColour
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 30
                startY: 26
                PathLine {
                    x: 33
                    y: 14
                }
                PathLine {
                    x: 36
                    y: 26
                }
                PathLine {
                    x: 30
                    y: 26
                }
            }

            ShapePath {
                fillColor: root.finColour
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 42
                startY: 22
                PathLine {
                    x: 45
                    y: 10
                }
                PathLine {
                    x: 48
                    y: 22
                }
                PathLine {
                    x: 42
                    y: 22
                }
            }

            ShapePath {
                fillColor: root.finColour
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 54
                startY: 20
                PathLine {
                    x: 57
                    y: 9
                }
                PathLine {
                    x: 60
                    y: 20
                }
                PathLine {
                    x: 54
                    y: 20
                }
            }

            // Small forked tail fin at the rear (low-x) tip, in place of
            // the old large flared fin that made the body read as an
            // even, symmetric oval.
            ShapePath {
                fillColor: root.finColour
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 18
                startY: 44

                PathQuad {
                    controlX: 8
                    controlY: 30
                    x: 4
                    y: 34
                }

                PathLine {
                    x: 14
                    y: 44
                }

                PathQuad {
                    controlX: 8
                    controlY: 58
                    x: 4
                    y: 54
                }

                PathLine {
                    x: 18
                    y: 44
                }
            }

            // Small pectoral fin, underside.
            ShapePath {
                fillColor: root.finColour
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 46
                startY: 58
                PathLine {
                    x: 36
                    y: 70
                }
                PathLine {
                    x: 50
                    y: 64
                }
                PathLine {
                    x: 46
                    y: 58
                }
            }

            // Main body: a big rounded head (high x) tapering to a
            // narrow rear point (low x), with a concave notch cut into
            // the front-lower silhouette for the open mouth.
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
                startX: 18
                startY: 44

                PathCubic {
                    control1X: 24
                    control1Y: 18
                    control2X: 54
                    control2Y: 8
                    x: 72
                    y: 20
                }

                PathCubic {
                    control1X: 84
                    control1Y: 26
                    control2X: 83
                    control2Y: 44
                    x: 78
                    y: 52
                }

                PathCubic {
                    control1X: 68
                    control1Y: 55
                    control2X: 68
                    control2Y: 60
                    x: 78
                    y: 64
                }

                PathCubic {
                    control1X: 62
                    control1Y: 76
                    control2X: 28
                    control2Y: 70
                    x: 18
                    y: 44
                }
            }

            // Mouth line, traced directly over the body's own concave
            // notch (the two control points above match) so the bite
            // reads as a real opening rather than just a smooth curve.
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.mouthColour
                strokeWidth: 2.5
                capStyle: ShapePath.RoundCap
                startX: 78
                startY: 50

                PathCubic {
                    control1X: 68
                    control1Y: 55
                    control2X: 68
                    control2Y: 60
                    x: 78
                    y: 64
                }
            }

            // Jagged teeth along the mouth line.
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.toothColour
                strokeWidth: 1.3
                capStyle: ShapePath.RoundCap
                startX: 76
                startY: 51

                PathLine {
                    x: 71
                    y: 53.5
                }
                PathLine {
                    x: 76
                    y: 55
                }
                PathLine {
                    x: 69
                    y: 57
                }
                PathLine {
                    x: 76
                    y: 59
                }
                PathLine {
                    x: 71
                    y: 61.5
                }
                PathLine {
                    x: 77
                    y: 63
                }
            }

            // Illicium: arcs up and forward off the top of the head,
            // then hooks back down so the esca dangles in front of the
            // face, above the mouth -- not off to the side as a plain
            // antenna.
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.lureColour
                strokeWidth: 2.5
                capStyle: ShapePath.RoundCap
                startX: 70
                startY: 18

                PathCubic {
                    control1X: 80
                    control1Y: 14
                    control2X: 84
                    control2Y: 20
                    x: 74
                    y: 28
                }

                PathCubic {
                    control1X: 68
                    control1Y: 34
                    control2X: 64
                    control2Y: 30
                    x: 62
                    y: 36
                }
            }
        }

        // Esca (the lure's glowing tip), dangling in front of the mouth.
        Rectangle {
            x: 62 - width / 2
            y: 36 - height / 2
            width: 17 + root.excitement * 9
            height: width
            radius: width / 2
            color: Qt.alpha(root.lureColour, 0.14 + root.excitement * 0.3)
        }

        Rectangle {
            x: 62 - width / 2
            y: 36 - height / 2
            width: 8 + root.excitement * 2.5
            height: width
            radius: width / 2
            color: root.lureColour
        }

        // Small eye, high on the forehead -- anglerfish eyes read as
        // modest next to the head, not the dominant feature a cartoon
        // fish's big round eye usually is.
        Rectangle {
            visible: !root.blinking
            x: 59
            y: 19
            width: 8
            height: 8
            radius: width / 2
            color: root.eyeColour

            Rectangle {
                x: 2.6
                y: 2
                width: 4
                height: 4
                radius: width / 2
                color: root.pupilColour
            }
        }

        Rectangle {
            visible: root.blinking
            x: 59
            y: 22
            width: 8
            height: 2.2
            radius: 1.1
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

            x: 54 + snooze.index * 9
            y: 10 - snooze.index * 9
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
