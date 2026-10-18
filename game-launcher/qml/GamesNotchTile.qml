// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.services.profile
import qs.modules.plugins.gameLauncher

// The Games tile. While a game runs it reads the gaming profile's phase
// and its VRAM claim through the engines, by profile id only -- this
// plugin never imports the gaming plugin, and with that profile absent
// the tile simply falls through to the list below. Otherwise it offers
// the last few launches and the pinned favourites.
//
// Nothing here scans or reads a file: the list, the launch history and
// the profile state all come from memory, so opening the notch costs
// nothing. The one read that keeps changing is the elapsed clock, and it
// follows this tile's own on-screen registration.
ColumnLayout {
    id: root

    implicitWidth: parent ? parent.width : 240
    spacing: Tokens.spacing.small
    visible: GameLauncherService.settings.tile_enabled

    readonly property string owner: `game-launcher-tile-${Math.random()}`
    readonly property var screenState: QsWindow.window?.screenState ?? null

    onVisibleChanged: GameLauncherService.setSurfaceVisible(root.owner, visible)
    Component.onCompleted: GameLauncherService.setSurfaceVisible(root.owner, visible)
    Component.onDestruction: GameLauncherService.setSurfaceVisible(root.owner, false)

    readonly property var clientNames: ["steam", "lutris", "heroic", "cartridges"]

    readonly property var presentClients: root.clientNames.filter(
        name => typeof GameLauncherService.clients[name] === "string"
            && GameLauncherService.clients[name].length > 0)

    readonly property real coverWidth: Math.max(48, (root.width - Tokens.spacing.extraSmall * 3) / 4)

    // ── Now playing ─────────────────────────────────────────────────────

    readonly property bool gaming: ProfileEngine.isRegistered("gaming") && ProfileEngine.isActive("gaming")

    // The gaming profile's own claim, adopted through the resource
    // engine's PID seam.
    readonly property var gamingClaim: root._gamingClaim()

    function _gamingClaim() {
        return (ResourceEngine.claims ?? []).find(
            claim => claim.owner === "gaming" && claim.resource === "gpu-vram") ?? null;
    }

    // gamemode's PID reaches this plugin through that claim: an adopted
    // claim is id'd <owner>-proc-<pid> and labelled with the process name
    // the driver reported. No claimed GPU memory means no PID to name, and
    // the line then says only what it knows.
    readonly property string processName: root.gamingClaim?.label ?? ""
    readonly property string runningName: root._matchGame(root.processName) || root.processName

    function _matchGame(process) {
        if (!process)
            return "";
        const name = process.toLowerCase();
        const base = name.replace(/\.(exe|sh|appimage)$/, "");
        for (const game of GameLauncherService.games) {
            const title = game.name.toLowerCase();
            if (title === name || title === base)
                return game.name;
            if (game.exec && game.exec.toLowerCase().includes(base))
                return game.name;
            if (base.length >= 5 && title.includes(base))
                return game.name;
        }
        return "";
    }

    // The profile records the moment of its last phase change, which for
    // the gaming profile is the apply that starts the session.
    readonly property double gamingSince: ProfileEngine.states["gaming"]?.since ?? 0

    // Zero while this tile is off screen, so the elapsed text stops
    // recomputing with the registration and picks the clock up again on
    // reopen. It reads the shell's own clock, which the bar already runs.
    readonly property double clock: GameLauncherService.surfacesVisible ? Time.date.getTime() : 0
    readonly property string elapsed: root._formatElapsed(root.gamingSince, root.clock)

    function _formatElapsed(since, now) {
        if (!since || !now)
            return "";
        let left = Math.max(0, Math.floor((now - since) / 1000));
        const hours = Math.floor(left / 3600);
        left -= hours * 3600;
        const minutes = Math.floor(left / 60);
        const seconds = left - minutes * 60;
        if (hours > 0)
            return `${hours}h ${minutes}m`;
        if (minutes > 0)
            return `${minutes}m ${seconds}s`;
        return `${seconds}s`;
    }

    readonly property string vramChip: root.gamingClaim
        ? qsTr("Game VRAM: %1 GB").arg((root.gamingClaim.amount / 1024).toFixed(1))
        : ""

    // ── Jump back in / pinned ───────────────────────────────────────────

    // Neither list is drawn while a game runs, so no cover image loads for
    // a row nobody is looking at.
    readonly property var recent: root.gaming ? [] : GameLauncherService.recentGames
    readonly property var pinned: root.gaming ? [] : GameLauncherService.favoriteGames
        .filter(game => !root.recent.some(seen => seen.name === game.name && seen.source === game.source))
        .slice(0, 4)

    component Pill: StyledRect {
        id: pill

        required property string label
        property string icon: ""

        signal activated

        implicitWidth: pillRow.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: 26
        radius: Tokens.rounding.full
        color: Colours.palette.m3surfaceContainer
        border.width: 1
        border.color: Colours.signalStyle.hairline

        Row {
            id: pillRow

            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: pill.icon.length > 0
                text: pill.icon
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                color: Colours.palette.m3onSurface
                font: Tokens.font.label.small
            }
        }

        StateLayer {
            anchors.fill: parent
            radius: parent.radius
            onClicked: pill.activated()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "sports_esports"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.small
        }

        StyledText {
            text: qsTr("Games")
            font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
            color: Colours.palette.m3onSurface
        }

        StyledText {
            visible: GameLauncherService.games.length > 0
            text: qsTr("%1").arg(GameLauncherService.games.length)
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }

        Item {
            Layout.fillWidth: true
        }

        // Big Picture only exists where the service found a Steam client
        // that reports it.
        Pill {
            visible: GameLauncherService.bigPicture
            label: qsTr("Big Picture")
            icon: "tv"
            onActivated: GameLauncherService.launchSteamBigPicture()
        }

        Pill {
            label: qsTr("Library")
            icon: "space_dashboard"
            onActivated: GameLauncherService.openLibrary(root.screenState)
        }
    }

    // ── Now playing ─────────────────────────────────────────────────────

    StyledRect {
        Layout.fillWidth: true
        visible: root.gaming
        implicitHeight: nowColumn.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainer
        border.width: 1
        border.color: Colours.signalStyle.hairline

        ColumnLayout {
            id: nowColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.padding.small
            spacing: Tokens.spacing.extraSmall

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Now playing")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.runningName.length > 0 ? root.runningName : qsTr("A game is running")
                color: Colours.palette.m3onSurface
                font: Tokens.font.title.builders.medium.weight(Font.Medium).build()
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.elapsed.length > 0
                text: root.elapsed
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.mono.small
            }

            Row {
                spacing: Tokens.spacing.extraSmall

                Pill {
                    label: qsTr("Game mode")
                }

                Pill {
                    visible: DoNotDisturb.enabled
                    label: qsTr("Do not disturb")
                }

                Pill {
                    visible: root.vramChip.length > 0
                    label: root.vramChip
                }
            }
        }
    }

    // ── Jump back in / pinned ───────────────────────────────────────────

    StyledText {
        Layout.fillWidth: true
        visible: !root.gaming && root.recent.length > 0
        text: qsTr("Jump back in")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
    }

    Row {
        Layout.fillWidth: true
        visible: !root.gaming && root.recent.length > 0
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: root.recent

            delegate: GameCoverTile {
                required property var modelData

                width: root.coverWidth
                height: 88
                game: modelData
                onActivated: GameLauncherService.launch(modelData, root.screenState)
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: !root.gaming && root.pinned.length > 0
        text: qsTr("Pinned")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
    }

    Row {
        Layout.fillWidth: true
        visible: !root.gaming && root.pinned.length > 0
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: root.pinned

            delegate: GameCoverTile {
                required property var modelData

                width: root.coverWidth
                height: 88
                game: modelData
                onActivated: GameLauncherService.launch(modelData, root.screenState)
            }
        }
    }

    // Nothing launched yet and nothing pinned: one honest line, and the
    // client buttons below still do something useful.
    StyledText {
        Layout.fillWidth: true
        visible: !root.gaming && root.recent.length === 0 && root.pinned.length === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: GameLauncherService.scanning
            ? qsTr("Scanning your installed games…")
            : qsTr("No recent games yet. Launch one and it shows up here.")
        font: Tokens.font.label.small
        color: Colours.palette.m3onSurfaceVariant
    }

    // ── Store clients ───────────────────────────────────────────────────

    // One row of client buttons, laid out to fill the tile width.
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: root.presentClients

            delegate: StyledRect {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Tokens.rounding.medium
                color: Colours.palette.m3surfaceContainer
                border.width: 1
                border.color: Colours.signalStyle.hairline

                StyledText {
                    anchors.centerIn: parent
                    text: root._clientLabel(modelData)
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: GameLauncherService.launchClient(modelData)
                }
            }
        }
    }

    // No store client at all: one honest line, the rest of the tile
    // stays empty.
    StyledText {
        Layout.fillWidth: true
        visible: root.presentClients.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: qsTr("No store clients found. Steam, Lutris, Heroic or Cartridges will appear here once installed.")
        wrapMode: Text.Wrap
        font: Tokens.font.label.small
        color: Colours.palette.m3onSurfaceVariant
    }

    function _clientLabel(name) {
        const labels = ({ steam: "Steam", lutris: "Lutris", heroic: "Heroic", cartridges: "Cartridges" });
        return labels[name] ?? name;
    }
}
