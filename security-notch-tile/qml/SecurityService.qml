// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.profile

Singleton {
    id: root

    readonly property string owner: "security-notch-tile"
    property var _visibleOwners: ({})

    // engagement state
    property string engagementToken: ""
    property string engagementLabel: ""
    property real engagementStart: 0

    // advisory cache
    property real advisoriesLast: 0
    property int advisoriesCount: 0
    property bool advisoriesFetched: false
    // False when arch-audit is missing or failed, so the tile says so
    // instead of reporting zero.
    property bool advisoriesOk: false

    // ss results cached while visible
    property var tcpListeners: []
    property var udpListeners: []
    property var sshEstablished: []

    // firewall info
    property bool fwReadable: false
    property int fwTableCount: 0

    function setSurfaceVisible(ownerId: string, on: bool): void {
        const next = Object.assign({}, root._visibleOwners);
        if (on)
            next[ownerId] = true;
        else
            delete next[ownerId];
        root._visibleOwners = next;
        if (Object.keys(root._visibleOwners).length === 0) {
            root._stopPolling();
        } else {
            root._startPolling();
        }
    }

    function _startPolling(): void {
        root._refreshSs();
        ssTimer.restart();
    }

    function _stopPolling(): void {
        ssTimer.stop();
    }

    function refreshAdvisories(): void {
        if (archAuditProc.running)
            return;
        if (Date.now() - root.advisoriesLast < 30 * 60 * 1000 && root.advisoriesFetched)
            return;
        root._runArchAudit();
    }

    function _runArchAudit(): void {
        archAuditProc.command = ["arch-audit", "-u", "-q"];
        archAuditProc.running = true;
    }

    property Timer ssTimer: Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: root._refreshSs()
    }

    function _refreshSs(): void {
        if (ssTcpProc.running || ssUdpProc.running)
            return;
        ssTcpProc.command = ["ss", "-Hltnp"];
        ssUdpProc.command = ["ss", "-Hlunp"];
        ssTcpProc.running = true;
        ssUdpProc.running = true;
    }

    function _parseSs(text: string, proto: string): var {
        const out = [];
        if (!text)
            return out;
        for (const line of text.split("\n")) {
            const parts = line.trim().split(/\s+/);
            if (parts.length < 4)
                continue;
            const state = parts[0];
            const addrPort = parts[3] || "";
            const idx = addrPort.lastIndexOf(":");
            if (idx <= 0)
                continue;
            let addr = addrPort.substring(0, idx);
            let port = addrPort.substring(idx + 1);
            if (proto === "udp" && parts[0] !== "UNCONN" && parts[0] !== "LISTEN")
                continue;
            let pid = 0;
            let proc = "";
            const pidIdx = line.indexOf("users:(");
            if (pidIdx >= 0) {
                const end = line.indexOf(")", pidIdx);
                const sub = end > pidIdx ? line.substring(pidIdx, end) : line.substring(pidIdx);
                const p = sub.match(/pid=(\d+)/);
                if (p)
                    pid = parseInt(p[1], 10);
                const nm = sub.match(/"([^"]+)"/);
                if (nm)
                    proc = nm[1];
            }
            out.push({ proto: proto, state: state, addr: addr, port: port, pid: pid, proc: proc, raw: line });
        }
        return out;
    }

    Process {
        id: ssTcpProc
        stdout: StdioCollector {
            onStreamFinished: root.tcpListeners = root._parseSs(text, "tcp")
        }
        onExited: {
            if (!ssUdpProc.running)
                root._refreshFirewallMaybe();
        }
    }

    Process {
        id: ssUdpProc
        stdout: StdioCollector {
            onStreamFinished: root.udpListeners = root._parseSs(text, "udp")
        }
        onExited: {
            if (!ssTcpProc.running)
                root._refreshFirewallMaybe();
        }
    }

    function _refreshFirewallMaybe(): void {
        // also refresh ssh established
        root._refreshSsh();
        root._refreshFirewall();
    }

    function _refreshSsh(): void {
        if (sshProc.running)
            return;
        sshProc.command = ["ss", "-Htnp", "state", "established", "( sport = :22 )"];
        sshProc.running = true;
    }

    Process {
        id: sshProc
        stdout: StdioCollector {
            onStreamFinished: root.sshEstablished = root._parseSsh(text)
        }
    }

    function _parseSsh(text: string): var {
        const out = [];
        if (!text)
            return out;
        for (const line of text.split("\n")) {
            const parts = line.trim().split(/\s+/);
            if (parts.length < 5)
                continue;
            const local = parts[3] || "";
            const remote = parts[4] || "";
            const rIdx = remote.lastIndexOf(":");
            const rAddr = rIdx > 0 ? remote.substring(0, rIdx) : remote;
            out.push({ local: local, remote: remote, rAddr: rAddr });
        }
        return out;
    }

    function _refreshFirewall(): void {
        if (fwProc.running)
            return;
        fwProc.command = ["nft", "-j", "list", "tables"];
        fwProc.running = true;
    }

    Process {
        id: fwProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const t = Array.isArray(data?.nftables) ? data.nftables.filter(e => e && e.table).length : 0;
                    root.fwReadable = true;
                    root.fwTableCount = t;
                } catch (e) {
                    root.fwReadable = false;
                    root.fwTableCount = 0;
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.fwReadable = false;
                root.fwTableCount = 0;
            }
        }
    }

    Process {
        id: archAuditProc
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text ? text.trim().split(/\n+/).filter(Boolean) : [];
                root.advisoriesCount = lines.length;
                root.advisoriesOk = true;
                root.advisoriesFetched = true;
                root.advisoriesLast = Date.now();
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.advisoriesCount = 0;
                root.advisoriesOk = false;
                root.advisoriesFetched = true;
                root.advisoriesLast = Date.now();
            }
        }
    }

    function startEngagement(label: string): string {
        if (!label || label.trim().length === 0)
            return "";
        const tok = SecurityProfile.engagementStarted(label.trim(), "lab");
        if (tok) {
            root.engagementToken = tok;
            root.engagementLabel = label.trim();
            root.engagementStart = Date.now();
        }
        return tok;
    }

    function endEngagement(): void {
        if (root.engagementToken) {
            SecurityProfile.engagementEnded(root.engagementToken, "user");
            root.engagementToken = "";
            root.engagementLabel = "";
            root.engagementStart = 0;
        }
    }

    function isEngaged(): bool {
        return root.engagementToken.length > 0;
    }
}
