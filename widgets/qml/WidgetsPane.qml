// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import "Catalog.js" as Catalog

ColumnLayout {
    id: root

    spacing: Tokens.spacing.small

    SettingsRow {
        icon: "dashboard_customize"
        label: WidgetsStore.editing ? qsTr("Finish editing") : qsTr("Edit widgets")
        description: qsTr("%1 placed, %2 to choose from. SUPER+ALT+W toggles edit mode from anywhere.").arg(WidgetsStore.widgets.length).arg(Catalog.TYPES.length)
        activatable: true
        onActivated: WidgetsStore.toggleEdit()
    }

    SettingsToggleRow {
        icon: "fullscreen"
        label: qsTr("Hide behind fullscreen windows")
        description: qsTr("Widgets on a screen with a fullscreen window stop drawing and updating until it leaves.")
        checked: WidgetsStore.hideWhenCovered
        onToggled: state => WidgetsStore.setHideWhenCovered(state)
    }
}
