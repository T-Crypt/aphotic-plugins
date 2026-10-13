// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

// Deliberately only these three imports: no qs.config, no qs.components and
// no qs.services. This file is the plugin's whole state layer, and keeping
// it free of the shell's own singletons is what lets tests/
// test_rdp_settings.sh load it alone under an offscreen `qs -p`. Reaching
// into qs.services would drag in the notification history and the rest of
// the service graph, which cannot be instantiated headlessly.
import QtQuick
import Quickshell
import Quickshell.Io

// The Remote Desktop profile: the one file this plugin owns, the defaults it
// resolves against, and whether a session is up.
//
// It is a singleton rather than state inside RdpPane because the settings
// category's loader only exists while that category is selected, and because
// `cli/rdp.sh` reads the same file this writes. The pane edits here, the CLI
// reads there, and there is no second copy of the schema: the defaults below
// are the same values the CLI falls back to field by field.
//
// The reader and the writer are two FileViews on one path with a pending
// flag between them, the shape pet/PetLibrary.qml uses and core's own
// Settings.qml before it: one FileView that reads, one that writes, so this
// singleton's own write is not re-read as somebody else's edit.
Singleton {
    id: root

    readonly property string configDir: `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/aphotic/plugins/xfreerdp`
    readonly property string configPath: `${root.configDir}/settings.json`

    // What a fresh install behaves like. The file on disk overrides key by
    // key, so a partial or missing file never strands the pane and never
    // builds a different argv from the one the CLI's own fallbacks build.
    //
    // There is no `keybind` key here on purpose: the combo and its action
    // live in plugin.toml's [keybind] block and nowhere else. A second copy
    // in this file would be a source of truth nothing reads.
    readonly property var defaultSettings: ({
        host: "",
        port: 3389,
        user: "",
        sec: "nla",
        cert: "ignore",
        mic: ({ enabled: true, device: "" }),
        speaker: ({ device: "" }),
        camera: ({ enabled: true }),
        resolution: ({ mode: "dynamic", width: 1920, height: 1080 }),
        window: ({
            class: "work-rdp",
            grab_keyboard: true,
            auto_reconnect: true,
            gfx: "AVC420",
            workspace: "none",
            fullscreen: false
        }),
        extra: ""
    })

    property var settings: root.defaultSettings

    // False until the read resolves (loaded or genuinely absent). An edit
    // arriving before that is held, so a click on a fresh install cannot
    // write a half-filled file over one that is about to be read.
    property bool _settled: false
    property var _queued: null
    property bool _writePending: false

    // The pane's status line. `statusKnown` is false when the answer is
    // "unknown" -- no compositor, or no aphotic on PATH -- which is a fact
    // about the machine rather than an error about the session.
    property bool statusKnown: false
    property bool sessionRunning: false

    // ── Reading ─────────────────────────────────────────────────────────

    // Key by key, and for the four nested groups into their keys as well,
    // so a file holding `{ "window": { "workspace": "3" } }` keeps the
    // default window class instead of losing it to the one key it did set.
    // A value of the wrong type is ignored rather than assigned: a stray
    // string where a number belongs would otherwise reach xfreerdp as one.
    function _mergeInto(target: var, source: var): void {
        for (const key of Object.keys(target)) {
            const value = source[key];
            if (value === undefined || value === null)
                continue;
            if (typeof target[key] === "object")
                root._mergeInto(target[key], value);
            else if (typeof value === typeof target[key])
                target[key] = value;
        }
    }

    function merged(data: var): var {
        const next = JSON.parse(JSON.stringify(root.defaultSettings));
        if (data)
            root._mergeInto(next, data);
        return next;
    }

    function _applyConfig(text: string): void {
        try {
            root.settings = root.merged(JSON.parse(text));
        } catch (e) {
            // A half-written or corrupt file keeps the defaults rather than
            // leaving a partial profile in place.
            console.warn(`xfreerdp: settings unreadable, keeping defaults: ${e}`);
        }
    }

    // ── Writing ─────────────────────────────────────────────────────────

    function _writeNow(): void {
        root._writePending = true;
        writer.setText(`${JSON.stringify(root.settings, null, 2)}\n`);
    }

    // Called once the settings file has either been read or been found
    // absent. Anything edited before that is folded into the settings that
    // were just loaded and written back, so an early click survives.
    function _settle(): void {
        if (root._settled)
            return;
        root._settled = true;
        const queued = root._queued;
        root._queued = null;
        if (!queued)
            return;
        const next = JSON.parse(JSON.stringify(root.settings));
        root._mergeInto(next, queued);
        root.settings = next;
        root._writeNow();
    }

    function _assign(target: var, path: string, value: var): void {
        const parts = path.split(".");
        let node = target;
        for (let i = 0; i < parts.length - 1; i++) {
            if (typeof node[parts[i]] !== "object" || node[parts[i]] === null)
                node[parts[i]] = ({});
            node = node[parts[i]];
        }
        node[parts[parts.length - 1]] = value;
    }

    // One write per call, however many paths the patch carries.
    function setMany(patch: var): void {
        const paths = Object.keys(patch);
        const next = JSON.parse(JSON.stringify(root.settings));
        for (const path of paths)
            root._assign(next, path, patch[path]);
        root.settings = next;

        if (!root._settled) {
            root._queued = root._queued ?? ({});
            for (const path of paths)
                root._assign(root._queued, path, patch[path]);
            return;
        }
        root._writeNow();
    }

    // A dotted path, so a nested field needs no second accessor:
    // set("window.class", "…").
    function set(path: string, value: var): void {
        const patch = ({});
        patch[path] = value;
        root.setMany(patch);
    }

    function _patch(group: string, values: var): var {
        const patch = ({});
        for (const key of Object.keys(values))
            patch[`${group}.${key}`] = values[key];
        return patch;
    }

    function _clampInt(value: var, min: int, max: int, fallback: int): int {
        const parsed = parseInt(value, 10);
        if (!isFinite(parsed))
            return fallback;
        return Math.max(min, Math.min(max, parsed));
    }

    // ── Typed setters ───────────────────────────────────────────────────

    function setHost(value: string): void {
        root.set("host", value.trim());
    }

    function setPort(value: var): void {
        root.set("port", root._clampInt(value, 1, 65535, root.defaultSettings.port));
    }

    function setUser(value: string): void {
        root.set("user", value.trim());
    }

    function setSecurity(value: string): void {
        root.set("sec", value === "aad" ? "aad" : "nla");
    }

    function setCertificate(value: string): void {
        root.set("cert", value === "tofu" ? "tofu" : "ignore");
    }

    function setMic(values: var): void {
        root.setMany(root._patch("mic", values));
    }

    function setSpeaker(values: var): void {
        root.setMany(root._patch("speaker", values));
    }

    function setCamera(enabled: bool): void {
        root.set("camera.enabled", enabled);
    }

    // The size is kept even in dynamic mode: the session still needs a
    // starting geometry, and switching back to fixed must not have lost it.
    function setResolution(values: var): void {
        const patch = ({});
        if (values.mode !== undefined)
            patch["resolution.mode"] = values.mode === "fixed" ? "fixed" : "dynamic";
        if (values.width !== undefined)
            patch["resolution.width"] = root._clampInt(values.width, 320, 16384, root.defaultSettings.resolution.width);
        if (values.height !== undefined)
            patch["resolution.height"] = root._clampInt(values.height, 200, 16384, root.defaultSettings.resolution.height);
        root.setMany(patch);
    }

    function setWindow(values: var): void {
        const patch = root._patch("window", values);
        if (values.class !== undefined && values.class.trim().length === 0)
            patch["window.class"] = root.defaultSettings.window.class;
        root.setMany(patch);
    }

    function setExtra(value: string): void {
        root.set("extra", value.trim());
    }

    // ── Status ──────────────────────────────────────────────────────────

    // On demand only: on construction, on a compositor open/close event and
    // after each button. There is no timer anywhere in this plugin, and a
    // status read that polls would be the one thing that made one necessary.
    function refreshStatus(): void {
        statusProc.running = true;
    }

    // ── Files ───────────────────────────────────────────────────────────

    FileView {
        id: reader

        path: root.configPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (root._writePending) {
                // Our own write coming back. Parsing it would be a no-op at
                // best and a race with the next edit at worst.
                root._writePending = false;
                root._settle();
                return;
            }
            root._applyConfig(reader.text());
            root._settle();
        }
        // No file yet, which is what a fresh install looks like. The
        // defaults already in place are the right answer.
        onLoadFailed: root._settle()
    }

    FileView {
        id: writer

        path: root.configPath
        printErrors: false
    }

    Process {
        id: statusProc

        command: ["aphotic", "xfreerdp", "status"]

        stdout: StdioCollector {
            onStreamFinished: {
                const answer = text.trim();
                if (answer === "running" || answer === "not-running") {
                    root.sessionRunning = answer === "running";
                    root.statusKnown = true;
                    return;
                }
                // "unknown", or anything else the CLI did not mean as an
                // answer: the pane shows no state rather than a wrong one.
                root.sessionRunning = false;
                root.statusKnown = false;
            }
        }

        // A missing aphotic, or one that failed, is the same answer as
        // "unknown": nothing here is worth an error line.
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.sessionRunning = false;
                root.statusKnown = false;
            }
        }
    }

    Component.onCompleted: root.refreshStatus()
}
