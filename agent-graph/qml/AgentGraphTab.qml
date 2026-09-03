// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.agentGraph

StyledRect {
    id: root

    property bool replayMode: false

    readonly property bool gamingActive: AgentGraphService.gamingActive

    implicitWidth: 820
    implicitHeight: root.gamingActive ? 176 : (root.replayMode ? 620 : 520)
    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainer

    // Replay drives its own stepping timers off `playing`, and it lives
    // outside the Loader below, so leaving it running would keep folding
    // events for a scene that no longer exists.
    onGamingActiveChanged: {
        if (root.gamingActive)
            replay.pause();
    }

    Behavior on implicitHeight {
        Anim { type: Anim.EmphasizedSmall }
    }

    Binding {
        target: AgentGraphService
        property: "surfaceVisible"
        value: root.visible
    }

    GraphReplay {
        id: replay
        events: AgentGraphService.replayEvents
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                text: qsTr("Agent graph")
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
            }

            StyledText {
                Layout.fillWidth: true
                text: root.gamingActive
                    ? qsTr("suspended · %1 nodes recorded").arg(AgentGraphService.nodeCount)
                    : root.replayMode
                    ? (replay.loaded ? qsTr("replaying %1 events").arg(replay.events.length) : qsTr("pick a run"))
                    : !Settings.agentGraphEnabled
                        ? qsTr("paused · %1 nodes").arg(AgentGraphService.nodeCount)
                        : AgentGraphService.liveSessionCount === 0
                            ? qsTr("idle")
                            : qsTr("%1 live · %2 nodes").arg(AgentGraphService.liveSessionCount).arg(AgentGraphService.nodeCount)
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledRect {
                visible: !root.gamingActive
                implicitWidth: replayLabel.implicitWidth + Tokens.padding.medium
                implicitHeight: 24
                radius: Tokens.rounding.full
                color: root.replayMode ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.9)
                border.width: 1
                border.color: root.replayMode ? "transparent" : Colours.palette.m3outlineVariant

                RowLayout {
                    id: replayLabel

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        text: "history"
                        fontStyle: Tokens.font.icon.small
                        color: root.replayMode ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        text: qsTr("Replay")
                        font: Tokens.font.label.small
                        color: root.replayMode ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: {
                        root.replayMode = !root.replayMode;
                        if (root.replayMode)
                            AgentGraphService.refreshRuns();
                        else
                            replay.pause();
                    }
                }
            }

            StyledRect {
                implicitWidth: tierLabel.implicitWidth + Tokens.padding.medium
                implicitHeight: 24
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3primary, 0.16)

                StyledText {
                    id: tierLabel

                    anchors.centerIn: parent
                    text: AgentGraphService.tier
                    font: Tokens.font.label.small
                    color: Colours.palette.m3primary
                }
            }
        }

        // Unmounted rather than hidden while a game is up: the scene is
        // hundreds of Shapes and particle delegates plus a per-second clock
        // and an infinite flow animation, none of which stop costing
        // anything just because nothing is looking at them. The graph is
        // rebuilt from AgentGraphService.sessions on the way back, so the
        // only thing lost is zoom/pan and the held node positions.
        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: !root.gamingActive
            active: !root.gamingActive

            sourceComponent: GraphView {
                visible: root.visible
                sessions: root.replayMode ? replay.sessions : AgentGraphService.sessions
            }
        }

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: root.gamingActive
            active: root.gamingActive
            visible: active

            sourceComponent: StyledRect {
                implicitHeight: 104
                radius: Tokens.rounding.large
                color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.6)

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "sports_esports"
                        fontStyle: Tokens.font.icon.extraLarge
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Suspended for the gaming profile")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Agent events are still being recorded")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: root.replayMode && !root.gamingActive
            visible: active

            sourceComponent: ReplayBar {
                replay: replay
                onExited: {
                    root.replayMode = false;
                    replay.pause();
                }
            }
        }
    }
}
