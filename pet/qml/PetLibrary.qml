// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Which pet is drawn, and the sheet it is drawn from.
//
// A custom pet is data, never code: one PNG sprite sheet plus one JSON
// manifest in ~/.config/aphotic/pets/<name>/. Importing arbitrary QML
// would put third-party code inside the shell's own process with the
// shell's own reach, and the trust question that raises is open (D-05),
// so this reads a fixed schema and nothing else.
//
// _validate is the whole of that boundary. `sheet` has to be a bare
// filename living beside the manifest -- no slash, no leading dot, no
// traversal -- so a manifest can only ever name an image inside its own
// pet directory, and everything else is bounds-checked into a usable
// value or the pet is rejected outright and the built-in one draws
// instead.
Singleton {
    id: root

    readonly property string petsDir: `${Quickshell.env("HOME")}/.config/aphotic/pets`
    readonly property string configPath: `${Quickshell.env("HOME")}/.config/aphotic/plugins/pet/pet.json`

    readonly property string selected: {
        const name = root._config?.pet;
        if (typeof name !== "string" || name.length === 0)
            return "default";
        if (name.includes("/") || name.includes("\\") || name.includes(".."))
            return "default";
        return name;
    }

    readonly property bool spriteReady: root._manifest !== null
    readonly property string displayName: root._manifest?.name ?? qsTr("Aphotid")
    readonly property string sheetUrl: root.spriteReady ? `file://${root.petsDir}/${root.selected}/${root._manifest.sheet}` : ""
    readonly property int frameWidth: root._manifest?.frame?.width ?? 0
    readonly property int frameHeight: root._manifest?.frame?.height ?? 0
    readonly property real scale: root._manifest?.scale ?? 1
    readonly property bool smooth: root._manifest?.smooth ?? false

    property var _config: ({})
    property var _manifest: null

    // A pet's own vocabulary is idle/walk/react/sleep. "fidget" is the
    // small between-beats motion the brain runs, which a sheet expresses
    // as extra frames on its idle row rather than a state of its own.
    function stateFor(mood: string): var {
        const states = root._manifest?.states ?? ({});
        const state = states[mood === "fidget" ? "idle" : mood] ?? states.idle ?? ({});
        return {
            row: Math.max(0, state.row ?? 0),
            frames: Math.max(1, state.frames ?? 1),
            fps: Math.max(1, Math.min(12, state.fps ?? root._manifest?.fps ?? 8))
        };
    }

    function _validate(data: var): var {
        if (!data || data.format !== 1)
            return null;
        const sheet = data.sheet;
        if (typeof sheet !== "string" || sheet.length === 0)
            return null;
        if (sheet.includes("/") || sheet.includes("\\") || sheet.startsWith("."))
            return null;
        if (!((data.frame?.width ?? 0) > 0 && (data.frame?.height ?? 0) > 0))
            return null;
        if (!data.states?.idle)
            return null;
        return data;
    }

    // Both files are optional on purpose -- an install with no imported
    // pet has neither -- so their absence is the normal case, not an
    // error worth a line in the shell log on every start.
    FileView {
        path: root.configPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root._config = JSON.parse(text());
            } catch (e) {
                root._config = ({});
            }
        }
        onLoadFailed: root._config = ({})
    }

    FileView {
        path: `${root.petsDir}/${root.selected}/pet.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root._manifest = root._validate(JSON.parse(text()));
            } catch (e) {
                root._manifest = null;
            }
        }
        onLoadFailed: root._manifest = null
    }
}
