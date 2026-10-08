// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// The plugin's one state holder: settings, the last scan result and the
// launch actions. The surfaces draw from this; none of them owns a scan
// or a launch, so the three of them can never disagree.
//
// The scanner is event-driven by contract. This service is constructed
// the moment a plugin surface names it (on a live install the resident
// notch tile does that at shell start), and that triggers exactly one
// scan. It runs again only when the UI explicitly rescans. There is no
// timer and no watcher here: the single FileView watches the plugin's
// own settings file, which is the one file the plugin owns.
Singleton {
    id: root

    readonly property string configDir: `${Quickshell.env("HOME")}/.config/aphotic/plugins/game-launcher`
    readonly property string configPath: `${root.configDir}/config.json`
    readonly property string pluginDir: `${Quickshell.env("HOME")}/.local/share/aphotic/plugins/game-launcher`
    readonly property string scanScript: `${root.pluginDir}/bin/scan_games.py`

    // Defaults. The on-disk file overrides key by key, so a partial or
    // missing file never strands a surface: a fresh install behaves
    // exactly like these.
    readonly property var defaultSettings: ({
        sources: ({ steam: true, lutris: true, heroic: true, cartridges: true, desktop: true }),
        box_art_dir: "",
        sgdb: ({ enabled: false, api_key: "", animated: false }),
        sort_by: "recent",
        favorites_first: true,
        close_on_launch: true,
        tile_enabled: true,
        favorites: [],
        manual: []
    })

    property var settings: root.defaultSettings
    property var games: []
    property var _result: ({})
    readonly property var clients: root._result.clients ?? ({})
    readonly property bool bigPicture: root._result.big_picture === true

    property bool scanning: false
    property string lastError: ""
    property var lastScanned: null

    // ── Settings ────────────────────────────────────────────────────────

    function _merge(data) {
        const merged = JSON.parse(JSON.stringify(root.defaultSettings));
        if (!data)
            return merged;
        for (const key of Object.keys(merged)) {
            if (data[key] === undefined)
                continue;
            if (key === "sources" || key === "sgdb")
                merged[key] = Object.assign({}, merged[key], data[key]);
            else
                merged[key] = data[key];
        }
        return merged;
    }

    function _applyConfig(text) {
        try {
            root.settings = root._merge(JSON.parse(text));
        } catch (e) {
            // A half-written or corrupt file keeps the last good
            // settings rather than resetting them.
            console.warn(`game-launcher: settings unreadable, keeping last good: ${e}`);
        }
    }

    // argv form, no shell: the payload travels as a plain argument, so
    // nothing in it can be misread as shell syntax. Same pattern core
    // Settings uses to persist.
    function _persist() {
        writeProc.command = ["python3", "-c",
            "import os,sys; os.makedirs(sys.argv[1], exist_ok=True); open(sys.argv[2], 'w').write(sys.argv[3])",
            root.configDir, root.configPath, JSON.stringify(root.settings, null, 2)];
        writeProc.running = true;
    }

    function _writeManualFile() {
        manualProc.command = ["python3", "-c",
            "import os,sys; os.makedirs(sys.argv[1], exist_ok=True); open(sys.argv[2], 'w').write(sys.argv[3])",
            root.configDir, `${root.configDir}/manual.json`, JSON.stringify(root.settings.manual)];
        manualProc.running = true;
    }

    function setSetting(key, value) {
        const next = JSON.parse(JSON.stringify(root.settings));
        next[key] = value;
        root.settings = next;
        root._persist();
    }

    function setSource(name, enabled) {
        const next = JSON.parse(JSON.stringify(root.settings));
        next.sources = Object.assign({}, next.sources);
        next.sources[name] = enabled;
        root.settings = next;
        root._persist();
    }

    function setSgdb(patch) {
        const next = JSON.parse(JSON.stringify(root.settings));
        next.sgdb = Object.assign({}, next.sgdb, patch);
        root.settings = next;
        root._persist();
    }

    function toggleFavorite(name, source) {
        const key = `${name}:${source}`;
        const favorites = root.settings.favorites.slice();
        const at = favorites.indexOf(key);
        const nowFavorite = at < 0;
        if (at >= 0)
            favorites.splice(at, 1);
        else
            favorites.push(key);
        root.settings = Object.assign({}, root.settings, { favorites: favorites });
        // Reflect the change in the in-memory list at once: the grid
        // must not wait for a rescan to show the new star state.
        root.games = root.games.map(g => g.name === name && g.source === source
            ? Object.assign({}, g, { favorite: nowFavorite })
            : g);
        root._persist();
    }

    function upsertManual(name, exec, cover) {
        const manual = root.settings.manual.slice();
        const at = manual.findIndex(g => g.name === name);
        if (at >= 0)
            manual[at] = { name: name, exec: exec, cover: cover };
        else
            manual.push({ name: name, exec: exec, cover: cover });
        root.setSetting("manual", manual);
    }

    function removeManual(name) {
        root.setSetting("manual", root.settings.manual.filter(g => g.name !== name));
    }

    // ── Scanning ────────────────────────────────────────────────────────

    function scan() {
        if (root.scanning)
            return;
        root.scanning = true;
        root.lastError = "";
        scanProc.command = ["python3", root.scanScript,
            "--settings", root.configPath,
            "--manual", `${root.configDir}/manual.json`];
        scanProc.running = true;
    }

    // One scan when the service comes to life. On a live install the
    // tile constructs it at shell start; in a windowless probe it is
    // the probe that constructs it. Either way: one scan per
    // construction, never a repeat.
    Component.onCompleted: {
        root._writeManualFile();
        root.scan();
    }

    // ── Launching ───────────────────────────────────────────────────────

    function launch(game) {
        if (!game || !game.exec)
            return;
        // setsid reparents the game away from the shell: the spawn
        // returns immediately, so a crash or a ten-hour session never
        // sits in the shell's process table.
        Quickshell.execDetached(["sh", "-c", `setsid ${game.exec} >/dev/null 2>&1 &`]);
        if (root.settings.close_on_launch)
            Actions.invoke("workspace", {});
    }

    function launchClient(name) {
        const command = root.clients[name];
        if (command)
            Quickshell.execDetached(["sh", "-c", `setsid ${command} >/dev/null 2>&1 &`]);
    }

    function launchSteamBigPicture() {
        if (root.clients.steam)
            Quickshell.execDetached(["sh", "-c", "setsid steam -silent steam://open/bigpicture >/dev/null 2>&1 &"]);
    }

    // ── Plumbing ────────────────────────────────────────────────────────

    FileView {
        id: configFile

        path: root.configPath
        watchChanges: true
        onLoaded: root._applyConfig(text())
        onLoadFailed: {
            // Absent file: defaults stand, nothing to do.
        }
    }

    property Process scanProc: Process {
        stdout: StdioCollector {
            id: scanStdout

            onStreamFinished: {
                root.scanning = false;
                try {
                    const data = JSON.parse(scanStdout.text);
                    root.games = data.games ?? [];
                    root._result = data;
                    root.lastScanned = new Date();
                } catch (e) {
                    // A bad parse keeps the last known list on screen
                    // rather than blanking it over one failed scan.
                    root.lastError = String(e);
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitStatus !== 0 && exitCode !== 0)
                root.lastError = `scanner exited ${exitCode}`;
            root.scanning = false;
        }
    }

    property Process writeProc: Process {
        onExited: (exitCode, exitStatus) => {
            if (exitStatus !== 0 || exitCode !== 0)
                console.warn(`game-launcher: settings write failed (${exitCode})`);
        }
    }

    property Process manualProc: Process {
        onExited: (exitCode, exitStatus) => {
            if (exitStatus !== 0 || exitCode !== 0)
                console.warn(`game-launcher: manual list write failed (${exitCode})`);
        }
    }
}
