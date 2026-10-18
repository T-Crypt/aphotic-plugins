// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import Quickshell
import qs.services
import qs.services.profile
import qs.modules.plugins.gameLauncher

// Instantiates the notch tile headlessly and drives it from the service,
// so a renamed property, a bad binding or a row that reads the wrong list
// fails here rather than on a desktop. It also registers an imitation of
// the gaming profile through the engines -- the profile id and a VRAM
// claim are the only contract this plugin reads, so the real gaming
// plugin is not needed and is deliberately not imported.
//
// The tile is created with a width, because everything it lays out is
// measured against the notch's own width, and the drawn rows are counted
// off the item tree: a property that says three covers while the layout
// drew none is exactly the failure a probe is for.
ShellRoot {
    id: root

    property var tile: null
    property var _after: null

    Component {
        id: tileComponent
        GamesNotchTile {}
    }

    Component {
        id: workspaceComponent
        GameLauncherWorkspace {}
    }

    function after(action): void {
        root._after = action;
    }

    function _continue(): void {
        const next = root._after;
        root._after = null;
        if (next)
            next();
    }

    function pass(message: string): void {
        console.log(`PASS: ${message}`);
        Qt.callLater(Qt.quit);
    }

    function fail(message: string): void {
        console.error(`FAIL: ${message}`);
        Qt.callLater(Qt.quit);
    }

    function check(condition: bool, message: string): bool {
        if (!condition) {
            root.fail(message);
            return false;
        }
        return true;
    }

    function checkEqual(actual, expected, what: string): bool {
        return root.check(actual === expected,
            `${what}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
    }

    // Every visible item in the tree, depth first. Hidden rows are skipped
    // with their children, which is how "the layout drew nothing" is told
    // apart from "the list is empty".
    function visibleItems(item, found): var {
        for (let i = 0; i < item.children.length; i++) {
            const child = item.children[i];
            if (child.visible === false)
                continue;
            found.push(child);
            root.visibleItems(child, found);
        }
        return found;
    }

    function visibleCovers(): int {
        return root.visibleItems(root.tile, []).filter(c => c.game !== undefined).length;
    }

    function hasVisibleLabel(label: string): bool {
        return root.visibleItems(root.tile, []).some(c => c.label === label);
    }

    Connections {
        target: GameLauncherService

        function onScanningChanged(): void {
            if (!GameLauncherService.scanning)
                Qt.callLater(root._continue);
        }
    }

    function run(): void {
        // The first reference constructs the service, which runs its one
        // scan; the assertions below wait for it so a late result cannot
        // land in the middle of them.
        root.tile = tileComponent.createObject(root, {
            width: 388,
            height: 420
        });
        if (!root.check(root.tile !== null, "GamesNotchTile should instantiate"))
            return;
        root.after(root.settle);
        if (!GameLauncherService.scanning)
            Qt.callLater(root._continue);
    }

    function settle(): void {
        // ── Empty: nothing scanned, nothing played ───────────────────
        if (!root.check(!root.tile.gaming, "no profile should be active yet"))
            return;
        if (!root.checkEqual(root.tile.recent.length, 0, "no recent games yet"))
            return;
        if (!root.checkEqual(root.tile.pinned.length, 0, "no pinned games yet"))
            return;
        if (!root.checkEqual(root.visibleCovers(), 0, "an empty tile draws no covers"))
            return;
        if (!root.checkEqual(root.tile.elapsed, "", "there is no elapsed time without a game"))
            return;

        // ── Recent and pinned come from the last scan ────────────────
        GameLauncherService.games = [
            { name: "Portal", source: "steam", exec: "steam -silent steam://rungameid/400", cover: "", favorite: true },
            { name: "Hollow Knight", source: "heroic", exec: "heroic run hollowknight", cover: "", favorite: false },
            { name: "Doom", source: "cartridges", exec: "doom", cover: "", favorite: true }
        ];
        GameLauncherService.settings = Object.assign({}, GameLauncherService.settings, {
            recent: [
                { name: "Doom", source: "cartridges", at: 3000 },
                { name: "Hollow Knight", source: "heroic", at: 2000 },
                { name: "Uninstalled", source: "steam", at: 1000 }
            ]
        });

        if (!root.checkEqual(root.tile.recent.length, 2, "recent entries resolve against the last scan"))
            return;
        if (!root.checkEqual(root.tile.recent[0].name, "Doom", "the newest launch comes first"))
            return;
        if (!root.checkEqual(root.tile.pinned.length, 1, "pinned excludes what the recent row already shows"))
            return;
        if (!root.checkEqual(root.tile.pinned[0].name, "Portal", "the pinned row keeps the favourite"))
            return;
        if (!root.checkEqual(root.visibleCovers(), 3, "two recent covers and one pinned cover are drawn"))
            return;
        // The notch clips at Config.notch.maxHeight, and this is the
        // tallest the tile ever gets: both cover rows plus the client row.
        if (!root.check(root.tile.implicitHeight <= 360,
            `the tile has to fit the notch: it came to ${root.tile.implicitHeight}px`))
            return;
        console.log(`DEBUG heights recent+pinned=${root.tile.implicitHeight} width=${root.tile.width}`);

        // The plane is the same service behind a bigger surface, and the
        // probe loads it too so the file the tile's launch path shares is
        // built rather than merely parsed.
        const plane = workspaceComponent.createObject(root, {
            width: 1200,
            height: 800
        });
        if (!root.check(plane !== null, "GameLauncherWorkspace should instantiate")) {
            return;
        }
        if (!root.checkEqual(plane.visibleGames.length, 3, "the plane lists every scanned game")) {
            plane.destroy();
            return;
        }
        if (!root.check(plane.sourceTabs.includes("steam"), "the plane tabs follow the scanned sources")) {
            plane.destroy();
            return;
        }
        plane.destroy();

        // ── At most four covers per row ──────────────────────────────
        const many = [];
        for (let i = 0; i < 6; i++) {
            many.push({ name: `Game ${i}`, source: "steam", exec: `steam ${i}`, cover: "", favorite: false });
        }
        const manyRecent = many.map((g, i) => ({ name: g.name, source: g.source, at: i }));
        GameLauncherService.games = many;
        GameLauncherService.settings = Object.assign({}, GameLauncherService.settings, { recent: manyRecent });
        if (!root.checkEqual(root.tile.recent.length, 4, "the recent row stops at four"))
            return;
        if (!root.checkEqual(root.visibleCovers(), 4, "four recent covers are drawn"))
            return;

        // ── Launch history ───────────────────────────────────────────
        const before = GameLauncherService.recent.length;
        GameLauncherService.launch({ name: "No command", source: "steam" });
        if (!root.checkEqual(GameLauncherService.recent.length, before, "a game with no command is never recorded"))
            return;
        GameLauncherService._recordRecent({ name: "Portal", source: "steam" });
        if (!root.checkEqual(GameLauncherService.recent[0].name, "Portal", "the newest launch is recorded first"))
            return;
        if (!root.checkEqual(GameLauncherService.recent[0].source, "steam", "the record keeps the source"))
            return;
        GameLauncherService._recordRecent({ name: "Portal", source: "steam" });
        if (!root.checkEqual(GameLauncherService.recent.length, before + 1, "re-launching moves an entry rather than duplicating it"))
            return;

        const twenty = [];
        for (let i = 0; i < 20; i++) {
            twenty.push({ name: `g${i}`, source: "steam", at: i });
        }
        twenty.push({ junk: true });
        const merged = GameLauncherService._merge({ recent: twenty });
        if (!root.checkEqual(merged.recent.length, 12, "a hand-edited recent list is capped when it loads"))
            return;
        if (!root.check(merged.recent.every(entry => typeof entry.name === "string"), "junk entries are dropped on load"))
            return;

        // ── Store clients and the two buttons ────────────────────────
        GameLauncherService._result = { clients: { steam: "steam" }, big_picture: true };
        if (!root.checkEqual(root.tile.presentClients.length, 1, "the present clients come from the scan"))
            return;
        if (!root.check(GameLauncherService.bigPicture, "the service should report big picture"))
            return;
        if (!root.check(root.hasVisibleLabel("Big Picture"), "big picture is offered when the service reports it"))
            return;
        if (!root.check(root.hasVisibleLabel("Library"), "the library button is always there"))
            return;
        GameLauncherService._result = { clients: {} };
        if (!root.check(!root.hasVisibleLabel("Big Picture"), "no big picture button without the service reporting it"))
            return;

        // ── On-screen registration gates the one changing read ───────
        if (!root.check(GameLauncherService.surfacesVisible, "the tile registers itself while it is on screen"))
            return;
        if (!root.check(root.tile.clock > 0, "the clock runs while the tile is on screen"))
            return;
        GameLauncherService.setSurfaceVisible(root.tile.owner, false);
        if (!root.check(!GameLauncherService.surfacesVisible, "the tile's own registration is the only one"))
            return;
        if (!root.checkEqual(root.tile.clock, 0, "the clock reads nothing while the tile is off screen"))
            return;
        GameLauncherService.setSurfaceVisible(root.tile.owner, true);
        if (!root.check(root.tile.clock > 0, "the clock comes back with the tile"))
            return;

        // ── Now playing ──────────────────────────────────────────────
        GameLauncherService.games = [
            { name: "Portal", source: "steam", exec: "steam -silent steam://rungameid/400", cover: "", favorite: false }
        ];
        ProfileEngine.register({
            id: "gaming",
            label: "Gaming",
            snapshot: ["notifications"]
        });
        ResourceEngine.register({
            id: "gaming-proc-4242",
            owner: "gaming",
            resource: "gpu-vram",
            amount: 6144,
            priority: "foreground",
            label: "portal",
            origin: "dynamic"
        });
        ProfileEngine.activate("gaming", "probe");

        if (!root.check(root.tile.gaming, "the tile reads the gaming profile by id"))
            return;
        if (!root.checkEqual(root.tile.runningName, "Portal", "the claim's process name matches a scanned game"))
            return;
        if (!root.checkEqual(root.tile.vramChip, "VRAM freed: 6.0 GB", "the claim's memory is named in gigabytes"))
            return;
        if (!root.check(root.hasVisibleLabel("Game mode"), "the game mode chip is shown while the profile runs"))
            return;
        if (!root.check(root.hasVisibleLabel("VRAM freed: 6.0 GB"), "the VRAM chip is shown while the claim exists"))
            return;
        console.log(`DEBUG heights recents=${root.tile.implicitHeight}`);
        if (!root.check(root.tile.implicitHeight <= 260,
            `the now-playing block has to fit the notch: it came to ${root.tile.implicitHeight}px`))
            return;
        if (!root.check(root.tile.elapsed.length > 0, "the elapsed read has something to say while a game runs"))
            return;
        if (!root.checkEqual(root.visibleCovers(), 0, "no cover row is drawn while a game runs"))
            return;

        // A game the scanner cannot name still gets its process name.
        ResourceEngine.register({
            id: "gaming-proc-4242",
            owner: "gaming",
            resource: "gpu-vram",
            amount: 6144,
            priority: "foreground",
            label: "some_unknown_thing",
            origin: "dynamic"
        });
        if (!root.checkEqual(root.tile.runningName, "some_unknown_thing", "an unmatched process name is still shown"))
            return;

        // ── Back to idle ─────────────────────────────────────────────
        ProfileEngine.deactivate("gaming", "probe");
        if (!root.check(!root.tile.gaming, "the tile stops showing a game once the profile restores"))
            return;
        if (!root.checkEqual(root.tile.vramChip, "", "the claim is gone with the profile"))
            return;

        // destroy() is deferred, so the teardown's deregistration is read
        // on the next turn of the event loop rather than straight after.
        root.tile.destroy();
        root.after(root.finished);
        Qt.callLater(root._continue);
    }

    function finished(): void {
        if (!root.check(!GameLauncherService.surfacesVisible, "a destroyed tile leaves nothing registered"))
            return;

        root.pass("the games notch tile follows the service, the scan and the gaming profile");
    }

    Timer {
        interval: 25000
        running: true
        onTriggered: root.fail("timed out waiting on the service")
    }

    Component.onCompleted: root.run()
}
