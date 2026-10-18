// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool active: Object.keys(root._visibleOwners).length > 0

    // "unknown" until the first ps probe lands, then "running",
    // "stopped" or "no-permission" (the socket denied us). Only the ps
    // probe decides this; no systemctl path is ever touched.
    readonly property string daemonState: root._daemonState
    readonly property bool daemonOk: root.daemonState === "running"

    readonly property var containers: {
        const stats = root._statsByName;
        const busy = root._busyKey;
        return root._containerRows.map(row => {
            const s = row.state === "running" ? (stats[row.name] ?? null) : null;
            return {
                id: row.id,
                name: row.name,
                state: row.state,
                status: row.status,
                image: row.image,
                ports: row.ports,
                project: row.project,
                cpuPerc: s?.cpu ?? 0,
                memText: s?.memText ?? "",
                busy: busy === "c:" + row.id || (row.project.length > 0 && busy === "p:" + row.project)
            };
        });
    }

    readonly property var groups: {
        const list = [];
        const byName = {};
        for (const c of root.containers) {
            const name = c.project.length > 0 ? c.project : qsTr("Standalone");
            let g = byName[name];
            if (!g) {
                g = { name: name, compose: c.project.length > 0, containers: [], running: 0, total: 0, busy: root._busyKey === "p:" + c.project };
                byName[name] = g;
                list.push(g);
            }
            g.containers.push(c);
            g.total++;
            if (c.state === "running")
                g.running++;
        }
        list.sort((a, b) => {
            if (a.compose !== b.compose)
                return a.compose ? -1 : 1;
            return a.name.localeCompare(b.name, undefined, { sensitivity: "base" });
        });
        for (const g of list)
            g.containers.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: "base" }));
        return list;
    }

    readonly property int runningCount: root.containers.reduce((n, c) => n + (c.state === "running" ? 1 : 0), 0)
    readonly property string countsText: `${root.runningCount}/${root.containers.length}`

    // One row per df type (Images / Containers / Local Volumes / Build
    // Cache). size and reclaimable are display strings; reclaimable
    // keeps its "(n%)" part.
    readonly property var df: root._dfRows
    readonly property string pruneResult: root._pruneResult

    // $TERMINAL when the session sets one, else the shell's own default.
    readonly property string terminalProgram: Quickshell.env("TERMINAL") || "kitty"

    property string _daemonState: "unknown"
    property var _containerRows: []
    property var _statsByName: ({})
    property var _dfRows: []
    property string _busyKey: ""
    property bool _busyAwaitRefresh: false
    property string _pruneResult: ""
    property bool _dfNeedsOpenRefresh: true
    property string _psKey: ""
    property string _statsKey: ""
    property string _dfKey: ""
    property string _psOut: ""
    property string _psErr: ""
    property string _statsOut: ""
    property string _dfOut: ""
    property var _visibleOwners: ({})

    function setSurfaceVisible(owner: string, on: bool): void {
        const next = Object.assign({}, root._visibleOwners);
        if (on)
            next[owner] = true;
        else
            delete next[owner];
        root._visibleOwners = next;
    }

    onActiveChanged: {
        if (root.active) {
            root._dfNeedsOpenRefresh = true;
            root._refreshPs();
        }
    }

    function startContainer(id: string): void {
        root._run("c:" + id, ["docker", "start", id]);
    }

    function stopContainer(id: string): void {
        root._run("c:" + id, ["docker", "stop", id]);
    }

    function restartContainer(id: string): void {
        root._run("c:" + id, ["docker", "restart", id]);
    }

    // start/stop only. `docker compose ... down` deletes the containers,
    // so it is never offered here.
    function startProject(project: string): void {
        root._run("p:" + project, ["docker", "compose", "-p", project, "start"]);
    }

    function stopProject(project: string): void {
        root._run("p:" + project, ["docker", "compose", "-p", project, "stop"]);
    }

    // Reclaims stopped-containers' write layers, dangling images and
    // stale build cache. No --volumes: named volumes are user data.
    function prune(): void {
        root._run("prune", ["docker", "system", "prune", "-f"]);
    }

    function openLogs(id: string): void {
        Quickshell.execDetached([root.terminalProgram, "-e", "docker", "logs", "-f", "--tail", "200", id]);
    }

    function openShell(id: string): void {
        Quickshell.execDetached([root.terminalProgram, "-e", "docker", "exec", "-it", id, "sh"]);
    }

    function shortImage(name: string): string {
        let s = name;
        if (s.startsWith("docker.io/library/"))
            s = s.substring("docker.io/library/".length);
        else if (s.startsWith("docker.io/"))
            s = s.substring("docker.io/".length);
        const at = s.indexOf("@");
        if (at >= 0)
            s = s.substring(0, at) + "…";
        return s;
    }

    function publishedPorts(raw: string): string {
        const seen = {};
        const out = [];
        for (const part of raw.split(",")) {
            const p = part.trim();
            const arrow = p.indexOf("->");
            if (arrow < 0)
                continue;
            const host = p.substring(0, arrow);
            const colon = host.lastIndexOf(":");
            const port = colon >= 0 ? host.substring(colon + 1) : host;
            if (port.length === 0 || seen[port])
                continue;
            seen[port] = true;
            out.push(port);
        }
        return out.join(", ");
    }

    function formatBytes(bytes: real): string {
        if (!isFinite(bytes) || bytes <= 0)
            return "0B";
        const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
        let v = bytes;
        let i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return `${v >= 10 ? Math.round(v) : Math.round(v * 10) / 10} ${units[i]}`;
    }

    function dfLine(row: var): string {
        if (!row || row.type.length === 0)
            return "";
        const parts = [row.type];
        if (row.total > 0)
            parts.push(`${row.total}`);
        if (row.size.length > 0)
            parts.push(row.size);
        if (row.reclaimable.length > 0)
            parts.push(`reclaimable ${row.reclaimable}`);
        return parts.join(" · ");
    }

    function _run(key: string, argv: var): void {
        if (!root.active || root._actionProc.running || key.length === 0)
            return;
        root._busyKey = key;
        root._actionProc.command = argv;
        root._actionProc.running = true;
    }

    function _refreshPs(): void {
        if (!root.active || root._psProc.running)
            return;
        root._psOut = "";
        root._psErr = "";
        root._psProc.running = true;
    }

    function _refreshStats(): void {
        if (!root.active || !root.daemonOk || root._statsProc.running || root.runningCount === 0)
            return;
        root._statsOut = "";
        root._statsProc.running = true;
    }

    function _refreshDf(): void {
        if (!root.active || !root.daemonOk || root._dfProc.running || !root._dfNeedsOpenRefresh)
            return;
        root._dfNeedsOpenRefresh = false;
        root._dfOut = "";
        root._dfProc.running = true;
    }

    function _onPsDone(exitCode: int): void {
        const lines = root._psOut.split("\n").filter(l => l.trim().length > 0);
        if (exitCode === 0) {
            root._daemonState = "running";
            const rows = root._parsePs(lines);
            const key = JSON.stringify(rows);
            if (key !== root._psKey) {
                root._psKey = key;
                root._containerRows = rows;
            }
        } else {
            root._daemonState = root._psErr.toLowerCase().indexOf("permission denied") >= 0 ? "no-permission" : "stopped";
            if (root._psKey.length > 0) {
                root._psKey = "";
                root._containerRows = [];
            }
        }
        if (root._daemonState !== "running") {
            if (root._statsKey.length > 0) {
                root._statsKey = "";
                root._statsByName = ({});
            }
            if (root._dfKey.length > 0) {
                root._dfKey = "";
                root._dfRows = [];
            }
        }
        // The refreshed ps list is the confirmation a busy row waits for.
        if (root._busyAwaitRefresh) {
            root._busyAwaitRefresh = false;
            root._busyKey = "";
        }
        if (root.daemonOk) {
            root._refreshDf();
            if (root.runningCount > 0)
                root._refreshStats();
        }
    }

    function _onStatsDone(): void {
        const map = {};
        for (const line of root._statsOut.split("\n")) {
            const t = line.trim();
            if (t.length === 0)
                continue;
            let o;
            try {
                o = JSON.parse(t);
            } catch (e) {
                continue;
            }
            const name = String(o?.Name ?? "").trim();
            if (name.length === 0)
                continue;
            map[name] = {
                cpu: root._parsePerc(o?.CPUPerc),
                memText: root._splitMemUsage(String(o?.MemUsage ?? ""))
            };
        }
        const key = JSON.stringify(map);
        if (key !== root._statsKey) {
            root._statsKey = key;
            root._statsByName = map;
        }
    }

    function _onDfDone(): void {
        const rows = [];
        for (const line of root._dfOut.split("\n")) {
            const t = line.trim();
            if (t.length === 0)
                continue;
            let o;
            try {
                o = JSON.parse(t);
            } catch (e) {
                continue;
            }
            const type = String(o?.Type ?? "").trim();
            if (type.length === 0)
                continue;
            rows.push({
                type: type,
                total: root._countOf(o?.TotalCount),
                size: root._sizeText(o?.Size),
                reclaimable: root._reclaimText(o?.Reclaimable)
            });
        }
        const key = JSON.stringify(rows);
        if (key !== root._dfKey) {
            root._dfKey = key;
            root._dfRows = rows;
        }
    }

    function _parsePs(lines: var): var {
        const rows = [];
        for (const line of lines) {
            let o;
            try {
                o = JSON.parse(line);
            } catch (e) {
                continue;
            }
            const labels = root._labelMap(o?.Labels);
            const id = String(o?.ID ?? "").trim();
            rows.push({
                id: id,
                name: String(o?.Names ?? id).trim(),
                state: String(o?.State ?? "").toLowerCase(),
                status: String(o?.Status ?? "").trim(),
                image: root.shortImage(String(o?.Image ?? "")),
                ports: root.publishedPorts(String(o?.Ports ?? "")),
                project: String(labels["com.docker.compose.project"] ?? "").trim()
            });
        }
        return rows;
    }

    // ps labels arrive as "k=v,k2=v2"; some CLI builds hand over an
    // object instead. Both become the same map.
    function _labelMap(raw: var): var {
        const out = {};
        if (raw && typeof raw === "object") {
            for (const k in raw)
                out[k] = String(raw[k] ?? "");
            return out;
        }
        for (const part of String(raw ?? "").split(",")) {
            const p = part.trim();
            if (p.length === 0)
                continue;
            const eq = p.indexOf("=");
            if (eq < 0)
                continue;
            out[p.substring(0, eq)] = p.substring(eq + 1);
        }
        return out;
    }

    function _parsePerc(text: var): real {
        const v = parseFloat(String(text ?? ""));
        return isNaN(v) ? 0 : v;
    }

    // "45.2MiB / 1.942GiB" -> "45.2 / 1.94 GiB", as one display string
    // so the mono column never reflows mid-stream.
    function _splitMemUsage(text: string): string {
        const i = text.indexOf("/");
        const used = i >= 0 ? text.substring(0, i).trim() : text.trim();
        const limit = i >= 0 ? text.substring(i + 1).trim() : "";
        return `${_compactSize(used)}${limit.length > 0 ? ` / ${_compactSize(limit)}` : ""}`;
    }

    function _compactSize(text: string): string {
        const m = String(text ?? "").trim().match(/^([\d.]+)\s*([kMGTP]i?B|kiB|B)$/i);
        if (!m)
            return text;
        const v = parseFloat(m[1]);
        if (isNaN(v))
            return text;
        const unit = m[2].toLowerCase();
        const exp = unit === "b" ? 0 : unit.indexOf("k") === 0 ? 1 : unit.indexOf("m") === 0 ? 2 : unit.indexOf("g") === 0 ? 3 : unit.indexOf("t") === 0 ? 4 : 5;
        return root.formatBytes(v * Math.pow(1024, exp));
    }

    function _countOf(v: var): int {
        const n = parseInt(String(v ?? ""), 10);
        return isNaN(n) ? 0 : n;
    }

    // df sizes are usually human strings ("1.245GB", "990.3MB (79%)");
    // some CLI builds hand over raw byte numbers. Both become display
    // strings here, so nothing downstream re-parses units.
    function _sizeText(v: var): string {
        if (typeof v === "number" && isFinite(v))
            return root.formatBytes(v);
        const s = String(v ?? "").trim();
        const bytes = root._bytesFromHuman(s);
        return bytes > 0 ? root.formatBytes(bytes) : s;
    }

    function _reclaimText(v: var): string {
        if (typeof v === "number" && isFinite(v))
            return root.formatBytes(v);
        const s = String(v ?? "").trim();
        const bytes = root._bytesFromHuman(s);
        const pct = s.match(/\((\d+)%\)/);
        if (bytes <= 0)
            return s;
        return pct ? `${root.formatBytes(bytes)} (${pct[1]}%)` : root.formatBytes(bytes);
    }

    function _bytesFromHuman(s: string): real {
        const m = String(s ?? "").trim().match(/^([\d.]+)\s*(B|kB|KB|MB|GB|TB)/);
        if (!m)
            return -1;
        const v = parseFloat(m[1]);
        if (isNaN(v))
            return -1;
        const mul = { "B": 1, "kB": 1000, "KB": 1000, "MB": 1000000, "GB": 1000000000, "TB": 1000000000000 };
        return v * (mul[m[2]] ?? 1);
    }

    function _lastLine(text: string): string {
        const lines = String(text ?? "").split("\n").filter(l => l.trim().length > 0);
        return lines.length > 0 ? lines[lines.length - 1].trim() : "";
    }

    property Process _psProc: Process {
        command: ["docker", "ps", "-a", "--format", "json"]
        stdout: StdioCollector {
            onStreamFinished: root._psOut = text
        }
        stderr: StdioCollector {
            onStreamFinished: root._psErr = text
        }
        onExited: exitCode => root._onPsDone(exitCode)
    }

    property Process _statsProc: Process {
        command: ["docker", "stats", "--no-stream", "--format", "json"]
        stdout: StdioCollector {
            onStreamFinished: root._statsOut = text
        }
        onExited: {
            if (root.active)
                root._onStatsDone();
        }
    }

    property Process _dfProc: Process {
        command: ["docker", "system", "df", "--format", "json"]
        stdout: StdioCollector {
            onStreamFinished: root._dfOut = text
        }
        onExited: {
            if (root.active)
                root._onDfDone();
        }
    }

    property Process _actionProc: Process {
        onExited: exitCode => {
            if (root._busyKey === "prune") {
                root._pruneResult = exitCode === 0
                    ? (root._lastLine(pruneStdout.text) || qsTr("nothing to reclaim"))
                    : (root._lastLine(pruneStderr.text) || qsTr("prune failed"));
                root._dfNeedsOpenRefresh = true;
            }
            if (root._busyKey.length > 0) {
                // The next ps refresh confirms the state change and clears
                // the busy row.
                root._busyAwaitRefresh = true;
                root._refreshPs();
            }
        }
        stdout: StdioCollector {
            id: pruneStdout
        }
        stderr: StdioCollector {
            id: pruneStderr
        }
    }

    property Timer _psTimer: Timer {
        interval: 3000
        running: root.active && root.daemonOk
        repeat: true
        onTriggered: root._refreshPs()
    }

    property Timer _statsTimer: Timer {
        interval: 3000
        running: root.active && root.daemonOk && root.runningCount > 0
        repeat: true
        onTriggered: root._refreshStats()
    }
}
