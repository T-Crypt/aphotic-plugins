// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import qs.config
import qs.components
import qs.services
import qs.services.ai
import qs.modules.plugins.pet

// Docked into the Appearance category (see plugin.toml's
// [ui.settings_pane], parent = "appearance"). Every control here writes
// through PetLibrary, which owns settings.json; nothing in this file
// touches a file of its own.
//
// The tiles draw the real pet rather than an icon of one, because a pet
// is retinted to the current theme and a picker that showed a flat glyph
// would be picking blind. They are the
// same components the desktop mounts, held at mood "idle" -- so a tile
// costs one still shape tree and no clock.
ColumnLayout {
    id: root

    readonly property string petsUrl: `file://${PetLibrary.petsDir}`

    // Active is worth spelling out, because on a quiet desktop it resolves
    // to nothing and the row would otherwise look like a setting that had
    // not taken.
    readonly property string dictationDescription: {
        const base = qsTr("Which session dictation types into. Nothing dictates yet: the mic is still being built.");
        if (PetLibrary.dictationTarget.length > 0)
            return base;
        const live = PetLibrary.dictationHarness;
        if (live.length === 0)
            return `${base} ${qsTr("No session is running, so Active has nothing to aim at.")}`;
        const label = AgentRoles.harnesses.find(h => h.id === live)?.label ?? live;
        return `${base} ${qsTr("Active is %1 right now.").arg(label)}`;
    }

    readonly property var choices: {
        const list = [];

        for (const b of PetLibrary.bundled)
            list.push({
                id: b.id,
                name: b.name,
                description: b.description,
                kind: "bundled",
                pet: b
            });

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
            // A folder whose name is already taken by a pet that ships
            // with the plugin is the same pet installed by hand before it
            // shipped. One tile, and the bundled one is what it picks.
            if (list.some(c => c.id === name))
                continue;
            list.push({
                id: name,
                name: name,
                description: qsTr("An imported sprite sheet."),
                kind: "imported",
                pet: null
            });
        }
        return list;
    }

    spacing: Tokens.spacing.largeIncreased

    // A folder the model refused (see `choices`) is not retried on its own,
    // because the refusal arrives without a change signal for a binding to
    // hang off. Someone who creates their first pet folder and comes back
    // to Settings is the case that matters, and reopening the pane is what
    // they will do, so the ask is made again here.
    onVisibleChanged: {
        if (root.visible)
            imported.folder = root.petsUrl;
    }

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

                    // `selected` has already turned "default" and every
                    // retired id into a real one, so this is a plain match.
                    readonly property bool active: PetLibrary.selected === tile.modelData.id

                    width: 84
                    height: 112
                    radius: Tokens.rounding.large
                    color: tile.active ? Qt.alpha(Colours.palette.m3primary, 0.18) : Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                    Behavior on color {
                        CAnim {}
                    }

                    PetTilePreview {
                        id: preview

                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 8
                        width: 68
                        height: 72
                        petName: tile.modelData.kind === "imported" ? tile.modelData.id : ""
                        bundledPet: tile.modelData.pet
                    }

                    // Only while its sheet is missing or its manifest was
                    // rejected. A tile that shows this is a pet that will
                    // not draw on the desktop either.
                    MaterialIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 30
                        visible: tile.modelData.kind === "imported" && !preview.ready
                        text: "broken_image"
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

    // No shared "Slider" component exists anywhere in core Settings yet,
    // so this is self-contained rather than reaching for one that isn't
    // there -- the same call, for the same reason, the Spectrum plugin's
    // own pane makes.
    component SizeSlider: StyledRect {
        id: slider

        required property string label
        required property string description
        required property real value
        required property real from
        required property real to
        signal moved(real value)

        property bool first: true
        property bool last: true

        readonly property real ratio: Math.max(0, Math.min(1, (slider.value - slider.from) / (slider.to - slider.from)))

        Layout.fillWidth: true
        implicitHeight: sliderContent.implicitHeight + Tokens.padding.large * 2

        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)
        topLeftRadius: slider.first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        topRightRadius: slider.first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        bottomLeftRadius: slider.last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        bottomRightRadius: slider.last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall

        ColumnLayout {
            id: sliderContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: slider.label
                    font: Tokens.font.body.medium
                }

                StyledText {
                    text: `${Math.round(slider.value * 100)}%`
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: slider.description
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }

            StyledRect {
                id: track

                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                implicitHeight: 6
                radius: Tokens.rounding.full
                color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                StyledRect {
                    width: track.width * slider.ratio
                    height: parent.height
                    radius: parent.radius
                    color: Colours.palette.m3primary
                }

                // Whole-track jump, declared first so the handle's own
                // drag area (declared after, below) sits on top of it
                // where they overlap -- a direct click on the handle
                // drags instead of jumping out from under the pointer.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => slider.moved(slider.from + Math.max(0, Math.min(1, mouse.x / track.width)) * (slider.to - slider.from))
                }

                StyledRect {
                    id: handle

                    width: 16
                    height: 16
                    radius: 8
                    color: Colours.palette.m3primary
                    y: (track.height - height) / 2
                    x: track.width * slider.ratio - width / 2

                    MouseArea {
                        id: dragArea

                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true

                        function apply(mx: real): void {
                            const local = mapToItem(track, mx, 0).x;
                            const ratio = Math.max(0, Math.min(1, local / track.width));
                            slider.moved(slider.from + ratio * (slider.to - slider.from));
                        }

                        onPressed: mouse => dragArea.apply(mouse.x)
                        onPositionChanged: mouse => {
                            if (dragArea.pressed)
                                dragArea.apply(mouse.x);
                        }
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

        SizeSlider {
            label: qsTr("Size")
            description: qsTr("How big the pet is drawn, over whatever size its own art asks for.")
            value: PetLibrary.userScale
            from: PetLibrary.minScale
            to: PetLibrary.maxScale
            onMoved: value => PetLibrary.setScale(value)
        }

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

        // Only for a pet that declares which of its colours are the
        // recolourable ones. A sheet that says nothing about its own
        // accents has nothing this could safely repaint.
        SettingsToggleRow {
            icon: "palette"
            visible: PetLibrary.themeable
            label: qsTr("Wear the theme")
            description: qsTr("Retint the pet's accent colours to match the current theme.")
            checked: PetLibrary.tinted
            onToggled: state => PetLibrary.setTinted(state)
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
        text: qsTr("Agent")
        font: Tokens.font.title.small
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("The pet watches your coding sessions and shows what they are doing. These two say which session it means and where it gets its answers.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsPresetRow {
            icon: "mic"
            label: qsTr("Dictation target")
            description: root.dictationDescription
            presets: PetLibrary.dictationTargets.map(t => ({
                value: t.id,
                label: t.label
            }))
            value: PetLibrary.dictationTarget
            onSelected: value => PetLibrary.setDictationTarget(value)
        }

        SettingsPresetRow {
            icon: "psychology"
            label: qsTr("Pet backend")
            description: qsTr("Mirroring means the pet has no answers of its own and shows you the session instead. A local assistant that holds its own conversation needs Ollama and is not built yet.")
            presets: PetLibrary.backends.map(b => ({
                value: b.id,
                label: b.label,
                enabled: b.available
            }))
            value: PetLibrary.backend
            onSelected: value => PetLibrary.setBackend(value)
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Pets of your own go in ~/.config/aphotic/pets/ as a sprite sheet and a small manifest. A folder drawn as a broken image has a manifest this cannot read.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
    }
}
