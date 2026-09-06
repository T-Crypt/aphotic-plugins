// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.services.ai
import qs.services.profile

// A notch tile, and nothing more: is a harness waiting on you, which one
// is working, how much it has spent today, and what the local provider is
// holding on the GPU. No node list, no topology, no replay -- that is
// Agent Graph's surface, folded from the same feed. The two are siblings
// under the `ai` layer and neither checks whether the other is installed.
//
// The subagent chip is a count, not a roster, for the same reason: how
// many are live is status, which belongs here; who spawned whom is a
// graph, which does not.
ColumnLayout {
    id: root

    // Read by the notch itself while this tile is off screen, which is
    // what puts a badge on the collapsed pill.
    readonly property bool attention: AgentEvents.anyWaiting

    readonly property var session: AgentEvents.activeSession
    readonly property int waitingCount: AgentEvents.waitingSessions.length

    function labelFor(harnessId: string): string {
        if (!harnessId)
            return "";
        return AgentRoles.entries.find(e => e.id === harnessId)?.label ?? harnessId;
    }

    readonly property string harnessLabel: root.labelFor(AgentEvents.activeHarness)

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

    readonly property var subagents: AgentEvents.activeSubagents

    // Usage for whichever harness is actually running, not a fixed
    // provider id: `usageOf` answers for any of them and returns zeros
    // for one with no transcripts on disk, which hides the row below
    // rather than showing a false zero.
    readonly property var usage: AgentProviders.usageOf(AgentEvents.activeHarness || "claude")
    readonly property bool hasUsage: root.usage.availability === "available" && root.usage.todayTokens > 0
    readonly property string topModel: root.usage.tokensByModel?.[0]?.model ?? ""

    readonly property var providerClaims: ResourceEngine.claimsOf("ollama")
    readonly property int providerVramMib: root.providerClaims.reduce((total, claim) => total + (claim.amount ?? 0), 0)

    function formatTokens(count: int): string {
        if (count >= 1000000)
            return qsTr("%1M").arg((count / 1000000).toFixed(1));
        if (count >= 1000)
            return qsTr("%1k").arg(Math.round(count / 1000));
        return String(count);
    }

    // What the shell knows about a session that the session cannot know
    // about itself, as plain text on the clipboard. Focus brings the
    // terminal forward; the paste is the user's, deliberately -- nothing
    // here types into a window, because a cwd match can be ambiguous and
    // synthetic keystrokes into the wrong window are unrecoverable.
    function focusAndCopy(session: var): void {
        if (!session)
            return;
        const lines = [qsTr("Aphotic session context")];
        const harness = root.labelFor(session.harness ?? "");
        if (harness)
            lines.push(qsTr("harness: %1").arg(harness));
        lines.push(qsTr("session: %1").arg(session.id));
        if (session.cwd)
            lines.push(qsTr("cwd: %1").arg(session.cwd));
        if (session.model)
            lines.push(qsTr("model: %1").arg(session.model));
        if (session.tool)
            lines.push(qsTr("last tool: %1").arg(session.tool));
        if (session.subagents?.length > 0)
            lines.push(qsTr("subagents: %1").arg(session.subagents.map(a => a.type || a.id).join(", ")));
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", lines.join("\n")]);
        AgentWindowFocus.focusByCwd(session.cwd ?? "");
    }

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
            implicitWidth: subagentLabel.implicitWidth + Tokens.padding.small * 2
            implicitHeight: 20
            radius: Tokens.rounding.full
            color: Colours.palette.m3surfaceContainerHigh
            visible: root.subagents.length > 0

            StyledText {
                id: subagentLabel

                anchors.centerIn: parent
                text: root.subagents.length > 1 ? qsTr("%1 subagents").arg(root.subagents.length) : qsTr("1 subagent")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.builders.small.weight(Font.Medium).build()
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

    // One row per session that stopped for input, and the tile's only
    // action: bring that session's terminal forward and put the shell's
    // own context on the clipboard for it. Not a session list -- it is
    // empty whenever nothing is waiting, which is most of the time.
    Repeater {
        model: AgentEvents.waitingSessions

        StyledRect {
            id: waitingRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: 28
            radius: Tokens.rounding.small
            color: Colours.palette.m3secondaryContainer

            StateLayer {
                anchors.fill: parent
                onClicked: root.focusAndCopy(waitingRow.modelData)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.small
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "keyboard_return"
                    color: Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: waitingRow.modelData.cwd || waitingRow.modelData.id
                    color: Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.label.medium
                    elide: Text.ElideMiddle
                }

                MaterialIcon {
                    text: "content_paste_go"
                    color: Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.small
                }
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
        visible: root.hasUsage
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.hasUsage
        spacing: Tokens.spacing.small

        StyledText {
            Layout.fillWidth: true
            text: root.topModel ? qsTr("Today — %1").arg(root.topModel) : qsTr("Today")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
            elide: Text.ElideRight
        }

        StyledText {
            text: qsTr("%1 tokens").arg(root.formatTokens(root.usage.todayTokens))
            color: Colours.palette.m3onSurface
            font: Tokens.font.mono.small
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
