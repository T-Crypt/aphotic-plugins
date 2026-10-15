// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// The Settings section body. The host wraps this in a SettingsSection, so
// this is the body of one collapsed expander rather than a pane of its
// own. Plugins never become a rail entry.
//
// It edits the plugin's own config file and reads no shell setting, so
// there is nothing here for `aphotic plugin remove` to clean up in
// settings.json.
ColumnLayout {
    id: root

    spacing: Tokens.spacing.medium

    readonly property color textPrimary: Colours.palette.m3onSurface
    readonly property color textMuted: Colours.palette.m3onSurfaceVariant

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Two settings, both per-machine. They are written to ~/.config/aphotic/plugins/ios-dev/config and read by `aphotic ios new`.")
        font: Tokens.font.label.small
        color: root.textMuted
    }

    // Bundle prefix and apps folder live in a shell file because the CLI
    // sources them. A Settings pane that wrote JSON here would need the
    // CLI to parse JSON, and one more format for one file is not worth it.
    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "tune"
            label: qsTr("Bundle ID prefix")
            description: qsTr("New apps get <prefix>.<AppName>. Change it to a domain you control.")

            StyledText {
                text: qsTr("Edit ~/.config/aphotic/plugins/ios-dev/config, or run `aphotic ios setup`")
                font: Tokens.font.label.small
                color: root.textMuted
            }
        }

        SettingsRow {
            icon: "folder_open"
            label: qsTr("Apps folder")
            description: qsTr("Where `aphotic ios new` creates each app.")

            StyledText {
                text: qsTr("Edit ~/.config/aphotic/plugins/ios-dev/config, or run `aphotic ios setup`")
                font: Tokens.font.label.small
                color: root.textMuted
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("The Darwin SDK is the one step no script can finish: it ships inside Apple's Xcode archive, and that download needs a signed-in browser. `aphotic ios doctor` names the Xcode your Swift needs.")
        font: Tokens.font.label.small
        color: root.textMuted
    }
}
