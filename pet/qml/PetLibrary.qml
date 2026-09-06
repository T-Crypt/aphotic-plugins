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
// normalise() is the whole of that boundary, and it reads two formats:
// this plugin's own, and the one the pet generators write, which is
// accepted directly so that installing one of those pets does not mean
// editing its manifest first. Either way `sheet` has to be a bare
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
            // Still "angler" on disk. The art is an orb now, but the id is
            // what a saved config names, and renaming it would quietly
            // move every install that had chosen this pet onto another one.
            id: "angler",
            name: qsTr("Aphotid"),
            description: qsTr("A glowing orb. The light in the dark, wearing the accent colour.")
        },
        {
            id: "clip",
            name: qsTr("Clip"),
            description: qsTr("A bent paperclip with opinions about what you are writing.")
        }
    ]

    readonly property string fallbackBuiltin: "miko"

    // Sprite pets that ship with the plugin. Same data path as an
    // imported pet -- one sheet, one grid, one set of state rows -- but
    // the sheet travels with the plugin, so there is nothing to download
    // or place by hand before picking one.
    //
    // Their manifests are written here rather than shipped as a pet.json
    // beside each sheet. These are the plugin's own assets: there is no
    // untrusted file to bounds-check and no format to sniff, and a second
    // copy of the layout on disk is a second thing to get wrong.
    //
    // `sheet` resolves against this file, and this file's directory is the
    // one symlinked into the shell's module tree -- so a bundled asset has
    // to live under qml/ to be reachable at all.
    readonly property var bundled: [
        {
            id: "cipher",
            name: qsTr("Cipher"),
            description: qsTr("A developer at a floating console, wearing the accent colour in his seams and circuitry."),
            sheet: "pets/cipher/spritesheet.webp",
            columns: 8,
            rows: 11,
            targetHeight: 96,
            accent: {
                from: 205,
                to: 285,
                feather: 10,
                minSat: 0.18,
                refSat: 0.38
            }
        }
    ]

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

    // A bundled id wins over a directory of the same name under
    // ~/.config/aphotic/pets/. The two are the same pet in every case that
    // matters -- someone who installed one by hand before it shipped --
    // and the one travelling with the plugin is the one kept in step
    // with it.
    readonly property var bundledPet: root.selectionIsBuiltin ? null : (root.bundled.find(b => b.id === root.selected) ?? null)
    readonly property bool selectionIsBundled: root.bundledPet !== null

    // Which vector pet draws. Also the answer when an imported pet is
    // selected but its folder, manifest or image does not load, which is
    // what keeps the surface from ever going blank.
    readonly property string builtin: root.selected !== "default" && root.selectionIsBuiltin ? root.selected : root.fallbackBuiltin

    // Empty for a built-in and for a bundled pet, so nothing goes looking
    // under ~/.config/aphotic/pets/ for a sheet that was never meant to
    // live there.
    readonly property string spriteName: root.selectionIsBuiltin || root.selectionIsBundled ? "" : root.selected

    // The one manifest everything below reads: a bundled pet's, written
    // in this file, or an imported pet's, parsed out of its pet.json.
    readonly property var manifest: root.selectionIsBundled ? root.bundledManifest(root.bundledPet) : root._manifest

    readonly property bool spriteReady: root.manifest !== null
    readonly property string displayName: root.spriteReady ? (root.manifest.name.length > 0 ? root.manifest.name : root.selected) : (root.builtins.find(b => b.id === root.builtin)?.name ?? root.builtin)
    readonly property string sheetUrl: root.spriteReady ? root.urlFor(root.spriteName, root.manifest) : ""

    // Zero when the manifest does not state a cell size, which is a
    // manifest whose format fixes the grid instead. PetView divides the
    // loaded image by `columns` and `rows` in that case, so one sheet
    // exported at a different resolution needs no edit anywhere.
    readonly property int frameWidth: root.manifest?.frame?.width ?? 0
    readonly property int frameHeight: root.manifest?.frame?.height ?? 0
    readonly property int columns: root.manifest?.columns ?? 0
    readonly property int rows: root.manifest?.rows ?? 0

    // Same again for draw scale. A format that fixes its cell size in
    // source pixels cannot also fix a sensible drawn size, so it asks for
    // a height instead and PetView works back to the scale.
    readonly property real scale: root.manifest?.scale ?? 1
    readonly property int targetHeight: root.manifest?.targetHeight ?? 0
    readonly property bool smooth: root.manifest?.smooth ?? false

    // The hue window a sprite pet declares its recolourable regions in, or
    // null for one that declares none. Only PetView's shader reads it.
    readonly property var accent: root.manifest?.accent ?? null
    readonly property bool themeable: root.accent !== null

    // On unless it has been turned off, so a pet that can wear the theme
    // arrives wearing it.
    readonly property bool tinted: root._config?.tint !== false

    // How big the pet is drawn, over whatever size its own manifest asks
    // for. Relative rather than a pixel height because the built-ins and
    // every sheet are authored at different sizes, so one absolute number
    // would mean something different for each of them.
    readonly property real minScale: 0.5
    readonly property real maxScale: 4
    readonly property real userScale: {
        const value = root._config?.size;
        if (typeof value !== "number" || !isFinite(value))
            return 1;
        return Math.max(root.minScale, Math.min(root.maxScale, value));
    }

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

    // --- Which monitor the pet is on -----------------------------------
    //
    // There is one pet no matter how many outputs are plugged in. Core
    // still builds a surface per screen and this plugin does not get to
    // say otherwise, so the surfaces agree among themselves which one is
    // drawing: exactly one owns the pet, and every other one draws nothing
    // and masks to nothing, leaving its whole output to the desktop.
    //
    // The screen is saved by connector name beside the position, because a
    // position on its own stops meaning anything once there is a second
    // output -- 0.5, 0.88 is the bottom middle of *a* screen, not of the
    // desktop.
    readonly property string homeScreen: {
        const name = root._config?.screen;
        if (typeof name !== "string")
            return "";
        return name;
    }

    // The screen actually drawing the pet: the dragged-to one while a drag
    // is in flight, the saved one while it is still plugged in, and the
    // first otherwise -- so unplugging the monitor the pet was left on
    // brings it back instead of stranding it on an output that is gone.
    readonly property string activeScreen: {
        if (root.dragScreen.length > 0)
            return root.dragScreen;
        if (root.homeScreen.length > 0 && root.screenNamed(root.homeScreen))
            return root.homeScreen;
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }

    // Set only while a drag is in flight, and read by every surface. The
    // surface holding the pointer grab keeps writing here even after the
    // pet has crossed onto another monitor, because a Wayland pointer grab
    // belongs to the surface the press landed on and cannot be handed to
    // another one mid-press. So for the rest of that drag the surface
    // tracking the pointer and the surface drawing the pet are two
    // different windows, and this is the whole of what they share.
    property string dragScreen: ""
    property real dragX: 0.5
    property real dragY: 0.88
    readonly property bool dragging: root.dragScreen.length > 0

    // Every surface's own size in pixels, by screen name, reported by that
    // surface. A drag crossing onto another monitor has to land the pet
    // inside that monitor's surface, and the output's size is not that
    // size: the bar's exclusive zone comes off the top, so a 1920x1080
    // output carries a 1920x1024 surface. Only the surface living there
    // knows the difference, so it is the one that says.
    property var surfaces: ({})

    function reportSurface(name: string, w: real, h: real): void {
        if (name.length === 0 || !(w > 0) || !(h > 0))
            return;
        const known = root.surfaces[name];
        if (known && known.w === w && known.h === h)
            return;
        const next = Object.assign({}, root.surfaces);
        next[name] = {
            w: w,
            h: h
        };
        root.surfaces = next;
    }

    // Falls back to the output's own size for a screen whose surface has
    // not reported yet, which is only ever the case for the frame or two
    // between a monitor appearing and its overlay loading.
    function surfaceSize(name: string): var {
        const known = root.surfaces[name];
        if (known)
            return known;
        const screen = root.screenNamed(name);
        if (screen)
            return {
                w: screen.width,
                h: screen.height
            };
        return {
            w: 1,
            h: 1
        };
    }

    function screenNamed(name: string): var {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return screens[i];
        }
        return null;
    }

    // The nearest screen touching `name` on one side, or null at the end
    // of the row. Laid out from the compositor's own coordinates rather
    // than from the order screens happen to be enumerated in, so a monitor
    // physically to the left is the one a pet dragged left arrives on.
    // Only screens whose other axis actually overlaps count, so dragging
    // sideways never lands the pet on one stacked above.
    function neighbour(name: string, dx: int, dy: int): var {
        const from = root.screenNamed(name);
        if (!from)
            return null;
        const screens = Quickshell.screens;
        let best = null;
        let bestGap = Infinity;
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i];
            if (s.name === name)
                continue;
            let gap = 0;
            if (dx !== 0) {
                if (s.y >= from.y + from.height || s.y + s.height <= from.y)
                    continue;
                gap = dx > 0 ? s.x - (from.x + from.width) : from.x - (s.x + s.width);
            } else {
                if (s.x >= from.x + from.width || s.x + s.width <= from.x)
                    continue;
                gap = dy > 0 ? s.y - (from.y + from.height) : from.y - (s.y + s.height);
            }
            if (gap < 0 || gap >= bestGap)
                continue;
            best = s;
            bestGap = gap;
        }
        return best;
    }

    function moveDrag(name: string, x: real, y: real): void {
        root.dragX = x;
        root.dragY = y;
        root.dragScreen = name;
    }

    // The drop is the only part of a drag that touches the file. Writing
    // the screen and the position together matters: they are one fact, and
    // a config that had moved to the new screen but kept the old screen's
    // coordinates would put the pet somewhere the user did not drop it.
    function commitDrag(): void {
        if (root.dragScreen.length === 0)
            return;
        const name = root.dragScreen;
        root.dragScreen = "";
        root._write({
            screen: name,
            x: root._clamp01(root.dragX, 0.5),
            y: root._clamp01(root.dragY, 0.88)
        });
    }

    function cancelDrag(): void {
        root.dragScreen = "";
    }

    property var _config: ({})

    // False until the read resolves. See _write.
    property bool _settled: false
    property var _queued: null
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

    function setHome(screen: string, x: real, y: real): void {
        root._write({ screen: screen, x: root._clamp01(x, 0.5), y: root._clamp01(y, 0.88) });
    }

    function setLocked(value: bool): void {
        root._write({ locked: value });
    }

    function setRoam(value: real): void {
        root._write({ roam: Math.max(0, Math.min(600, Math.round(value))) });
    }

    // Stored as `size`, not `scale`: a pet's own manifest already has a
    // `scale`, meaning the sheet's authored draw size, and two keys of
    // that name a directory apart is the mistake pet.json already made
    // once.
    function setScale(value: real): void {
        root._write({ size: Math.max(root.minScale, Math.min(root.maxScale, Math.round(value * 100) / 100)) });
    }

    function setTinted(value: bool): void {
        root._write({ tint: value });
    }

    function resetHome(): void {
        root._write({ screen: root.activeScreen, x: 0.5, y: 0.88 });
    }

    // A pet's own vocabulary is idle/walk/react/sleep. "fidget" is the
    // small between-beats motion the brain runs, and "held" is the pet in
    // the user's hand; a sheet expresses both as extra frames on its idle
    // row rather than as states of their own.
    function stateFor(mood: string): var {
        const states = root.manifest?.states ?? ({});
        const state = states[mood === "fidget" || mood === "held" ? "idle" : mood] ?? states.idle ?? ({});
        return {
            row: Math.max(0, state.row ?? 0),
            frames: Math.max(1, state.frames ?? 1),
            fps: Math.max(1, Math.min(12, state.fps ?? root.manifest?.fps ?? 8))
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
    //
    // Nothing reaches the file before the read has resolved, though. The
    // merge below is against whatever `_config` holds, and until the read
    // lands that is an empty object -- so a write in that window would
    // spell out a whole config from one patch and drop every key already
    // on disk, which pet included. Writes that arrive early are held and
    // replayed on top of the real config once it is known.
    function _write(patch: var): void {
        root._config = Object.assign({}, root._config, patch);
        if (!root._settled) {
            root._queued = Object.assign({}, root._queued ?? ({}), patch);
            return;
        }
        root._writePending = true;
        writer.setText(JSON.stringify(root._config, null, 2) + "\n");
    }

    // Called once the config file has either been read or been established
    // not to exist -- including the legacy name, which is only looked for
    // when the current one is missing.
    function _settle(): void {
        if (root._settled)
            return;
        root._settled = true;
        const queued = root._queued;
        root._queued = null;
        if (queued)
            root._write(queued);
    }

    // Where a pet's sheet lives, for a manifest this has already accepted.
    // Public because the settings pane draws the same sheets in its
    // picker and must not build that path a second way.
    function sheetUrlFor(name: string, manifest: var): string {
        return `file://${root.petsDir}/${name}/${manifest.sheet}`;
    }

    // The same question for either kind of sprite pet. A bundled manifest
    // carries an already-resolved URL, because its sheet travels with the
    // plugin and has no pets-directory path to build.
    function urlFor(name: string, manifest: var): string {
        const url = manifest?.sheetUrl ?? "";
        if (url.length > 0)
            return url;
        return root.sheetUrlFor(name, manifest);
    }

    // A bundled pet's manifest, in the shape normalise() produces for an
    // imported one, so everything downstream reads one thing. Public
    // because the settings pane draws these tiles too.
    function bundledManifest(pet: var): var {
        return {
            name: pet.name,
            sheet: "",
            sheetUrl: Qt.resolvedUrl(pet.sheet).toString(),
            frame: null,
            columns: pet.columns,
            rows: pet.rows,
            scale: 0,
            targetHeight: pet.targetHeight,
            fps: 8,
            smooth: true,
            accent: root._normaliseAccent(pet.accent),
            states: root._standardStates()
        };
    }

    // Turn whatever is in a pet.json into the one shape the rest of this
    // plugin reads, or null. Two formats are understood.
    //
    // `format: 1` is this plugin's own: the manifest states its cell size
    // and its rows, so any layout works.
    //
    // A manifest with a `spritesheetPath` and no format is the one the
    // pet generators write, and its layout is fixed rather than declared:
    // eight columns by nine rows, the nine rows being idle, running-right,
    // running-left, waving, jumping, failed, waiting, running and review.
    // Reading it directly is the difference between installing one of
    // those pets and editing its manifest by hand first, and the cell size
    // is divided out of the image rather than assumed, so a sheet exported
    // at another resolution still works.
    //
    // Sheet names are checked the same way in both. A manifest can only
    // ever name an image inside its own pet directory: no slash, no
    // backslash, no leading dot.
    function normalise(data: var): var {
        if (!data)
            return null;
        if (data.format === 1)
            return root._normaliseNative(data);
        if (typeof data.spritesheetPath === "string")
            return root._normaliseGenerated(data);
        return null;
    }

    function _sheetName(value: var): string {
        if (typeof value !== "string" || value.length === 0)
            return "";
        if (value.includes("/") || value.includes("\\") || value.startsWith("."))
            return "";
        return value;
    }

    function _normaliseNative(data: var): var {
        const sheet = root._sheetName(data.sheet);
        if (sheet.length === 0)
            return null;
        if (!((data.frame?.width ?? 0) > 0 && (data.frame?.height ?? 0) > 0))
            return null;
        if (!data.states?.idle)
            return null;
        return {
            name: typeof data.name === "string" ? data.name : "",
            sheet: sheet,
            sheetUrl: "",
            frame: data.frame,
            columns: 0,
            rows: 0,
            scale: data.scale ?? 1,
            targetHeight: 0,
            fps: data.fps,
            smooth: data.smooth ?? false,
            accent: root._normaliseAccent(data.accent),
            states: data.states
        };
    }

    function _normaliseGenerated(data: var): var {
        const sheet = root._sheetName(data.spritesheetPath);
        if (sheet.length === 0)
            return null;

        // The generators' own contract: spriteVersionNumber 2 is an 8x11
        // atlas, the nine standard rows plus two rows of look directions
        // this plugin does not draw, and anything earlier is 8x9 with the
        // standard rows alone. A manifest stating its own grid outranks
        // both, because a sheet that declares its layout is worth more
        // than a convention about it.
        //
        // The row count is not cosmetic. Cell height is the image height
        // divided by it, so an 8x11 sheet read as 8x9 draws every frame
        // through a window a fifth too tall and hangs the top of the next
        // row below the pet's feet.
        const layout = data.spritesheetLayout ?? ({});
        const version = typeof data.spriteVersionNumber === "number" ? data.spriteVersionNumber : 1;

        return {
            name: typeof data.displayName === "string" ? data.displayName : (typeof data.id === "string" ? data.id : ""),
            sheet: sheet,
            sheetUrl: "",
            frame: null,
            columns: root._grid(layout.columns, 8),
            rows: root._grid(layout.rows, version >= 2 ? 11 : 9),
            // No scale: a fixed grid says nothing about how big the art
            // wants to be on screen, so ask for a height near the built-in
            // pets and let PetView divide.
            scale: 0,
            targetHeight: 96,
            fps: 8,
            // Painted rather than pixel art, and always drawn smaller than
            // its cell, where nearest-neighbour eats whole rows of pixels.
            smooth: true,
            accent: root._normaliseAccent(data.accent),
            states: root._standardStates()
        };
    }

    // Eight of the nine standard rows, which the generated format and this
    // plugin's own bundled pets share. Row 2 is the mirror of row 1, which
    // this plugin does itself. `sleep` borrows the failure pose, which
    // droops with its eyes half shut where the waiting pose is alert.
    //
    // `working`/`waitingProcess`/`attentionRequired`/`complete`/`error` are
    // `PetAgentState`'s own mood vocabulary (`PET-03`), not this plugin's
    // idle/walk/react/sleep one -- they exist so a sprite pet gets real
    // art for a harness's state instead of always falling back to `idle`.
    // `error` shares row 5 with `sleep`; two moods pointing at the same
    // pose is fine; `stateFor()` keys on the mood string, not the row.
    // `compacting` has no row of its own (`PETS.md` §4.3) and is meant to
    // fall through to `idle` here -- see `Pet.qml`'s badge for how that
    // state is told apart from plain idle without new art.
    function _standardStates(): var {
        return {
            idle: {
                row: 0,
                frames: 6
            },
            walk: {
                row: 1,
                frames: 8
            },
            react: {
                row: 3,
                frames: 4
            },
            sleep: {
                row: 5,
                frames: 1
            },
            working: {
                row: 7,
                frames: 6
            },
            waitingProcess: {
                row: 6,
                frames: 6
            },
            attentionRequired: {
                row: 8,
                frames: 6
            },
            complete: {
                row: 4,
                frames: 5
            },
            error: {
                row: 5,
                frames: 8
            }
        };
    }

    function _grid(value: var, fallback: int): int {
        if (typeof value !== "number" || !isFinite(value) || value < 1 || value > 64)
            return fallback;
        return Math.floor(value);
    }

    // Which hue window a pet's recolourable regions live in. Read as
    // defensively as the rest of a manifest: a window outside 0-360, a
    // saturation outside 0-1, or no accent block at all leaves the pet
    // drawn exactly as authored rather than tinted by nonsense.
    function _normaliseAccent(value: var): var {
        if (!value)
            return null;
        const from = root._degrees(value.from);
        const to = root._degrees(value.to);
        if (from === null || to === null || from === to)
            return null;
        return {
            from: from,
            to: to,
            feather: Math.max(0, Math.min(60, root._number(value.feather, 10))),
            minSat: root._clamp01(value.minSat, 0.18),
            refSat: Math.max(0.05, root._clamp01(value.refSat, 0.4))
        };
    }

    function _degrees(value: var): var {
        if (typeof value !== "number" || !isFinite(value) || value < 0 || value > 360)
            return null;
        return value;
    }

    function _number(value: var, fallback: real): real {
        if (typeof value !== "number" || !isFinite(value))
            return fallback;
        return value;
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
            root._settle();
        }
        onLoadFailed: {
            if (root._adopted)
                return;
            root._config = ({});
            // Not settled yet: the legacy name is still to be tried, and
            // settling here would let a queued write land first and be
            // overwritten by the migration a moment later.
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
                root._config = JSON.parse(text());
            } catch (e) {
            }
            root._settle();
            // Settled with the migrated config in hand, so this writes it
            // back under the new name rather than queueing behind itself.
            root._write({});
        }

        // No file under either name, which is what a fresh install looks
        // like. Nothing to migrate, and nothing more to wait for.
        onLoadFailed: root._settle()
    }

    FileView {
        path: root.spriteName.length > 0 ? `${root.petsDir}/${root.spriteName}/pet.json` : ""
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root._manifest = root.normalise(JSON.parse(text()));
            } catch (e) {
                root._manifest = null;
            }
        }
        onLoadFailed: root._manifest = null
    }
}
