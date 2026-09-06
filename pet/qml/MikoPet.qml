// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services
import qs.modules.plugins.pet

// The default built-in pet: a small shrine girl, drawn as vector paths off
// the live palette exactly the way the anglerfish is, so she wears the
// theme rather than sitting on the desktop as a foreign sprite. Hair takes
// the primary accent and the hakama and her ribbon the tertiary, so no
// theme can put her in one colour.
//
// Skin and robe are the two things not taken straight from a role. A
// palette role that lands on grey or green stops reading as a person at
// all, and a robe taken from whatever contrasts with the hair goes black
// under half the themes, which on a dark wallpaper leaves a head and a
// skirt with nothing between them. Both are fixed warm tones with a little
// of the accent tinted through: enough to belong to the theme, not enough
// to leave the character behind.
//
// Everything visible is a pure function of `mood`, `phase`, `facing` and
// `excitement`, all pushed in by Pet.qml's brain. Nothing here holds a
// timer or an animation, so the whole tree is silent between beats.
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

    readonly property color hair: Colours.palette.m3primary
    readonly property color hairShade: Qt.darker(Colours.palette.m3primary, 1.35)
    readonly property color robe: Qt.tint("#f7f2ee", Qt.alpha(Colours.palette.m3primary, 0.18))
    readonly property color hakama: Colours.palette.m3tertiary
    readonly property color hakamaShade: Qt.darker(Colours.palette.m3tertiary, 1.4)
    readonly property color skin: Qt.tint("#f2d4c0", Qt.alpha(Colours.palette.m3primary, 0.12))
    readonly property color line: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
    readonly property color eyeColour: Qt.tint(Colours.contrastOn(root.skin), Qt.alpha(Colours.palette.m3primary, 0.35))
    readonly property color blush: Qt.alpha(Colours.palette.m3error, 0.34)
    readonly property color ribbon: Colours.palette.m3tertiaryOnSurface

    implicitWidth: 84
    implicitHeight: 112

    Item {
        id: body

        width: root.width
        height: root.height
        y: Math.abs(root.stride) * 1.6
        rotation: root.held ? 3 : root.stride * 1.6
        transformOrigin: Item.Bottom
        transform: Scale {
            origin.x: body.width / 2
            xScale: root.facing
        }

        // Twin tails, each carrying its own tie as a child so the tie
        // swings with the hair rather than beside it.
        Rectangle {
            x: 6
            y: 28
            width: 15
            height: 50
            radius: 7.5
            color: root.hairShade
            transformOrigin: Item.Top
            rotation: -7 - root.stride * 3

            Rectangle {
                x: -2
                y: 15
                width: 19
                height: 5
                radius: 2.5
                color: root.ribbon
            }
        }

        Rectangle {
            x: 63
            y: 28
            width: 15
            height: 50
            radius: 7.5
            color: root.hairShade
            transformOrigin: Item.Top
            rotation: 7 + root.stride * 3

            Rectangle {
                x: -2
                y: 15
                width: 19
                height: 5
                radius: 2.5
                color: root.ribbon
            }
        }

        Rectangle {
            x: 12
            y: 8
            width: 60
            height: 52
            radius: 26
            color: root.hairShade
        }

        // Legs before the hakama, so the skirt covers where they join.
        Rectangle {
            x: 33
            y: 97 + root.stride * 2
            width: 7
            height: 9
            color: root.skin
        }

        Rectangle {
            x: 44
            y: 97 - root.stride * 2
            width: 7
            height: 9
            color: root.skin
        }

        Rectangle {
            x: 31
            y: 105 + root.stride * 2
            width: 11
            height: 5
            radius: 2
            color: root.hakamaShade
        }

        Rectangle {
            x: 42
            y: 105 - root.stride * 2
            width: 11
            height: 5
            radius: 2
            color: root.hakamaShade
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Hakama.
            ShapePath {
                fillColor: root.hakama
                strokeColor: root.line
                strokeWidth: 1
                startX: 26
                startY: 78

                PathLine {
                    x: 58
                    y: 78
                }
                PathLine {
                    x: 63
                    y: 99
                }
                PathLine {
                    x: 21
                    y: 99
                }
                PathLine {
                    x: 26
                    y: 78
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.hakamaShade
                strokeWidth: 1.2
                startX: 36
                startY: 80

                PathLine {
                    x: 33
                    y: 98
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.hakamaShade
                strokeWidth: 1.2
                startX: 48
                startY: 80

                PathLine {
                    x: 51
                    y: 98
                }
            }

            // Robe, over the waist of the hakama.
            ShapePath {
                fillColor: root.robe
                strokeColor: root.line
                strokeWidth: 1
                startX: 30
                startY: 58

                PathLine {
                    x: 54
                    y: 58
                }
                PathLine {
                    x: 58
                    y: 80
                }
                PathLine {
                    x: 26
                    y: 80
                }
                PathLine {
                    x: 30
                    y: 58
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.hakama
                strokeWidth: 3
                capStyle: ShapePath.RoundCap
                startX: 34
                startY: 58

                PathLine {
                    x: 42
                    y: 70
                }
                PathLine {
                    x: 50
                    y: 58
                }
            }
        }

        Rectangle {
            x: 25
            y: 74
            width: 34
            height: 6
            color: root.hakamaShade
        }

        Rectangle {
            x: 17
            y: 60
            width: 13
            height: 22
            radius: 6
            color: root.robe
        }

        Rectangle {
            x: 54
            y: 60
            width: 13
            height: 22
            radius: 6
            color: root.robe
        }

        Rectangle {
            x: 18
            y: 79
            width: 9
            height: 9
            radius: 4.5
            color: root.skin
        }

        Rectangle {
            x: 57
            y: 79
            width: 9
            height: 9
            radius: 4.5
            color: root.skin
        }

        Rectangle {
            x: 18
            y: 12
            width: 48
            height: 48
            radius: 23
            color: root.skin
            border.width: 1
            border.color: root.line
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Fringe. The lower edge runs back right-to-left as an
            // alternating zigzag, which is what makes it read as bangs
            // rather than as a helmet.
            ShapePath {
                fillColor: root.hair
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 18
                startY: 34

                PathCubic {
                    control1X: 19
                    control1Y: 16
                    control2X: 28
                    control2Y: 8
                    x: 42
                    y: 8
                }
                PathCubic {
                    control1X: 56
                    control1Y: 8
                    control2X: 65
                    control2Y: 16
                    x: 66
                    y: 34
                }
                PathLine {
                    x: 60
                    y: 26
                }
                PathLine {
                    x: 54
                    y: 34
                }
                PathLine {
                    x: 47
                    y: 24
                }
                PathLine {
                    x: 40
                    y: 34
                }
                PathLine {
                    x: 33
                    y: 25
                }
                PathLine {
                    x: 26
                    y: 33
                }
                PathLine {
                    x: 18
                    y: 34
                }
            }

            ShapePath {
                fillColor: root.hair
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 19
                startY: 26

                PathCubic {
                    control1X: 13
                    control1Y: 38
                    control2X: 12
                    control2Y: 50
                    x: 15
                    y: 60
                }
                PathLine {
                    x: 25
                    y: 52
                }
                PathCubic {
                    control1X: 22
                    control1Y: 42
                    control2X: 21
                    control2Y: 34
                    x: 19
                    y: 26
                }
            }

            ShapePath {
                fillColor: root.hair
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 65
                startY: 26

                PathCubic {
                    control1X: 71
                    control1Y: 38
                    control2X: 72
                    control2Y: 50
                    x: 69
                    y: 60
                }
                PathLine {
                    x: 59
                    y: 52
                }
                PathCubic {
                    control1X: 62
                    control1Y: 42
                    control2X: 63
                    control2Y: 34
                    x: 65
                    y: 26
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.darker(root.skin, 2)
                strokeWidth: 1.6
                capStyle: ShapePath.RoundCap
                startX: 39
                startY: 50

                PathQuad {
                    controlX: 42
                    controlY: 54
                    x: 45
                    y: 50
                }
            }

            // Hair ribbon, last so it sits over the fringe it is tied
            // into. Both wings are outlined, because a bow the same
            // brightness as the hair it is tied into is not a bow.
            ShapePath {
                fillColor: root.ribbon
                strokeColor: root.line
                strokeWidth: 1
                startX: 62
                startY: 12

                PathQuad {
                    controlX: 74
                    controlY: 0
                    x: 77
                    y: 6
                }
                PathQuad {
                    controlX: 79
                    controlY: 13
                    x: 62
                    y: 12
                }
            }

            ShapePath {
                fillColor: root.ribbon
                strokeColor: root.line
                strokeWidth: 1
                startX: 60
                startY: 12

                PathQuad {
                    controlX: 48
                    controlY: 1
                    x: 45
                    y: 7
                }
                PathQuad {
                    controlX: 43
                    controlY: 14
                    x: 60
                    y: 12
                }
            }
        }

        Rectangle {
            x: 57
            y: 8
            width: 8
            height: 8
            radius: 4
            color: Qt.darker(root.ribbon, 1.25)
            border.width: 1
            border.color: root.line
        }

        Rectangle {
            visible: !root.blinking
            x: 28
            y: 31
            width: 11
            height: 14
            radius: 5.5
            color: root.eyeColour

            Rectangle {
                x: 2.5
                y: 2.5
                width: 4.5
                height: 4.5
                radius: 2.25
                color: root.robe
            }

            Rectangle {
                x: 6
                y: 9
                width: 2.6
                height: 2.6
                radius: 1.3
                color: Qt.alpha(root.robe, 0.75)
            }
        }

        Rectangle {
            visible: !root.blinking
            x: 45
            y: 31
            width: 11
            height: 14
            radius: 5.5
            color: root.eyeColour

            Rectangle {
                x: 2.5
                y: 2.5
                width: 4.5
                height: 4.5
                radius: 2.25
                color: root.robe
            }

            Rectangle {
                x: 6
                y: 9
                width: 2.6
                height: 2.6
                radius: 1.3
                color: Qt.alpha(root.robe, 0.75)
            }
        }

        Rectangle {
            visible: root.blinking
            x: 28
            y: 38
            width: 11
            height: 2.4
            radius: 1.2
            color: root.eyeColour
        }

        Rectangle {
            visible: root.blinking
            x: 45
            y: 38
            width: 11
            height: 2.4
            radius: 1.2
            color: root.eyeColour
        }

        Rectangle {
            x: 21
            y: 46
            width: 9
            height: 5
            radius: 2.5
            color: root.blush
        }

        Rectangle {
            x: 54
            y: 46
            width: 9
            height: 5
            radius: 2.5
            color: root.blush
        }
    }

    // Outside `body`, so neither the facing flip nor the walk tilt reaches
    // them. Placed around the head rather than in a row, so a poke reads
    // as delight and not as a loading indicator.
    Repeater {
        model: [
            {
                x: 4,
                y: 22,
                size: 8
            },
            {
                x: 38,
                y: -4,
                size: 6
            },
            {
                x: 72,
                y: 30,
                size: 7
            }
        ]

        Rectangle {
            id: spark

            required property var modelData

            x: spark.modelData.x
            y: spark.modelData.y
            width: spark.modelData.size
            height: spark.modelData.size
            radius: 1.5
            rotation: 45
            color: root.ribbon
            opacity: root.excitement * 0.9
            visible: root.excitement > 0.01
        }
    }

    PetSnooze {
        x: 62
        y: -20
        asleep: root.asleep
    }
}
