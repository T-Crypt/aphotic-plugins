// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.gameLauncher

// The game library on the workspace plane. The host owns the window,
// the rail, the reveal motion and the close behaviour; this Item only
// fills the pane it is given.
//
// Nothing here polls. The list comes from the service's last scan
// (boot or an explicit Rescan); the covers load lazily as grid cells
// appear. Big picture mode is a state of this surface, not a window.
Item {
    id: root

    property string bigPictureMode: "grid" // "grid" | "bigpicture"
    property string activeTab: "All"
    property string searchText: ""
    property int selectedIndex: 0

    readonly property var sourceTabs: root._tabs()

    function _tabs() {
        const tabs = ["All", "Favorites"];
        for (const game of GameLauncherService.games) {
            if (!tabs.includes(game.source))
                tabs.push(game.source);
        }
        return tabs;
    }

    // What the grid shows: tab filter, then search filter.
    readonly property var visibleGames: root._visibleGames()

    function _visibleGames() {
        let list = GameLauncherService.games.slice();
        if (root.activeTab === "Favorites")
            list = list.filter(g => g.favorite);
        else if (root.activeTab !== "All")
            list = list.filter(g => g.source === root.activeTab);
        const needle = root.searchText.trim().toLowerCase();
        if (needle.length > 0)
            list = list.filter(g => g.name.toLowerCase().includes(needle));
        return list;
    }

    function launchSelected(game) {
        if (game)
            GameLauncherService.launch(game);
    }

    // Keyboard walk, one handler for every key: the root holds focus
    // so character keys (F) reach it as well. The selection is an
    // index into visibleGames; arrows move it, Enter launches, F
    // swaps to big picture, and Esc in big picture returns to the
    // grid. An Esc in grid mode is deliberately ignored: it falls
    // through to the host, which closes the plane.
    focus: true
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Left) {
            root._moveSelection(-1)
        } else if (event.key === Qt.Key_Right) {
            root._moveSelection(1)
        } else if (event.key === Qt.Key_Up) {
            root._moveSelection(-root.columns())
        } else if (event.key === Qt.Key_Down) {
            root._moveSelection(root.columns())
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            const game = root.visibleGames[root.selectedIndex]
            if (game)
                GameLauncherService.launch(game)
        } else if (event.key === Qt.Key_F) {
            if (root.bigPictureMode === "grid")
                root.bigPictureMode = "bigpicture"
        } else if (event.key === Qt.Key_Escape) {
            if (root.bigPictureMode === "bigpicture")
                root.bigPictureMode = "grid"
        }
    }

    function columns() {
        return Math.max(1, Math.floor((root.width + gridView.horizontalSpacing) / (gridView.cellWidth + gridView.horizontalSpacing)));
    }

    function _moveSelection(delta) {
        if (root.visibleGames.length === 0)
            return;
        const next = root.selectedIndex + delta;
        root.selectedIndex = Math.max(0, Math.min(root.visibleGames.length - 1, next));
    }

    onVisibleGamesChanged: {
        if (root.selectedIndex >= root.visibleGames.length)
            root.selectedIndex = 0;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // ── Header ──────────────────────────────────────────────────

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "sports_esports"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.medium
            }

            ColumnLayout {
                spacing: 0

                StyledText {
                    text: qsTr("Games")
                    font: Tokens.font.title.small
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: GameLauncherService.scanning
                        ? qsTr("Scanning…")
                        : qsTr("%1 games · %2").arg(GameLauncherService.games.length).arg(
                            GameLauncherService.lastScanned
                                ? Qt.formatDateTime(GameLauncherService.lastScanned, "HH:mm")
                                : qsTr("not scanned yet"))
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            Item {
                Layout.fillWidth: true
            }

            TextField {
                id: searchField

                Layout.preferredWidth: 220
                Layout.preferredHeight: 34
                placeholderText: qsTr("Search")
                text: root.searchText
                onTextChanged: {
                    root.searchText = searchField.text;
                    root.selectedIndex = 0;
                }
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurface
                background: StyledRect {
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainer
                    border.width: 1
                    border.color: searchField.activeFocus ? Colours.palette.m3primary : Colours.signalStyle.hairline
                }
            }

            StyledRect {
                implicitWidth: rescanLabel.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: 34
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainer
                border.width: 1
                border.color: Colours.signalStyle.hairline
                opacity: GameLauncherService.scanning ? 0.6 : 1

                StyledText {
                    id: rescanLabel
                    anchors.centerIn: parent
                    text: GameLauncherService.scanning ? qsTr("Scanning…") : qsTr("Rescan")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: GameLauncherService.scan()
                }
            }

            // Steam Big Picture: a quick action, only when the client
            // is on the machine.
            StyledRect {
                visible: typeof GameLauncherService.clients.steam === "string"
                    && GameLauncherService.clients.steam.length > 0
                implicitWidth: bpLabel.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: 34
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainer
                border.width: 1
                border.color: Colours.signalStyle.hairline

                StyledText {
                    id: bpLabel
                    anchors.centerIn: parent
                    text: qsTr("Steam Big Picture")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: GameLauncherService.launchSteamBigPicture()
                }
            }
        }

        // ── Source tabs ─────────────────────────────────────────────

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: root.sourceTabs

                delegate: StyledRect {
                    id: tab

                    required property var modelData
                    implicitWidth: tabLabel.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 28
                    radius: Tokens.rounding.full
                    color: root.activeTab === tab.modelData
                        ? Qt.alpha(Colours.palette.m3primary, 0.16)
                        : Colours.palette.m3surfaceContainer
                    border.width: 1
                    border.color: root.activeTab === tab.modelData
                        ? Colours.palette.m3primary
                        : Colours.signalStyle.hairline

                    StyledText {
                        id: tabLabel
                        anchors.centerIn: parent
                        text: tab.modelData
                        color: root.activeTab === tab.modelData
                            ? Colours.palette.m3primary
                            : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        onClicked: {
                            root.activeTab = tab.modelData;
                            root.selectedIndex = 0;
                        }
                    }
                }
            }
        }

        // ── Content ─────────────────────────────────────────────────

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Empty state: one honest line, no decoration.
            ColumnLayout {
                anchors.centerIn: parent
                spacing: Tokens.spacing.small
                visible: root.visibleGames.length === 0

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: GameLauncherService.lastError.length > 0
                        ? qsTr("The last scan failed: %1").arg(GameLauncherService.lastError)
                        : qsTr("No games found. Enable a source or add a manual game in Settings, Power and Security, Games.")
                    wrapMode: Text.Wrap
                    width: parent.width * 0.7
                    horizontalAlignment: Text.AlignHCenter
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            // Grid mode.
            GridView {
                id: gridView

                anchors.fill: parent
                visible: root.bigPictureMode === "grid" && root.visibleGames.length > 0
                clip: true
                model: root.visibleGames
                cellWidth: Math.max(140, Math.floor(root.width / Math.max(2, Math.floor(root.width / 220))))
                cellHeight: Math.floor(gridView.cellWidth * 1.4)
                // Qt6 GridView has no spacing properties and no direction
                // properties: the default LeftToRight flow is what we want,
                // and cell gaps come from the delegate sizing, not spacing.

                delegate: GameCard {
                    required property var modelData
                    required property int index

                    width: gridView.cellWidth
                    height: gridView.cellHeight
                    game: modelData
                }
            }

            // Big picture mode.
            BigPictureView {
                anchors.fill: parent
                visible: root.bigPictureMode === "bigpicture"
                games: root.visibleGames
                index: root.selectedIndex
            }
        }
    }
}
