// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.services.ai
import qs.services.profile

// A notch tile, and nothing more: is a harness waiting on you, which one
// is working, and what the local provider is holding on the GPU. No node
// list, no topology, no replay -- that is Agent Graph's surface, folded
// from the same feed. The two are siblings under the `ai` layer and
// neither checks whether the other is installed.
ColumnLayout {
    id: root

    // Read by the notch itself while this tile is off screen, which is
    // what puts a badge on the collapsed pill.
    readonly property bool attention: AgentEvents.anyWaiting

    readonly property var session: AgentEvents.activeSession
    readonly property int waitingCount: AgentEvents.waitingSessions.length

    readonly property string harnessLabel: {
        const id = AgentEvents.activeHarness;
        if (!id)
            return "";
        return AgentRoles.entries.find(e => e.id === id)?.label ?? id;
    }

    readonly property string phaseLabel: {
        if (root.waitingCount > 0)
            return qsTr("waiting for input");
        switch (AgentEvents.phase) {
        case "running":
            return qsTr("running");
        case "idle":
            return qsTr("idle");
        default:
            return qsTr("no session");
        }
    }

    readonly property var providerClaims: ResourceEngine.claimsOf("ollama")
    readonly property int providerVramMib: root.providerClaims.reduce((total, claim) => total + (claim.amount ?? 0), 0)

    // The hold, not a tail: AgentEvents owns the single reader of
    // agent-events.jsonl and runs it only while something is watching.
    // Object lifetime is the registration, so a tile behind a Loader
    // cannot leak the feed open by missing an unpaired call.
    Component.onCompleted: AgentEvents.hold("agent-notch-tile", true)
    Component.onDestruction: AgentEvents.hold("agent-notch-tile", false)

    spacing: Tokens.spacing.small

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: root.attention ? "notifications_active" : "smart_toy"
            color: root.attention ? Colours.palette.m3primary : (root.session ? Colours.palette.m3primaryOnSurface : Colours.palette.m3onSurfaceVariant)
            fontStyle: Tokens.font.icon.large
            fill: root.session ? 1 : 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.harnessLabel ? qsTr("%1 — %2").arg(root.harnessLabel).arg(root.phaseLabel) : qsTr("No agent session")
                color: root.session ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.title.builders.medium.weight(Font.Medium).build()
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: (root.session?.cwd ?? "") !== ""
                text: root.session?.cwd ?? ""
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideMiddle
            }
        }

        StyledRect {
            implicitWidth: waitingLabel.implicitWidth + Tokens.padding.small * 2
            implicitHeight: 20
            radius: Tokens.rounding.full
            color: Colours.palette.m3secondaryContainer
            visible: root.waitingCount > 0

            StyledText {
                id: waitingLabel

                anchors.centerIn: parent
                text: root.waitingCount > 1 ? qsTr("%1 waiting").arg(root.waitingCount) : qsTr("waiting")
                color: Colours.palette.m3onSecondaryContainer
                font: Tokens.font.label.builders.small.weight(Font.Medium).build()
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
        visible: root.providerClaims.length > 0
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.providerClaims.length > 0
        spacing: Tokens.spacing.extraSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Local provider VRAM")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
                elide: Text.ElideRight
            }

            StyledText {
                text: root.providerVramMib >= 1024 ? qsTr("%1 GiB").arg((root.providerVramMib / 1024).toFixed(1)) : qsTr("%1 MiB").arg(root.providerVramMib)
                color: Colours.palette.m3onSurface
                font: Tokens.font.mono.small
            }
        }

        Repeater {
            model: root.providerClaims

            StyledText {
                id: claimLabel

                required property var modelData

                Layout.fillWidth: true
                text: claimLabel.modelData.label || claimLabel.modelData.id
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }
        }
    }
}
