// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.services.profile

ColumnLayout {
    id: root

    // The notch reads this off whichever tiles are loaded to badge the
    // collapsed pill.
    readonly property bool attention: root.driftDetected

    readonly property var claims: ResourceEngine.claimsOf(DevProfile.profileId)
    readonly property string phase: ProfileEngine.phaseOf(DevProfile.profileId)

    // Read from core rather than from a drift-detector plugin: two `dev`
    // plugins are siblings, and this tile depending on one of them is the
    // dependency the layer model forbids. Drift is the `dev` layer's own
    // baseline in DevDrift.qml, so the tile and any later Dev surface get
    // one answer.
    readonly property bool driftDetected: DevDrift.detected

    spacing: Tokens.spacing.small

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: DevProfile.active ? "folder_code" : "folder_off"
            color: DevProfile.active ? Colours.palette.m3primaryOnSurface : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.large
            fill: DevProfile.active ? 1 : 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: DevProfile.active ? DevProfile.activeProjectName : qsTr("No project open")
                color: DevProfile.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.title.builders.medium.weight(Font.Medium).build()
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: DevProfile.active
                text: DevProfile.activeProjectPath
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideMiddle
            }
        }

        StyledRect {
            implicitWidth: phaseLabel.implicitWidth + Tokens.padding.small * 2
            implicitHeight: 20
            radius: Tokens.rounding.full
            color: Colours.palette.m3secondaryContainer

            StyledText {
                id: phaseLabel

                anchors.centerIn: parent
                text: root.phase
                color: Colours.palette.m3onSecondaryContainer
                font: Tokens.font.label.builders.small.weight(Font.Medium).build()
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.claims.length > 0
        spacing: Tokens.spacing.extraSmall

        StyledText {
            text: qsTr("Resource claims")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        Repeater {
            model: root.claims

            RowLayout {
                id: claimRow

                required property var modelData

                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: claimRow.modelData.resource
                    elide: Text.ElideRight
                    font: Tokens.font.body.small
                }

                StyledText {
                    text: `${claimRow.modelData.amount}`
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.mono.small
                }
            }
        }
    }

    Loader {
        Layout.fillWidth: true
        active: root.driftDetected

        sourceComponent: RowLayout {
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "warning"
                color: Colours.palette.m3error
                fontStyle: Tokens.font.icon.small
                fill: 1
            }

            StyledText {
                Layout.fillWidth: true
                text: DevDrift.summary
                color: Colours.palette.m3error
                font: Tokens.font.label.medium
                elide: Text.ElideRight
            }
        }
    }
}
