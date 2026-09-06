// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.config
import qs.components
import qs.services

// The pet's own action menu (PETS.md §7.1/§8): one row per
// `PluginRegistry.surfacesFor("pet_action")` entry -- terminal + VS Code
// for the pet's own MVP list today, any domain sibling's entries appended
// after, all from the one generic registry every other surface kind
// already normalizes into.
//
// A click on a row loads that entry's component just long enough to run
// its `Component.onCompleted` -- the launch itself -- then tears the
// Loader down again. See `qml/actions/LaunchTerminal.qml` for the plain
// `QtObject` shape every entry's component takes; there is nothing here
// for a headless action to persist.
//
// No dismiss-on-outside-click: Pet.qml's `maskItem` only ever covers this
// menu's own bounds plus the pet's hitbox while it is open (there is no
// mechanism in this window for masking anything wider), so a click
// anywhere else on the desktop never reaches this surface at all -- there
// is nothing to catch it with. Closing again is clicking the pet a
// second time, the same gesture that opened it.
Item {
    id: root

    required property var actions

    signal triggered

    implicitWidth: row.implicitWidth + Tokens.padding.small * 2
    implicitHeight: row.implicitHeight + Tokens.padding.small * 2

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHigh

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: 0.5
            shadowBlur: 0.5
            shadowVerticalOffset: 2
        }
    }

    // Fire-and-forget: `onLoaded` means the loaded QtObject's own
    // `Component.onCompleted` already ran, so the launch has already
    // happened and there is nothing left to hold this open for.
    Loader {
        id: runner

        onLoaded: runner.source = ""
    }

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: Tokens.spacing.small / 2

        Repeater {
            model: root.actions

            StyledRect {
                id: cell

                required property var modelData

                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: Tokens.rounding.medium
                color: "transparent"

                MaterialIcon {
                    anchors.centerIn: parent
                    text: cell.modelData.icon || "extension"
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: {
                        runner.source = cell.modelData.componentUrl;
                        root.triggered();
                    }
                }
            }
        }
    }
}
