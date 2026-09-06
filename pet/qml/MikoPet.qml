// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services
import qs.modules.plugins.pet

// The default built-in pet: a small shrine girl, drawn as vector paths off
// the live palette exactly the way the orb is, so she wears the theme
// rather than sitting on the desktop as a foreign sprite. Hair takes the
// primary accent and the hakama and her ribbon the tertiary, so no theme
// can put her in a single colour.
//
// Skin and robe are the two things not taken straight from a role. A
// palette role that lands on grey or green stops reading as a person at
// all, and a robe taken from whatever contrasts with the hair goes black
// under half the themes, which on a dark wallpaper leaves a head and a
// skirt with nothing between them. Both are fixed warm tones with a little
// of the accent tinted through: enough to belong to the theme, not enough
// to leave the character behind.
//
// She is built to move. The previous drawing was a stack of rectangles
// that rotated slightly as a single block, which is why a walk looked like
// a lean -- so limbs now swing from their joints, and the hair swings
// after them rather than with them. That lag is most of what separates a
// character who is walking from a picture that is tilting: hair, ribbon
// and the long side locks all read the stride a beat late.
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
    readonly property bool walking: root.mood === "walk"
    readonly property bool reacting: root.mood === "react"

    // Two blinks in a fidget, and eyes shut for the whole nap.
    readonly property bool blinking: root.asleep || (root.mood === "fidget" && (root.phase < 0.13 || (root.phase > 0.34 && root.phase < 0.47)))

    // The stride drives every limb. Arms take it inverted, so they swing
    // opposite the legs the way arms actually do.
    readonly property real stride: root.walking ? Math.sin(root.phase * 7.5) : 0

    // The same wave, a beat behind. Hair has mass; it arrives late and
    // overshoots, and that delay is the whole trick.
    readonly property real lag: root.walking ? Math.sin(root.phase * 7.5 - 1.1) : (root.held ? Math.sin(root.phase * 5 - 0.8) * 0.85 : Math.sin(root.phase * 2.1 - 0.7) * 0.35)

    // A slow breath while she is standing still, and a faster one while
    // she is being carried.
    readonly property real breath: root.held ? Math.sin(root.phase * 5) * 1.4 : (root.walking || root.reacting ? 0 : Math.sin(root.phase * 2.1) * 0.9)

    // Both feet leave the ground twice a cycle, which is what stops a walk
    // reading as a shuffle.
    readonly property real bounce: root.walking ? Math.abs(Math.sin(root.phase * 7.5)) * 2.2 : 0

    // React is a wave: the near arm comes up and flaps. Excitement falls
    // from 1 to 0 across the beat, so it also lets the arm back down.
    readonly property real waveLift: root.reacting ? root.excitement : 0
    readonly property real waveFlap: root.reacting ? Math.sin(root.phase * 16) * 16 * root.excitement : 0

    readonly property real slump: root.asleep ? 4 : 0

    readonly property color hair: Colours.palette.m3primary
    readonly property color hairShade: Qt.darker(Colours.palette.m3primary, 1.4)
    readonly property color hairLight: Qt.lighter(Colours.palette.m3primary, 1.22)
    readonly property color robe: Qt.tint("#f7f2ee", Qt.alpha(Colours.palette.m3primary, 0.18))
    readonly property color robeShade: Qt.darker(root.robe, 1.12)
    readonly property color hakama: Colours.palette.m3tertiary
    readonly property color hakamaShade: Qt.darker(Colours.palette.m3tertiary, 1.4)
    readonly property color skin: Qt.tint("#f2d4c0", Qt.alpha(Colours.palette.m3primary, 0.12))
    readonly property color skinShade: Qt.darker(root.skin, 1.1)
    readonly property color line: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
    readonly property color eyeColour: Qt.tint(Colours.contrastOn(root.skin), Qt.alpha(Colours.palette.m3primary, 0.35))
    readonly property color eyeWhite: "#fbfdff"
    readonly property color blush: Qt.alpha(Colours.palette.m3error, 0.34)
    readonly property color ribbon: Colours.palette.m3tertiaryOnSurface

    implicitWidth: 84
    implicitHeight: 112

    // One eye. Written once and placed twice, because two hand-copied eyes
    // drift apart the moment either is touched.
    component Eye: Item {
        id: eye

        required property color white
        required property color iris
        required property color skinTone
        required property bool shut
        required property real tilt

        width: 15
        height: 16

        // Shutting scales the whole eye down to a slit rather than drawing
        // a separate closed state, so the lashes and the highlight land in
        // the right place on the way down.
        transform: Scale {
            origin.x: eye.width / 2
            origin.y: eye.height / 2
            yScale: eye.shut ? 0.08 : 1
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: eye.white
        }

        Rectangle {
            width: 11
            height: 12
            radius: width / 2
            color: eye.iris
            x: 2
            y: 3 + eye.tilt
        }

        Rectangle {
            width: 5
            height: 5
            radius: width / 2
            color: "#10141c"
            x: 5
            y: 7 + eye.tilt
        }

        // Two highlights, a big one high and a small one low. One alone
        // reads as a glass bead.
        Rectangle {
            width: 4.5
            height: 4.5
            radius: width / 2
            color: "#ffffff"
            x: 3.5
            y: 4 + eye.tilt
        }

        Rectangle {
            width: 2.2
            height: 2.2
            radius: width / 2
            color: Qt.alpha("#ffffff", 0.75)
            x: 8.5
            y: 10.5 + eye.tilt
        }
    }

    // A closed eye: one curved lash line, drawn only while she is blinking
    // so the slit above has something to read as.
    component Lashes: Shape {
        id: lashes

        required property color ink

        width: 15
        height: 6
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: lashes.ink
            strokeWidth: 1.6
            capStyle: ShapePath.RoundCap
            startX: 1
            startY: 2

            PathQuad {
                x: 14
                y: 2
                controlX: 7.5
                controlY: 6.5
            }
        }
    }

    Item {
        id: body

        width: root.width
        height: root.height
        y: -root.bounce + root.breath + root.slump
        transformOrigin: Item.Bottom
        transform: Scale {
            origin.x: body.width / 2
            xScale: root.facing
        }

        // --- behind everything: the long back hair --------------------
        //
        // It reaches the hem and swings on the lag rather than the stride,
        // pivoting from the crown so the ends travel furthest.
        Shape {
            preferredRendererType: Shape.CurveRenderer
            anchors.fill: parent
            transformOrigin: Item.Top
            rotation: root.lag * 3.2
            y: 0

            ShapePath {
                fillColor: root.hairShade
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 20
                startY: 30

                // Out over the shoulders, down to a soft point near the
                // hem, and back up the other side.
                PathCubic {
                    x: 13
                    y: 74
                    control1X: 10
                    control1Y: 46
                    control2X: 11
                    control2Y: 60
                }
                PathCubic {
                    x: 42
                    y: 88
                    control1X: 17
                    control1Y: 86
                    control2X: 30
                    control2Y: 88
                }
                PathCubic {
                    x: 71
                    y: 74
                    control1X: 54
                    control1Y: 88
                    control2X: 67
                    control2Y: 86
                }
                PathCubic {
                    x: 64
                    y: 30
                    control1X: 73
                    control1Y: 60
                    control2X: 74
                    control2Y: 46
                }
                PathLine {
                    x: 20
                    y: 30
                }
            }
        }

        // --- far limbs, behind the torso ------------------------------
        Rectangle {
            id: farLeg

            width: 9
            height: 22
            radius: 4.5
            color: root.skinShade
            x: 36
            y: 86
            transformOrigin: Item.Top
            rotation: -root.stride * 17
        }

        Rectangle {
            width: 8
            height: 20
            radius: 4
            color: root.skinShade
            x: 20
            y: 62
            transformOrigin: Item.Top
            rotation: 6 - root.stride * 20
        }

        // --- near leg -------------------------------------------------
        Rectangle {
            id: nearLeg

            width: 9
            height: 22
            radius: 4.5
            color: root.skin
            x: 44
            y: 86
            transformOrigin: Item.Top
            rotation: root.stride * 17
        }

        // --- hakama ---------------------------------------------------
        //
        // Drawn after the legs so the hem covers where they join, and
        // flared by the stride so the skirt lifts on the swing.
        Shape {
            preferredRendererType: Shape.CurveRenderer
            anchors.fill: parent

            ShapePath {
                fillColor: root.hakama
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 27
                startY: 66

                PathLine {
                    x: 57
                    y: 66
                }
                PathCubic {
                    x: 64 + root.stride * 2
                    y: 92
                    control1X: 60
                    control1Y: 76
                    control2X: 63
                    control2Y: 84
                }
                PathQuad {
                    x: 20 - root.stride * 2
                    y: 92
                    controlX: 42
                    controlY: 97
                }
                PathCubic {
                    x: 27
                    y: 66
                    control1X: 21
                    control1Y: 84
                    control2X: 24
                    control2Y: 76
                }
            }

            // A single fold, which is all the hakama needs at this size to
            // stop reading as a cone.
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.hakamaShade
                strokeWidth: 1.4
                capStyle: ShapePath.RoundCap
                startX: 42
                startY: 68

                PathLine {
                    x: 42 + root.stride * 1.5
                    y: 90
                }
            }
        }

        // --- torso ----------------------------------------------------
        Shape {
            preferredRendererType: Shape.CurveRenderer
            anchors.fill: parent

            ShapePath {
                fillColor: root.robe
                strokeWidth: 0
                strokeColor: "transparent"
                startX: 28
                startY: 56

                PathLine {
                    x: 56
                    y: 56
                }
                PathLine {
                    x: 58
                    y: 70
                }
                PathLine {
                    x: 26
                    y: 70
                }
                PathLine {
                    x: 28
                    y: 56
                }
            }

            // The collar: two strokes meeting in a V, the one detail that
            // makes the robe a robe.
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.hakamaShade
                strokeWidth: 2.2
                capStyle: ShapePath.RoundCap
                startX: 34
                startY: 56

                PathLine {
                    x: 42
                    y: 66
                }
                PathLine {
                    x: 50
                    y: 56
                }
            }
        }

        // --- near arm -------------------------------------------------
        //
        // Swings against the legs while walking, and comes up over the
        // shoulder to wave when poked.
        Rectangle {
            id: nearArm

            width: 8
            height: 20
            radius: 4
            color: root.skin
            x: 55
            y: 62
            transformOrigin: Item.Top
            rotation: root.reacting ? -150 + root.waveFlap : (root.held ? -28 : -6 + root.stride * 20)
        }

        // --- head -----------------------------------------------------
        Item {
            id: head

            width: root.width
            height: root.height
            transformOrigin: Item.Bottom
            // A small counter-rotation against the stride: the head stays
            // level while the body swings, which is what people do.
            rotation: root.asleep ? 6 : -root.stride * 1.8

            Rectangle {
                width: 52
                height: 50
                radius: 24
                color: root.skin
                x: 16
                y: 12
            }

            Rectangle {
                width: 11
                height: 8
                radius: 4
                color: root.blush
                x: 20
                y: 42
            }

            Rectangle {
                width: 11
                height: 8
                radius: 4
                color: root.blush
                x: 53
                y: 42
            }

            Eye {
                x: 24
                y: 30
                white: root.eyeWhite
                iris: root.eyeColour
                skinTone: root.skin
                shut: root.blinking
                tilt: root.asleep ? 1.5 : 0
            }

            Eye {
                x: 45
                y: 30
                white: root.eyeWhite
                iris: root.eyeColour
                skinTone: root.skin
                shut: root.blinking
                tilt: root.asleep ? 1.5 : 0
            }

            Lashes {
                x: 24
                y: 35
                ink: root.line
                visible: root.blinking
            }

            Lashes {
                x: 45
                y: 35
                ink: root.line
                visible: root.blinking
            }

            // Mouth: a small open smile awake, a flat line asleep.
            Shape {
                preferredRendererType: Shape.CurveRenderer
                anchors.fill: parent

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.line
                    strokeWidth: 1.5
                    capStyle: ShapePath.RoundCap
                    startX: 39
                    startY: 51

                    PathQuad {
                        x: 45
                        y: 51
                        controlX: 42
                        controlY: root.asleep ? 51 : (root.reacting ? 56 : 54)
                    }
                }
            }

            // --- side locks --------------------------------------------
            //
            // The pair that frames the face, drawn before the fringe so
            // the bangs cover where they start -- on top, they read as
            // pointed ears. They hang past the jaw and swing furthest of
            // anything, because they are the lightest thing on her.
            Shape {
                preferredRendererType: Shape.CurveRenderer
                anchors.fill: parent
                transformOrigin: Item.Top
                rotation: root.lag * 4.5

                ShapePath {
                    fillColor: root.hair
                    strokeWidth: 0
                    strokeColor: "transparent"
                    startX: 16
                    startY: 26

                    PathCubic {
                        x: 20
                        y: 70
                        control1X: 10
                        control1Y: 44
                        control2X: 14
                        control2Y: 60
                    }
                    PathQuad {
                        x: 23
                        y: 40
                        controlX: 24
                        controlY: 58
                    }
                    PathLine {
                        x: 16
                        y: 26
                    }
                }

                ShapePath {
                    fillColor: root.hair
                    strokeWidth: 0
                    strokeColor: "transparent"
                    startX: 68
                    startY: 26

                    PathCubic {
                        x: 64
                        y: 70
                        control1X: 74
                        control1Y: 44
                        control2X: 70
                        control2Y: 60
                    }
                    PathQuad {
                        x: 61
                        y: 40
                        controlX: 60
                        controlY: 58
                    }
                    PathLine {
                        x: 68
                        y: 26
                    }
                }
            }

            // --- fringe, over the face ---------------------------------
            //
            // Swings on the lag like the back hair but half as far, so the
            // bangs settle before the long hair does.
            Shape {
                preferredRendererType: Shape.CurveRenderer
                anchors.fill: parent
                transformOrigin: Item.Top
                rotation: root.lag * 1.6

                ShapePath {
                    fillColor: root.hair
                    strokeWidth: 0
                    strokeColor: "transparent"
                    startX: 14
                    startY: 40

                    // Crown.
                    PathCubic {
                        x: 70
                        y: 40
                        control1X: 14
                        control1Y: 2
                        control2X: 70
                        control2Y: 2
                    }
                    // Back across the brow in soft scallops. Sharp points
                    // here read as horns rather than as bangs, and the
                    // whole edge sits above the eyes so it frames the face
                    // instead of covering it.
                    PathLine {
                        x: 67
                        y: 28
                    }
                    PathQuad {
                        x: 54
                        y: 33
                        controlX: 62
                        controlY: 33
                    }
                    PathQuad {
                        x: 42
                        y: 28
                        controlX: 48
                        controlY: 33
                    }
                    PathQuad {
                        x: 30
                        y: 33
                        controlX: 36
                        controlY: 33
                    }
                    PathQuad {
                        x: 17
                        y: 28
                        controlX: 23
                        controlY: 33
                    }
                    PathLine {
                        x: 14
                        y: 40
                    }
                }

                // A highlight band across the crown. Hair without one at
                // this size is a flat shape the eye reads as a hat.
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.alpha(root.hairLight, 0.75)
                    strokeWidth: 2.6
                    capStyle: ShapePath.RoundCap
                    startX: 26
                    startY: 19

                    PathQuad {
                        x: 56
                        y: 19
                        controlX: 41
                        controlY: 13
                    }
                }
            }

            // --- the ribbon --------------------------------------------
            //
            // Sits off-centre on the crown rather than dead top, which was
            // the old drawing's propeller. It swings hardest of all.
            Item {
                x: 54
                y: 14
                width: 18
                height: 12
                transformOrigin: Item.BottomLeft
                rotation: -14 + root.lag * 7

                Shape {
                    preferredRendererType: Shape.CurveRenderer
                    anchors.fill: parent

                    ShapePath {
                        fillColor: root.ribbon
                        strokeWidth: 0
                        strokeColor: "transparent"
                        startX: 9
                        startY: 6

                        PathCubic {
                            x: 0
                            y: 1
                            control1X: 5
                            control1Y: 0
                            control2X: 0
                            control2Y: -3
                        }
                        PathCubic {
                            x: 9
                            y: 6
                            control1X: 0
                            control1Y: 6
                            control2X: 4
                            control2Y: 7
                        }
                    }

                    ShapePath {
                        fillColor: root.ribbon
                        strokeWidth: 0
                        strokeColor: "transparent"
                        startX: 9
                        startY: 6

                        PathCubic {
                            x: 18
                            y: 1
                            control1X: 13
                            control1Y: 0
                            control2X: 18
                            control2Y: -3
                        }
                        PathCubic {
                            x: 9
                            y: 6
                            control1X: 18
                            control1Y: 6
                            control2X: 14
                            control2Y: 7
                        }
                    }
                }

                Rectangle {
                    width: 5
                    height: 5
                    radius: 2.5
                    color: Qt.darker(root.ribbon, 1.25)
                    x: 6.5
                    y: 3.5
                }
            }
        }
    }

    // Little sparks on a poke, thrown from the shoulders outward.
    Repeater {
        model: 4

        Rectangle {
            id: spark

            required property int index

            readonly property real spread: 1 - root.excitement

            width: 4
            height: 4
            radius: 2
            rotation: 45
            color: root.ribbon
            visible: root.excitement > 0.01
            opacity: root.excitement * 0.9
            x: 42 + (spark.index % 2 === 0 ? -1 : 1) * (14 + spark.spread * 20) - width / 2
            y: 34 + Math.floor(spark.index / 2) * 16 - spark.spread * 16
        }
    }

    PetSnooze {
        x: 62
        y: -20
        asleep: root.asleep
    }
}
