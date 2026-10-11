// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.gameLauncher

// The Games section, docked into Power and Security. The host's
// SettingsSection already draws the header (icon and label); this body holds
// the four groups the reference launcher kept in its own settings window:
// sources, covers, behaviour, the notch tile. Every value persists to the
// plugin's own settings file through the service; nothing here writes a core
// Settings key. Controls are the shared Settings* family; the two free-text
// fields save on focus-out so typing never rewrites the settings file.
ColumnLayout {
    id: root

    implicitWidth: parent ? parent.width : 460
    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Game Launcher")
        font: Tokens.font.title.large
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Where your games come from, how their covers load, and how the launcher behaves. Everything is stored in this plugin's own settings; nothing here touches the rest of Aphotic.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    // ── Sources ─────────────────────────────────────────────────────

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Sources")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsToggleRow {
            icon: "sports_esports"
            label: qsTr("Steam")
            description: qsTr("Library and shortcuts")
            checked: GameLauncherService.settings.sources.steam
            onToggled: state => GameLauncherService.setSource("steam", state)
        }

        SettingsToggleRow {
            icon: "sports_esports"
            label: qsTr("Lutris")
            description: qsTr("Games installed through Lutris")
            checked: GameLauncherService.settings.sources.lutris
            onToggled: state => GameLauncherService.setSource("lutris", state)
        }

        SettingsToggleRow {
            icon: "sports_esports"
            label: qsTr("Heroic")
            description: qsTr("Epic, GOG, Amazon and sideloaded games")
            checked: GameLauncherService.settings.sources.heroic
            onToggled: state => GameLauncherService.setSource("heroic", state)
        }

        SettingsToggleRow {
            icon: "sports_esports"
            label: qsTr("Cartridges")
            description: qsTr("Games managed by Cartridges")
            checked: GameLauncherService.settings.sources.cartridges
            onToggled: state => GameLauncherService.setSource("cartridges", state)
        }

        SettingsToggleRow {
            icon: "apps"
            label: qsTr("Desktop entries")
            description: qsTr(".desktop files on the Desktop")
            checked: GameLauncherService.settings.sources.desktop
            onToggled: state => GameLauncherService.setSource("desktop", state)
        }
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "refresh"
            label: qsTr("Rescan")
            description: GameLauncherService.scanning
                ? qsTr("Scanning…")
                : qsTr("%1 games, last scan %2").arg(
                    GameLauncherService.games.length).arg(
                    GameLauncherService.lastScanned
                        ? Qt.formatDateTime(GameLauncherService.lastScanned, "d MMM HH:mm")
                        : qsTr("never"))

            // A lone StyledRect with Layout.preferredWidth would collapse
            // in the row's trailing slot (a plain Item, not a layout); the
            // explicit implicitWidth is what sizes it, as in the core panes.
            StyledRect {
                implicitWidth: rescanLabel.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: 32
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainer
                border.width: 1
                border.color: Colours.signalStyle.hairline
                opacity: GameLauncherService.scanning ? 0.5 : 1

                StyledText {
                    id: rescanLabel
                    anchors.centerIn: parent
                    text: qsTr("Rescan")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    disabled: GameLauncherService.scanning
                    onClicked: GameLauncherService.scan()
                }
            }
        }
    }

    // ── Manual games ────────────────────────────────────────────────

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Manual games")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "text_fields"
            label: qsTr("Title")

            StyledRect {
                implicitWidth: 240
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: manualName
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    activeFocusOnPress: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true

                    StyledText {
                        visible: manualName.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("Minecraft")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SettingsRow {
            icon: "terminal"
            label: qsTr("Launch command")
            description: qsTr("Run as a detached process")

            StyledRect {
                implicitWidth: 240
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: manualExec
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    activeFocusOnPress: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true

                    StyledText {
                        visible: manualExec.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("minecraft-launcher")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SettingsRow {
            icon: "add"
            label: qsTr("Add")
            description: qsTr("Saves the game above and rescans")

            StyledRect {
                implicitWidth: addLabel.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: 32
                radius: Tokens.rounding.full
                color: Colours.palette.m3primary

                StyledText {
                    id: addLabel
                    anchors.centerIn: parent
                    text: qsTr("Add")
                    color: Colours.contrastOn(Colours.palette.m3primary)
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: {
                        if (manualName.text.trim().length > 0 && manualExec.text.trim().length > 0) {
                            GameLauncherService.upsertManual(manualName.text.trim(), manualExec.text.trim(), "");
                            manualName.text = "";
                            manualExec.text = "";
                            GameLauncherService.scan();
                        }
                    }
                }
            }
        }
    }

    SettingsGroup {
        Layout.fillWidth: true
        visible: GameLauncherService.settings.manual.length > 0

        Repeater {
            model: GameLauncherService.settings.manual

            delegate: SettingsRow {
                required property var modelData

                icon: "sports_esports"
                label: modelData.name
                description: modelData.exec

                StyledRect {
                    implicitWidth: removeLabel.implicitWidth + Tokens.padding.medium
                    implicitHeight: 28
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainer

                    StyledText {
                        id: removeLabel
                        anchors.centerIn: parent
                        text: qsTr("Remove")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        onClicked: GameLauncherService.removeManual(modelData.name)
                    }
                }
            }
        }
    }

    // ── Covers ──────────────────────────────────────────────────────

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Covers")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "image"
            label: qsTr("Box art directory")
            description: GameLauncherService.settings.box_art_dir.length > 0
                ? GameLauncherService.settings.box_art_dir
                : qsTr("A file named after the game overrides its cover")

            StyledRect {
                implicitWidth: 240
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: boxArtField
                    property string _boxArt: GameLauncherService.settings.box_art_dir
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    activeFocusOnPress: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true
                    // Local mirror: typing must not rewrite the settings
                    // file on every keystroke; focus-out is the save point.
                    text: boxArtField._boxArt
                    onTextChanged: boxArtField._boxArt = boxArtField.text
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            GameLauncherService.setSetting("box_art_dir", boxArtField.text);
                    }

                    StyledText {
                        visible: boxArtField.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("/home/you/boxart")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SettingsToggleRow {
            icon: "grid_on"
            label: qsTr("SteamGridDB covers")
            description: qsTr("Optional. The only network this plugin makes; needs an API key")
            checked: GameLauncherService.settings.sgdb.enabled
            onToggled: state => GameLauncherService.setSgdb({ enabled: state })
        }

        SettingsRow {
            visible: GameLauncherService.settings.sgdb.enabled
            icon: "key"
            label: qsTr("SteamGridDB API key")
            description: qsTr("Free at the SteamGridDB site")

            StyledRect {
                implicitWidth: 240
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: sgdbKeyField
                    property string _sgdbKey: GameLauncherService.settings.sgdb.api_key
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    activeFocusOnPress: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true
                    text: sgdbKeyField._sgdbKey
                    onTextChanged: sgdbKeyField._sgdbKey = sgdbKeyField.text
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            GameLauncherService.setSgdb({ api_key: sgdbKeyField.text });
                    }

                    StyledText {
                        visible: sgdbKeyField.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("Paste your key")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SettingsToggleRow {
            visible: GameLauncherService.settings.sgdb.enabled
            icon: "animation"
            label: qsTr("Animated covers")
            description: qsTr("Only animate while the library is open")
            checked: GameLauncherService.settings.sgdb.animated
            onToggled: state => GameLauncherService.setSgdb({ animated: state })
        }
    }

    // ── Behavior ────────────────────────────────────────────────────

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Behavior")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "sort"
            label: qsTr("Sort by")
            description: GameLauncherService.settings.sort_by === "recent"
                ? qsTr("Recently played")
                : qsTr("Name")

            // Two chips need a real layout to sit side by side; a bare Item
            // would stack them.
            RowLayout {
                spacing: Tokens.spacing.small

                StyledRect {
                    implicitWidth: recentChip.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 28
                    radius: Tokens.rounding.full
                    color: GameLauncherService.settings.sort_by === "recent"
                        ? Qt.alpha(Colours.palette.m3primary, 0.16)
                        : Colours.palette.m3surfaceContainer
                    border.width: GameLauncherService.settings.sort_by === "recent" ? 0 : 1
                    border.color: Colours.signalStyle.hairline

                    StyledText {
                        id: recentChip
                        anchors.centerIn: parent
                        text: qsTr("Recently played")
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        onClicked: {
                            GameLauncherService.setSetting("sort_by", "recent");
                            GameLauncherService.scan();
                        }
                    }
                }

                StyledRect {
                    implicitWidth: nameChip.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 28
                    radius: Tokens.rounding.full
                    color: GameLauncherService.settings.sort_by === "name"
                        ? Qt.alpha(Colours.palette.m3primary, 0.16)
                        : Colours.palette.m3surfaceContainer
                    border.width: GameLauncherService.settings.sort_by === "name" ? 0 : 1
                    border.color: Colours.signalStyle.hairline

                    StyledText {
                        id: nameChip
                        anchors.centerIn: parent
                        text: qsTr("Name")
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        onClicked: {
                            GameLauncherService.setSetting("sort_by", "name");
                            GameLauncherService.scan();
                        }
                    }
                }
            }
        }

        SettingsToggleRow {
            icon: "star"
            label: qsTr("Favorites first")
            checked: GameLauncherService.settings.favorites_first
            onToggled: state => GameLauncherService.setSetting("favorites_first", state)
        }

        SettingsToggleRow {
            icon: "launch"
            label: qsTr("Close the library on launch")
            checked: GameLauncherService.settings.close_on_launch
            onToggled: state => GameLauncherService.setSetting("close_on_launch", state)
        }
    }

    // ── Notch ───────────────────────────────────────────────────────

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Notch tile")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsToggleRow {
            icon: "sports_esports"
            label: qsTr("Show the Games tile")
            description: qsTr("Quick launch for the installed store clients")
            checked: GameLauncherService.settings.tile_enabled
            onToggled: state => GameLauncherService.setSetting("tile_enabled", state)
        }
    }
}
