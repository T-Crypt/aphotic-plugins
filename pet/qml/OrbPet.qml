// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services
import qs.modules.plugins.pet

// Aphotid: the light in the dark. A glowing orb rather than a creature,
// drawn as vector paths off the live palette so the thing the whole shell
// is named after takes the accent colour rather than shipping its own.
//
// It replaced an anglerfish. The fish was a joke about the name; the orb
// is the name itself, and it survives retinting in a way a fish never did
// -- a wallust palette landing on green gave you a green fish, where a
// green orb is just a green light.
//
// Five layers, back to front: a wide bloom, a tighter one, the shaded core
// sphere, energy ribbons wrapping it, and motes orbiting outside. The
// bloom is most of what sells it -- an orb without one is a circle. The
// ribbons are tilted rings rather than level ones, because level rings
// read as a beach ball, and tilted ones that cross read as energy.
//
// Every visible property is a pure function of `mood`, `phase`, `facing`
// and `excitement`, all pushed in by Pet.qml's brain. Nothing here holds a
// timer or an animation, so between beats this whole tree is silent and
// the orb is a still picture -- which is the point: an ambient light that
// repainted at the display rate forever would be the idle-GPU regression
// (E2-08) all over again.
Item {
    id: root

    required property string mood
    required property real phase
    required property real excitement
    required property int facing

    readonly property bool asleep: root.mood === "sleep"

    readonly property real mid: 46

    // How far round the swirl has turned. Ribbons and motes read it at
    // different rates so they never settle into a single spoke.
    readonly property real spin: root.phase * 2.4

    // One slow breath in the bloom. Asleep it sits lower and shallower,
    // which is the orb guttering rather than pulsing.
    readonly property real pulse: root.asleep ? 0.86 + Math.sin(root.phase * 1.1) * 0.03 : 1 + Math.sin(root.phase * 2.6) * 0.05 + root.excitement * 0.2

    // A walk drags the motes a little behind the direction of travel, so
    // the orb reads as being carried rather than sliding.
    readonly property real drift: root.mood === "walk" ? -Math.sin(root.phase * 6.4) * 2.6 * root.facing : 0

    // Asleep dims by going deeper, not by going transparent. Fading the
    // whole thing towards the wallpaper turns a dark-blue light into a
    // pale grey smudge; darkening the ramp keeps it a light that is low.
    readonly property real glowAlpha: root.asleep ? 0.46 : 0.85 + root.excitement * 0.3

    // The accent is the light. Everything else is that colour at another
    // brightness, so a single-accent theme still reads as a lamp.
    readonly property color accent: Colours.palette.m3primary
    readonly property color glow: root.asleep ? Qt.darker(root.accent, 1.3) : root.accent
    readonly property color hot: root.asleep ? Qt.lighter(root.glow, 1.3) : Qt.tint(root.glow, Qt.rgba(1, 1, 1, 0.8))
    readonly property color warm: Qt.lighter(root.glow, 1.3)
    readonly property color deep: Qt.darker(root.glow, 1.9)
    readonly property color ribbon: root.asleep ? Qt.darker(Colours.palette.m3tertiary, 1.4) : Colours.palette.m3tertiary
    readonly property color mote: Colours.palette.m3tertiaryOnSurface

    implicitWidth: 92
    implicitHeight: 92

    // The wide bloom. Reaches the edge of the item and is nearly all
    // falloff, which is the part that makes the orb look lit rather than
    // merely round.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.glowAlpha
        transform: Scale {
            origin.x: root.mid
            origin.y: root.mid
            xScale: root.pulse
            yScale: root.pulse
        }

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: root.mid
                centerY: root.mid
                centerRadius: 46
                focalX: root.mid
                focalY: root.mid

                GradientStop {
                    position: 0.0
                    color: Qt.alpha(root.glow, 0.5)
                }
                GradientStop {
                    position: 0.45
                    color: Qt.alpha(root.glow, 0.22)
                }
                GradientStop {
                    position: 0.75
                    color: Qt.alpha(root.glow, 0.07)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.alpha(root.glow, 0)
                }
            }

            PathAngleArc {
                centerX: root.mid
                centerY: root.mid
                radiusX: 46
                radiusY: 46
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    // The tighter bloom, hugging the core. Two of these rather than one
    // wide gradient because a single falloff either hangs too close or
    // washes the whole box out; stacking gives a hot skirt and a soft edge.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.glowAlpha
        transform: Scale {
            origin.x: root.mid
            origin.y: root.mid
            xScale: root.pulse
            yScale: root.pulse
        }

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: root.mid
                centerY: root.mid
                centerRadius: 32
                focalX: root.mid
                focalY: root.mid

                GradientStop {
                    position: 0.0
                    color: Qt.alpha(root.hot, 0.45)
                }
                GradientStop {
                    position: 0.6
                    color: Qt.alpha(root.glow, 0.35)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.alpha(root.glow, 0)
                }
            }

            PathAngleArc {
                centerX: root.mid
                centerY: root.mid
                radiusX: 32
                radiusY: 32
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    // Motes behind the core, so some of them pass out of sight round the
    // back and the orbit reads as an orbit rather than a ring.
    Repeater {
        model: 3

        Rectangle {
            id: backMote

            required property int index

            readonly property real angle: root.spin * 0.85 + backMote.index * 2.1 + 3.14
            readonly property real orbit: 30 + Math.sin(root.spin * 1.3 + backMote.index) * 3.5

            width: 3
            height: width
            radius: width / 2
            color: root.mote
            opacity: (root.asleep ? 0.16 : 0.4) * (0.6 + root.excitement * 0.4)
            x: root.mid + Math.cos(backMote.angle) * backMote.orbit - width / 2 + root.drift
            y: root.mid + Math.sin(backMote.angle) * backMote.orbit * 0.6 - height / 2
        }
    }

    // The core sphere. Its bright spot sits up and to the left of centre
    // rather than dead centre, which is the whole of what turns a flat
    // disc into a ball.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Scale {
            origin.x: root.mid
            origin.y: root.mid
            xScale: root.asleep ? 0.92 : 1 + root.excitement * 0.05
            yScale: root.asleep ? 0.92 : 1 + root.excitement * 0.05
        }

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: root.mid
                centerY: root.mid
                centerRadius: 21
                focalX: root.mid - 7
                focalY: root.mid - 8

                GradientStop {
                    position: 0.0
                    color: root.hot
                }
                GradientStop {
                    position: 0.32
                    color: root.warm
                }
                GradientStop {
                    position: 0.72
                    color: root.glow
                }
                GradientStop {
                    position: 1.0
                    color: root.deep
                }
            }

            PathAngleArc {
                centerX: root.mid
                centerY: root.mid
                radiusX: 21
                radiusY: 21
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    // Energy ribbons. Each is a ring tilted to its own angle and squashed
    // by its own phase, so they cross one another instead of stacking into
    // latitude lines. The squash is what swings a ring round the back of
    // the ball rather than spinning it flat like a hoop.
    Item {
        anchors.fill: parent
        opacity: root.asleep ? 0.42 : 0.95

        Repeater {
            model: 4

            Shape {
                id: band

                required property int index

                readonly property real turn: root.spin * 0.9 + band.index * 1.31
                readonly property real squash: Math.cos(band.turn)

                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: 0.3 + Math.abs(band.squash) * 0.55
                rotation: band.index * 47 + root.spin * 11
                transformOrigin: Item.Center

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: band.index % 2 === 0 ? root.ribbon : root.hot
                    strokeWidth: 1.5 + root.excitement * 0.7
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: root.mid
                        centerY: root.mid
                        radiusX: 20
                        radiusY: Math.max(1.5, Math.abs(band.squash) * 20)
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
            }
        }
    }

    // Rim light along the top-left, where the bright spot is. A gradient
    // alone leaves the edge mushy; this is the line that closes the sphere.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.asleep ? 0.38 : 0.7

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.hot
            strokeWidth: 1.6
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.mid
                centerY: root.mid
                radiusX: 20.5
                radiusY: 20.5
                startAngle: 186
                sweepAngle: 78
            }
        }
    }

    // The specular pip, faded rather than hard-edged: a crisp white shape
    // at this size reads as a chip out of the art, not a highlight.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.asleep ? 0.3 : 0.9

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: 37
                centerY: 35
                centerRadius: 7
                focalX: 37
                focalY: 35

                GradientStop {
                    position: 0.0
                    color: Qt.alpha(root.hot, 0.95)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.alpha(root.hot, 0)
                }
            }

            PathAngleArc {
                centerX: 37
                centerY: 35
                radiusX: 7
                radiusY: 7
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    // Motes in front. Brighter and a little larger than the ones behind,
    // which is the only depth cue an orbit this size gets.
    Repeater {
        model: 4

        Rectangle {
            id: frontMote

            required property int index

            readonly property real angle: root.spin * 0.85 + frontMote.index * 1.57
            readonly property real orbit: 30 + Math.sin(root.spin * 1.3 + frontMote.index) * 3.5

            width: root.excitement > 0.01 ? 4.4 : 3.6
            height: width
            radius: width / 2
            color: root.mote
            opacity: (root.asleep ? 0.22 : 0.95) * (0.75 + root.excitement * 0.25)
            x: root.mid + Math.cos(frontMote.angle) * frontMote.orbit - width / 2 + root.drift
            y: root.mid + Math.sin(frontMote.angle) * frontMote.orbit * 0.6 - height / 2
        }
    }

    // Poked, the orb throws a ring outward. It exists only while the react
    // beat is running, so it costs nothing the rest of the time.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.excitement > 0.01
        opacity: root.excitement * 0.6

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.hot
            strokeWidth: 1.6

            PathAngleArc {
                centerX: root.mid
                centerY: root.mid
                radiusX: 23 + (1 - root.excitement) * 20
                radiusY: 23 + (1 - root.excitement) * 20
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    PetSnooze {
        x: 62
        y: -12
        asleep: root.asleep
    }
}
