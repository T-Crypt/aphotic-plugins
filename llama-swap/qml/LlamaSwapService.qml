// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.services
import qs.services.ai
import qs.services.profile

Singleton {
    id: root

    readonly property bool active: Object.keys(root._visibleOwners).length > 0
    readonly property var runningModels: AiProviders.llamaSwapRunningModels

    readonly property var models: root.runningModels.map(model => {
        const pid = root._portToPid[String(model?.port ?? 0)] ?? 0;
        const claim = pid > 0 ? ResourceEngine.claimById(`llama-swap-proc-${pid}`) : null;
        return {
            name: model?.name ?? "",
            state: model?.state ?? "",
            port: model?.port ?? 0,
            pid: pid,
            vramMib: claim?.owner === "llama-swap" ? Number(claim.amount ?? 0) : 0
        };
    })

    property var _visibleOwners: ({})
    property var _portToPid: ({})
    property string _resolvedKey: ""
    property string _pendingKey: ""
    property string unloadingModel: ""

    onActiveChanged: {
        LlamaSwapStats.hold("llama-swap-tile", root.active);
        if (root.active)
            root._resolve();
    }
    onRunningModelsChanged: root._resolve()

    function setSurfaceVisible(owner: string, on: bool): void {
        const next = Object.assign({}, root._visibleOwners);
        if (on)
            next[owner] = true;
        else
            delete next[owner];
        root._visibleOwners = next;
    }

    function _modelKey(): string {
        if (!root.active || !AiConfig.llamaSwapHostConfigured)
            return "";
        return root.runningModels.map(m => `${m?.name ?? ""}:${m?.port ?? 0}:${m?.state ?? ""}`).sort().join("|");
    }

    function _resolve(): void {
        const key = root._modelKey();
        if (key === root._resolvedKey)
            return;
        if (!key) {
            root._resolvedKey = "";
            root._portToPid = ({});
            return;
        }
        if (root._pidProc.running)
            return;
        root._pendingKey = key;
        root._pidProc.running = true;
    }

    function _parsePids(text: string): var {
        const map = ({});
        for (const line of text.split("\n")) {
            const pid = parseInt(line, 10);
            const port = line.match(/--port\s+(\d+)/);
            if (pid > 0 && port)
                map[port[1]] = pid;
        }
        return map;
    }

    function unload(model: string): void {
        if (!model || !AiConfig.llamaSwapHostConfigured || root._unloadProc.running)
            return;
        root.unloadingModel = model;
        root._unloadProc.command = ["curl", "-sS", "-m", "10", "-X", "POST",
            `${AiConfig.llamaSwapHost}/api/models/unload/${encodeURIComponent(model)}`];
        root._unloadProc.running = true;
    }

    property Process _pidProc: Process {
        command: ["pgrep", "-a", "-x", "llama-server"]
        stdout: StdioCollector {
            onStreamFinished: root._portToPid = root._parsePids(text)
        }
        onRunningChanged: {
            if (root._pidProc.running)
                return;
            root._resolvedKey = root._pendingKey;
            Qt.callLater(root._resolve);
        }
    }

    property Process _unloadProc: Process {
        onExited: root.unloadingModel = ""
    }
}
