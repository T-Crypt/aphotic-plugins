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

    // Quota windows, and whether they still describe now. The record is
    // only rewritten while a harness session is live, so an old one is
    // unknown rather than zero -- and a window whose reset has already
    // passed rolled over without anyone writing the new figure.
    readonly property var quota: AgentProviders.quotaOf(AgentEvents.activeHarness || "claude")
    readonly property bool quotaFresh: AgentProviders.quotaCapturedAt > 0 && (root.now - AgentProviders.quotaCapturedAt) < AgentProviders.quotaMaxAgeSeconds

    readonly property var quotaBars: {
        if (!root.quotaFresh)
            return [];
        const bars = [];
        for (const [key, label] of [["fiveHour", qsTr("5h")], ["sevenDay", qsTr("7d")], ["context", qsTr("Context")]]) {
            const w = root.quota[key];
            if (!w)
                continue;
            if (w.resetsAt > 0 && root.now >= w.resetsAt)
                continue;
            bars.push({
                label: label,
                percent: w.usedPercent,
                resetsAt: w.resetsAt ?? 0
            });
        }
        return bars;
    }

    // One clock for every countdown, and only while the tile exists --
    // a notch tile is built when the notch opens and destroyed when it
    // closes, so this does not tick on a desktop nobody is looking at.
    // Minute granularity is all the labels show, so 30s is plenty.
    property int now: Math.floor(Date.now() / 1000)

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Math.floor(Date.now() / 1000)
    }

    function formatReset(resetsAt: int): string {
        if (resetsAt <= 0)
            return "";
        const minutes = Math.max(0, Math.round((resetsAt - root.now) / 60));
        if (minutes < 60)
            return qsTr("%1m").arg(minutes);
        const hours = Math.floor(minutes / 60);
        if (hours < 24)
            return qsTr("%1h %2m").arg(hours).arg(minutes % 60);
        return qsTr("%1d %2h").arg(Math.floor(hours / 24)).arg(hours % 24);
    }

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
        visible: root.quotaBars.length > 0 || root.hasUsage
    }

    // The harness's own account of what it has spent, which nothing else
    // on the machine knows: transcripts record tokens, never the share of
    // an allowance. Absent entirely until a session reports it.
    Repeater {
        model: root.quotaBars

        RowLayout {
            id: quotaRow

            required property var modelData

            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                Layout.preferredWidth: 48
                text: quotaRow.modelData.label
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
                elide: Text.ElideRight
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHigh

                StyledRect {
                    width: Math.max(parent.width * quotaRow.modelData.percent / 100, parent.height)
                    height: parent.height
                    radius: parent.radius
                    color: quotaRow.modelData.percent >= 90 ? Colours.palette.m3error : (quotaRow.modelData.percent >= 75 ? Colours.palette.m3tertiary : Colours.palette.m3primary)

                    Behavior on width {
                        Anim {}
                    }
                }
            }

            StyledText {
                text: qsTr("%1%").arg(Math.round(quotaRow.modelData.percent))
                color: Colours.palette.m3onSurface
                font: Tokens.font.mono.small
            }

            StyledText {
                visible: text !== ""
                text: root.formatReset(quotaRow.modelData.resetsAt)
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.mono.small
            }
        }
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
