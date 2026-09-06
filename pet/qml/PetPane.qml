// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.pet

// Docked into the Appearance category (see plugin.toml's
// [ui.settings_pane], parent = "appearance"). Every control here writes
// through PetLibrary, which owns pet.json; nothing in this file touches a
// file of its own.
//
// The tiles draw the real pet rather than an icon of one, because the
// whole point of a built-in is that it wears the current theme, and a
// picker that showed a flat glyph would be picking blind. They are the
// same components the desktop mounts, held at mood "idle" -- so a tile
// costs one still shape tree and no clock.
ColumnLayout {
    id: root

    readonly property string petsUrl: `file://${PetLibrary.petsDir}`

    readonly property var choices: {
        const list = PetLibrary.builtins.map(b => ({
            id: b.id,
            name: b.name,
            description: b.description,
            imported: false
        }));

        // A FolderListModel pointed at a directory that does not exist
        // quietly keeps listing the one it had, which is the process's
        // working directory -- so on an install with no imported pets the
        // picker would offer the shell's own source folders as pets.
        // Reading `folder` back says whether the ask was taken, and it is
        // read here rather than in a binding of its own because the revert
        // arrives without a change signal: `count` is what wakes this up.
        const found = imported.count;
        if (String(imported.folder) !== root.petsUrl)
            return list;
        for (let i = 0; i < found; i++) {
            const name = imported.get(i, "fileName");
            if (typeof name !== "string" || name.startsWith("."))
                continue;
            list.push({
                id: name,
                name: name,
                description: qsTr("An imported sprite sheet."),
                imported: true
            });
        }
        return list;
    }

    spacing: Tokens.spacing.largeIncreased

    // Read once when the pane is built, and again only when the directory
    // itself changes. A pet folder appearing while the pane is open is
    // rare enough that watching for it is the cheapest way to handle it,
    // and cheaper than the poll the alternative would need.
    FolderListModel {
        id: imported

        folder: root.petsUrl
        showFiles: false
        showDirs: true
        showDotAndDotDot: false
        sortField: FolderListModel.Name
    }

    StyledText {
        text: qsTr("Desktop Pet")
        font: Tokens.font.title.large
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Pick who lives on the wallpaper. Drag the pet with the mouse to move it; it wanders around wherever you drop it, and a click still gets its attention.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    // Declared as a sibling of the SettingsGroup below rather than inside
    // it, matching where PluginsPane.qml declares its own inline
    // components. `first`/`last` are duck-typed by SettingsGroup, so a
    // custom row joins the connected card the same way a SettingsRow does.
    component PetPicker: StyledRect {
        id: picker

        property bool first: true
        property bool last: true

        Layout.fillWidth: true
        implicitHeight: grid.implicitHeight + Tokens.padding.large * 2

        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)
        topLeftRadius: picker.first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        topRightRadius: picker.first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        bottomLeftRadius: picker.last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        bottomRightRadius: picker.last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall

        Flow {
            id: grid

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            Repeater {
                model: root.choices

                StyledRect {
                    id: tile

                    required property var modelData

                    readonly property bool active: PetLibrary.selected === tile.modelData.id || (PetLibrary.selected === "default" && tile.modelData.id === PetLibrary.fallbackBuiltin)

                    width: 84
                    height: 112
                    radius: Tokens.rounding.large
                    color: tile.active ? Qt.alpha(Colours.palette.m3primary, 0.18) : Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                    Behavior on color {
                        CAnim {}
                    }

                    DefaultPet {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 8
                        visible: !tile.modelData.imported
                        petId: tile.modelData.id
                        mood: "idle"
                        phase: 0
                        excitement: 0
                        facing: 1
                        scale: Math.min(1, 68 / Math.max(1, implicitWidth), 72 / Math.max(1, implicitHeight))
                        transformOrigin: Item.Top
                    }

                    MaterialIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 30
                        visible: tile.modelData.imported
                        text: "photo_library"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.large
                    }

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Tokens.padding.small
                        width: parent.width - Tokens.padding.small * 2
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: tile.modelData.name
                        color: tile.active ? Colours.palette.m3primaryOnSurface : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PetLibrary.setPet(tile.modelData.id)
                    }
                }
            }
        }
    }

    component ActionPill: StyledRect {
        id: pill

        required property string text
        signal activated

        implicitWidth: pillLabel.implicitWidth + Tokens.padding.large * 2
        implicitHeight: 30
        radius: Tokens.rounding.full
        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

        StyledText {
            id: pillLabel

            anchors.centerIn: parent
            text: pill.text
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        StateLayer {
            anchors.fill: parent
            radius: parent.radius
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.activated()
        }
    }

    SettingsGroup {
        Layout.fillWidth: true

        PetPicker {}

        SettingsPresetRow {
            icon: "explore"
            label: qsTr("Wandering")
            description: qsTr("How far the pet strays from where you put it.")
            presets: [
                {
                    value: 0,
                    label: qsTr("Stay put")
                },
                {
                    value: 130,
                    label: qsTr("Close")
                },
                {
                    value: 320,
                    label: qsTr("Wide")
                }
            ]
            value: PetLibrary.roam
            onSelected: value => PetLibrary.setRoam(value)
        }

        SettingsToggleRow {
            icon: "lock"
            label: qsTr("Lock in place")
            description: qsTr("Stop the pet being dragged. Clicking it still works.")
            checked: PetLibrary.locked
            onToggled: state => PetLibrary.setLocked(state)
        }

        SettingsRow {
            icon: "recenter"
            label: qsTr("Position")
            description: qsTr("Put the pet back at the bottom centre of every screen.")

            ActionPill {
                text: qsTr("Reset")
                onActivated: PetLibrary.resetHome()
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Pets of your own go in ~/.config/aphotic/pets/ as a sprite sheet and a small manifest. They show up here as soon as the folder exists.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
    }
}
