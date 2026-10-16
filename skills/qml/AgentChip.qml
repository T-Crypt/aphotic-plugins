// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.skills

// One agent and whether it holds this skill. Clicking flips that state.
//
// The deployed state is read from the skill record rather than from
// SkillsService.isDeployed(), because that function is not a property: a
// binding to it would never re-evaluate. The record is, and a refresh
// replaces every record, so the chips follow the re-read on their own.
StyledRect {
    id: chip

    required property var record
    required property var agent

    readonly property bool deployed: (chip.record?.deployed_to ?? []).includes(chip.agent?.key ?? "")

    implicitWidth: chipRow.implicitWidth + Tokens.padding.small * 2
    implicitHeight: 26
    radius: Tokens.rounding.full
    color: chip.deployed
        ? Qt.alpha(Colours.palette.m3primary, 0.18)
        : Colours.layer(Colours.tPalette.m3surfaceContainer, 2)
    border.width: 1
    border.color: chip.deployed ? Colours.palette.m3primary : Colours.signalStyle.hairline
    opacity: SkillsService.busy ? 0.6 : 1

    RowLayout {
        id: chipRow

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            text: chip.deployed ? "check_circle" : "radio_button_unchecked"
            color: chip.deployed ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.small
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            text: chip.agent?.display_name ?? ""
            color: chip.deployed ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        disabled: SkillsService.busy
        onClicked: SkillsService.toggleDeploy(chip.record?.name ?? "", chip.agent?.key ?? "")
    }
}
