// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.config
import qs.components
import qs.services
import qs.services.profile
import qs.modules.plugins.securityNotchTile

ColumnLayout {
    id: root

    readonly property string owner: "security-notch-tile-" + Math.random()
    readonly property bool attention: root.posture === "Exposed"

    function stripAddr(addr: string): string {
        return String(addr ?? "").replace(/^\[|\]$/g, "").replace(/%.*$/, "");
    }

    function isLoopback(addr: string): bool {
        const a = root.stripAddr(addr);
        return a === "" || a.startsWith("127.") || a === "::1";
    }

    // 100.64.0.0/10 and the tailnet's fd7a:115c:a1e0::/48, or anything
    // bound to the tailscale interface by name.
    function isTailnet(addr: string): bool {
        if (String(addr ?? "").includes("%tailscale"))
            return true;
        const a = root.stripAddr(addr);
        const m = /^100\.(\d+)\./.exec(a);
        if (m && Number(m[1]) >= 64 && Number(m[1]) <= 127)
            return true;
        return a.toLowerCase().startsWith("fd7a:115c:a1e0:");
    }

    readonly property var publicListeners: {
        const list = [];
        // UDP sockets on ephemeral ports are clients, not services.
        for (const l of SecurityService.tcpListeners.concat(SecurityService.udpListeners.filter(u => Number(u.port) < 32768))) {
            if (!l || root.isLoopback(l.addr) || root.isTailnet(l.addr))
                continue;
            const a = root.stripAddr(l.addr);
            list.push({ proto: l.proto, addr: l.addr, port: l.port, proc: l.proc, wild: a === "0.0.0.0" || a === "*" || a === "::" });
        }
        return list;
    }

    // Exposed means something listens beyond loopback and the tailnet, or
    // the firewall is readable and holds no table. A firewall that needs
    // root to read is unknown, not open.
    readonly property bool noFirewall: SecurityService.fwReadable && SecurityService.fwTableCount === 0
    readonly property string posture: SecurityService.engagementToken !== "" ? "Engaged" : (root.publicListeners.length > 0 || root.noFirewall ? "Exposed" : "Shielded")
    readonly property string postureReason: {
        if (root.posture === "Engaged")
            return SecurityService.engagementLabel || qsTr("engagement running");
        if (root.posture === "Exposed") {
            const parts = [];
            if (root.publicListeners.length > 0)
                parts.push(qsTr("%n service(s) listening beyond loopback and the tailnet", "", root.publicListeners.length));
            if (root.noFirewall)
                parts.push(qsTr("no firewall rules"));
            return parts.join(", ");
        }
        return qsTr("nothing listens beyond loopback and the tailnet");
    }

    property real now: Date.now()

    function elapsed(): string {
        if (SecurityService.engagementToken === "")
            return "";
        const s = Math.max(0, Math.floor((root.now - SecurityService.engagementStart) / 1000));
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const sec = s % 60;
        const pad = n => n < 10 ? "0" + n : String(n);
        return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
    }

    onVisibleChanged: {
        SecurityService.setSurfaceVisible(root.owner, visible);
        if (visible)
            SecurityService.refreshAdvisories();
    }
    Component.onCompleted: {
        SecurityService.setSurfaceVisible(root.owner, visible);
        if (visible)
            SecurityService.refreshAdvisories();
    }
    Component.onDestruction: SecurityService.setSurfaceVisible(root.owner, false)

    spacing: Tokens.spacing.small

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: root.posture === "Engaged" ? "security" : root.posture === "Exposed" ? "warning" : "shield"
            color: root.posture === "Exposed" ? Colours.palette.m3error : root.posture === "Engaged" ? Colours.palette.m3primaryOnSurface : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.large
            fill: root.posture === "Shielded" ? 0 : 1
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.posture
                color: Colours.palette.m3onSurface
                font: Tokens.font.title.builders.medium.weight(Font.Medium).build()
            }

            StyledText {
                Layout.fillWidth: true
                text: root.postureReason
                color: root.attention ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        StyledRect {
            implicitWidth: badge.implicitWidth + Tokens.padding.small * 2
            implicitHeight: 20
            radius: Tokens.rounding.full
            color: root.attention ? Colours.palette.m3error : Colours.palette.m3secondaryContainer

            StyledText {
                id: badge
                anchors.centerIn: parent
                text: root.attention ? "exposed" : "ok"
                color: root.attention ? Colours.palette.m3onError : Colours.palette.m3onSecondaryContainer
                font: Tokens.font.label.small
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
    }

    // VPN
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            text: "VPN"
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: Vpn.connected ? (Vpn.activeConnections.length > 0 ? (Vpn.activeConnections[0].name || "connected") : "connected") : "disconnected"
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                visible: Vpn.busy
                text: "busy"
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }

        Repeater {
            model: Vpn.connections

            RowLayout {
                id: connRow
                required property var modelData
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: connRow.modelData.name
                    color: connRow.modelData.active ? Colours.palette.m3primaryOnSurface : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                StyledRect {
                    implicitWidth: connBtn.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: 22
                    radius: Tokens.rounding.full
                    color: connRow.modelData.active ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh

                    StyledText {
                        id: connBtn
                        anchors.centerIn: parent
                        text: connRow.modelData.active ? "disconnect" : "connect"
                        color: connRow.modelData.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        onClicked: {
                            if (connRow.modelData.active)
                                Vpn.disconnectProvider(connRow.modelData.provider, connRow.modelData.id);
                            else
                                Vpn.connectProvider(connRow.modelData.provider, connRow.modelData.id);
                        }
                    }
                }
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
        visible: root.publicListeners.length > 0 || SecurityService.tcpListeners.length > 0 || SecurityService.udpListeners.length > 0
    }

    // Exposure
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.publicListeners.length > 0
        spacing: Tokens.spacing.extraSmall

        StyledText {
            text: "Public listeners"
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        Repeater {
            model: root.publicListeners.slice(0, 10)

            ColumnLayout {
                id: pubRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: pubRow.modelData.proto
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.mono.small
                    }

                    StyledText {
                        text: pubRow.modelData.addr + ":" + pubRow.modelData.port
                        color: pubRow.modelData.wild ? Colours.palette.m3error : Colours.palette.m3onSurface
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: pubRow.modelData.proc || ""
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
        visible: SecurityService.fwReadable || (!SecurityService.fwReadable && true)
    }

    // Firewall
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            text: "Firewall"
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        StyledText {
            text: SecurityService.fwReadable ? (SecurityService.fwTableCount + " tables") : "needs root to read"
            color: SecurityService.fwReadable ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
        visible: SecurityService.sshEstablished.length > 0
    }

    // Sessions
    ColumnLayout {
        Layout.fillWidth: true
        visible: SecurityService.sshEstablished.length > 0
        spacing: Tokens.spacing.extraSmall

        StyledText {
            text: "SSH established"
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        Repeater {
            model: SecurityService.sshEstablished.slice(0, 10)

            StyledText {
                id: sshRow
                required property var modelData
                text: sshRow.modelData.rAddr
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
    }

    // Advisories
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            text: "Advisories"
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        StyledText {
            text: !SecurityService.advisoriesFetched ? qsTr("checking…") : !SecurityService.advisoriesOk ? qsTr("arch-audit not available") : SecurityService.advisoriesCount > 0 ? qsTr("%n vulnerable package(s) have fixes", "", SecurityService.advisoriesCount) : qsTr("none with fixes pending")
            color: Colours.palette.m3onSurface
            font: Tokens.font.body.small
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
    }

    // Engagement
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            text: "Engagement"
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !(SecurityService.engagementToken !== "")
            spacing: Tokens.spacing.small

            TextField {
                id: engageField
                placeholderText: "label"
                Layout.fillWidth: true
                font: Tokens.font.body.small
            }

            StyledRect {
                implicitWidth: startBtn.implicitWidth + Tokens.padding.small * 2
                implicitHeight: 22
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHigh

                StyledText {
                    id: startBtn
                    anchors.centerIn: parent
                    text: "Start engagement"
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.label.small
                }

                StateLayer {
                    onClicked: {
                        if (engageField.text.length > 0) {
                            SecurityService.startEngagement(engageField.text);
                            engageField.text = "";
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: (SecurityService.engagementToken !== "")
            spacing: Tokens.spacing.small

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: SecurityService.engagementLabel
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                StyledText {
                    text: root.elapsed()
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.mono.small
                }
            }

            StyledRect {
                implicitWidth: endBtn.implicitWidth + Tokens.padding.small * 2
                implicitHeight: 22
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHigh

                StyledText {
                    id: endBtn
                    anchors.centerIn: parent
                    text: "End"
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.label.small
                }

                StateLayer {
                    onClicked: SecurityService.endEngagement()
                }
            }
        }
    }

    Timer {
        running: root.visible && SecurityService.engagementToken !== ""
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }
}
