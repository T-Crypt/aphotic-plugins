// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Which pet is drawn, where the user put it, and the sheet it is drawn
// from when the pet is an imported one.
//
// Two kinds of pet share one name. A built-in is vector code in this
// plugin, drawn off the live palette, and `pet` naming one of `builtins`
// below selects it. Anything else is read as a folder under
// ~/.config/aphotic/pets/, which is data: one PNG sprite sheet plus one
// JSON manifest. Importing arbitrary QML would put third-party code
// inside the shell's own process with the shell's own reach, and the
// trust question that raises is open (D-05), so an imported pet reads a
// fixed schema and nothing else.
//
// _validate is the whole of that boundary. `sheet` has to be a bare
// filename living beside the manifest -- no slash, no leading dot, no
// traversal -- so a manifest can only ever name an image inside its own
// pet directory, and everything else is bounds-checked into a usable
// value or the pet is rejected outright and a built-in draws instead.
//
// This is also the only writer of the plugin's own settings. Dragging the
// pet and every control in the settings pane lands here, which is why the
// reader and the writer are two FileViews on one path with a pending flag
// between them: the same shape core's Settings.qml uses for its own state
// file, so this singleton's write is not re-read as somebody else's edit.
Singleton {
    id: root

    readonly property string petsDir: `${Quickshell.env("HOME")}/.config/aphotic/pets`
    readonly property string configDir: `${Quickshell.env("HOME")}/.config/aphotic/plugins/pet`
    readonly property string configPath: `${root.configDir}/settings.json`

    // Where these settings lived until 1.2.1. Calling them pet.json put
    // two files of that name one directory apart, holding different
    // things: this one says which pet and where it sits, the one in
    // pets/<name>/ is a pet's own manifest. People opened the wrong one.
    // Read once, on the first start after the rename, then written back
    // under the new name and left alone. Deleting it is the user's call,
    // not this plugin's.
    readonly property string legacyPath: `${root.configDir}/pet.json`

    // Order is the order the settings pane offers them in, so the default
    // comes first.
    readonly property var builtins: [
        {
            id: "miko",
            name: qsTr("Miko"),
            description: qsTr("A small shrine girl who wears the accent colour.")
        },
        {
            id: "angler",
            name: qsTr("Aphotid"),
            description: qsTr("The anglerfish. Front-heavy, toothed, lit by its own lure.")
        },
        {
            id: "clip",
            name: qsTr("Clip"),
            description: qsTr("A bent paperclip with opinions about what you are writing.")
        },
        {
            id: "claude",
            name: qsTr("Claude"),
            description: qsTr("A starburst that blinks. Rotates a little when it walks.")
        }
    ]

    readonly property string fallbackBuiltin: "miko"

    // The raw name, sanitised. "default" is what every pet.json written
    // before there was more than one built-in says, and it has to keep
    // meaning "whatever this plugin ships as the default".
    readonly property string selected: {
        const name = root._config?.pet;
        if (typeof name !== "string" || name.length === 0)
            return "default";
        if (name.includes("/") || name.includes("\\") || name.includes(".."))
            return "default";
        return name;
    }

    readonly property bool selectionIsBuiltin: root.selected === "default" || root.builtins.some(b => b.id === root.selected)

    // Which vector pet draws. Also the answer when an imported pet is
    // selected but its folder, manifest or image does not load, which is
    // what keeps the surface from ever going blank.
    readonly property string builtin: root.selected !== "default" && root.selectionIsBuiltin ? root.selected : root.fallbackBuiltin

    // Empty for a built-in, so nothing goes looking for a sheet that was
    // never meant to exist.
    readonly property string spriteName: root.selectionIsBuiltin ? "" : root.selected

    readonly property bool spriteReady: root._manifest !== null
    readonly property string displayName: root.spriteReady ? (root._manifest.name ?? root.selected) : (root.builtins.find(b => b.id === root.builtin)?.name ?? root.builtin)
    readonly property string sheetUrl: root.spriteReady ? `file://${root.petsDir}/${root.spriteName}/${root._manifest.sheet}` : ""
    readonly property int frameWidth: root._manifest?.frame?.width ?? 0
    readonly property int frameHeight: root._manifest?.frame?.height ?? 0
    readonly property real scale: root._manifest?.scale ?? 1
    readonly property bool smooth: root._manifest?.smooth ?? false

    // Where the user put the pet, as the centre of the creature over the
    // surface it lives on. Normalised rather than in pixels so one saved
    // spot lands in the same place on a 1080p laptop and a 1440p ultrawide,
    // and so a monitor change never strands the pet off screen.
    readonly property real homeX: root._clamp01(root._config?.x, 0.5)
    readonly property real homeY: root._clamp01(root._config?.y, 0.88)
    readonly property bool locked: root._config?.locked === true
    readonly property real roam: {
        const value = root._config?.roam;
        if (typeof value !== "number" || !isFinite(value))
            return 130;
        return Math.max(0, Math.min(600, value));
    }

    property var _config: ({})
    property var _manifest: null
    property bool _writePending: false
    property bool _wantLegacy: false

    // True once a config has come from a file, new name or old. A failed
    // read must not clear what a successful one already put here: the
    // watcher fires on a path that did not exist and then does exist, and
    // one spurious failure in that window would throw the migration away.
    property bool _adopted: false

    // A FileView pointed at an empty path never reports a failure, so
    // switching from an imported pet to a built-in one has to drop the
    // old manifest here or the sheet would keep drawing over it.
    onSpriteNameChanged: root._manifest = null

    function setPet(name: string): void {
        root._write({ pet: name });
    }

    function setHome(x: real, y: real): void {
        root._write({ x: root._clamp01(x, 0.5), y: root._clamp01(y, 0.88) });
    }

    function setLocked(value: bool): void {
        root._write({ locked: value });
    }

    function setRoam(value: real): void {
        root._write({ roam: Math.max(0, Math.min(600, Math.round(value))) });
    }

    function resetHome(): void {
        root._write({ x: 0.5, y: 0.88 });
    }

    // A pet's own vocabulary is idle/walk/react/sleep. "fidget" is the
    // small between-beats motion the brain runs, and "held" is the pet in
    // the user's hand; a sheet expresses both as extra frames on its idle
    // row rather than as states of their own.
    function stateFor(mood: string): var {
        const states = root._manifest?.states ?? ({});
        const state = states[mood === "fidget" || mood === "held" ? "idle" : mood] ?? states.idle ?? ({});
        return {
            row: Math.max(0, state.row ?? 0),
            frames: Math.max(1, state.frames ?? 1),
            fps: Math.max(1, Math.min(12, state.fps ?? root._manifest?.fps ?? 8))
        };
    }

    function _clamp01(value: var, fallback: real): real {
        if (typeof value !== "number" || !isFinite(value))
            return fallback;
        return Math.max(0, Math.min(1, value));
    }

    // The in-memory config moves first and the file follows. A setter that
    // waited for the write to come back through the watcher would leave
    // the pet a frame behind the cursor it is being dragged by.
    function _write(patch: var): void {
        root._config = Object.assign({}, root._config, patch);
        root._writePending = true;
        writer.setText(JSON.stringify(root._config, null, 2) + "\n");
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

    // Both files are optional on purpose -- a fresh install has neither --
    // so their absence is the normal case, not an error worth a line in
    // the shell log on every start.
    FileView {
        path: root.configPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root._adopted = true;
            if (root._writePending) {
                root._writePending = false;
                return;
            }
            try {
                root._config = JSON.parse(text());
            } catch (e) {
                root._config = ({});
            }
        }
        onLoadFailed: {
            if (root._adopted)
                return;
            root._config = ({});
            root._wantLegacy = true;
        }
    }

    FileView {
        id: writer

        path: root.configPath
        printErrors: false
    }

    // Held at an empty path until the read above says there is nothing to
    // read, so an install that has both files never reads the stale one.
    FileView {
        path: root._wantLegacy ? root.legacyPath : ""
        printErrors: false
        onLoaded: {
            if (root._adopted)
                return;
            root._adopted = true;
            try {
                root._write(JSON.parse(text()));
            } catch (e) {
            }
        }
    }

    FileView {
        path: root.spriteName.length > 0 ? `${root.petsDir}/${root.spriteName}/pet.json` : ""
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
