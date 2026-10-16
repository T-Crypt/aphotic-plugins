// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.skills

// The AI page's Skill Manager section. It docks under `ai` rather than
// claiming a rail slot, and it is read-mostly: the only writes here are the
// ones that have no other home (adopt, preset deploy), because the plane is
// where a single skill is deployed.
ColumnLayout {
    id: root

    spacing: Tokens.spacing.largeIncreased

    readonly property alias agentRowCount: agentRows.count
    readonly property alias presetRowCount: presetRows.count

    Component.onCompleted: SkillsService.refresh()

    StyledText {
        text: qsTr("Skill Manager")
        font: Tokens.font.title.large
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("One library of agent skills, shared by every agent on this machine.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.small
    }

    // ── The binary ──────────────────────────────────────────────────

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Command line tool")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsRow {
                icon: "terminal"
                label: SkillsService.available ? qsTr("skills-manager-cli") : qsTr("skills-manager-cli is not installed")
                description: SkillsService.available
                    ? qsTr("version %1, from %2").arg(SkillsService.cliVersion).arg(SkillsService.cliSource)
                    : qsTr("The pane stays dark until it resolves.")

                StyledText {
                    visible: SkillsService.available && !SkillsService.versionMatches
                    text: qsTr("pin is %1").arg(SkillsService.pinnedVersion)
                    color: Colours.palette.m3error
                    font: Tokens.font.label.small
                }
            }

            SettingsRow {
                icon: "folder"
                label: qsTr("Library")
                description: SkillsService.available
                    ? qsTr("%1 skills in %2").arg(SkillsService.skillCount).arg(SkillsService.libraryPath)
                    : qsTr("unknown until the tool resolves")
                last: true
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !SkillsService.available && SkillsService.hint.length > 0
            wrapMode: Text.Wrap
            text: SkillsService.hint
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        StyledText {
            Layout.fillWidth: true
            visible: SkillsService.errorText.length > 0
            wrapMode: Text.Wrap
            text: `⚠ ${SkillsService.errorText}`
            color: Colours.palette.m3error
            font: Tokens.font.label.small
        }
    }

    // ── Agents ──────────────────────────────────────────────────────

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        visible: SkillsService.available

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Agents on this machine")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            Repeater {
                id: agentRows

                model: SkillsService.installedAgents

                delegate: SettingsRow {
                    required property var modelData
                    required property int index

                    icon: "smart_toy"
                    label: modelData.display_name
                    description: modelData.skills_dir
                    first: index === 0
                    last: index === SkillsService.installedAgents.length - 1

                    StyledText {
                        text: modelData.category
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }
    }

    // ── Presets ─────────────────────────────────────────────────────

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        visible: SkillsService.available && SkillsService.presets.length > 0

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Presets")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            Repeater {
                id: presetRows

                model: SkillsService.presets

                delegate: SettingsRow {
                    id: presetRow

                    required property var modelData
                    required property int index

                    icon: "bookmark"
                    label: modelData.name
                    description: qsTr("%1 skills · %2").arg(modelData.skill_count).arg(modelData.description ?? "")
                    first: index === 0
                    last: index === SkillsService.presets.length - 1

                    // Deploy and undeploy are shown as a pair because the
                    // preset list does not report whether it is deployed,
                    // and a toggle that guesses would be wrong after any
                    // change made outside this pane.
                    RowLayout {
                        spacing: Tokens.spacing.extraSmall

                        StyledRect {
                            implicitWidth: activeLabel.implicitWidth + Tokens.padding.small * 2
                            implicitHeight: 26
                            radius: Tokens.rounding.full
                            visible: presetRow.modelData.active === true
                            color: Qt.alpha(Colours.palette.m3primary, 0.16)

                            StyledText {
                                id: activeLabel
                                anchors.centerIn: parent
                                text: qsTr("active")
                                color: Colours.palette.m3primary
                                font: Tokens.font.label.small
                            }
                        }

                        StyledRect {
                            implicitWidth: deployLabel.implicitWidth + Tokens.padding.small * 2
                            implicitHeight: 26
                            radius: Tokens.rounding.full
                            color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)
                            opacity: SkillsService.busy ? 0.6 : 1

                            StyledText {
                                id: deployLabel
                                anchors.centerIn: parent
                                text: qsTr("Deploy")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }

                            StateLayer {
                                anchors.fill: parent
                                radius: parent.radius
                                disabled: SkillsService.busy
                                onClicked: SkillsService.deployPreset(presetRow.modelData.name)
                            }
                        }

                        StyledRect {
                            implicitWidth: undeployLabel.implicitWidth + Tokens.padding.small * 2
                            implicitHeight: 26
                            radius: Tokens.rounding.full
                            color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)
                            opacity: SkillsService.busy ? 0.6 : 1

                            StyledText {
                                id: undeployLabel
                                anchors.centerIn: parent
                                text: qsTr("Undeploy")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }

                            StateLayer {
                                anchors.fill: parent
                                radius: parent.radius
                                disabled: SkillsService.busy
                                onClicked: SkillsService.undeployPreset(presetRow.modelData.name)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Maintenance ─────────────────────────────────────────────────

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        visible: SkillsService.available

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Library")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsRow {
                icon: "download"
                label: qsTr("Adopt skills your agents already have")
                description: qsTr("Imports what is already in the agent directories into the library.")

                StyledRect {
                    implicitWidth: adoptLabel.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 30
                    radius: Tokens.rounding.full
                    color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)
                    opacity: SkillsService.busy ? 0.6 : 1

                    StyledText {
                        id: adoptLabel
                        anchors.centerIn: parent
                        text: qsTr("Adopt")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        disabled: SkillsService.busy
                        onClicked: SkillsService.adopt()
                    }
                }
            }

            SettingsRow {
                icon: "refresh"
                label: qsTr("Reload")
                description: SkillsService.lastAction.length > 0 ? qsTr("Last action: %1").arg(SkillsService.lastAction) : qsTr("Re-reads the library from the tool.")
                last: true

                StyledRect {
                    implicitWidth: reloadLabel.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 30
                    radius: Tokens.rounding.full
                    color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)
                    opacity: SkillsService.busy ? 0.6 : 1

                    StyledText {
                        id: reloadLabel
                        anchors.centerIn: parent
                        text: SkillsService.busy ? qsTr("Reading…") : qsTr("Reload")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        disabled: SkillsService.busy
                        onClicked: SkillsService.refresh()
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: qsTr("The library lives where the command line tool puts it, so this pane and the terminal read the same skills. Run 'aphotic skills path --set DIR' to move it.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }
}
