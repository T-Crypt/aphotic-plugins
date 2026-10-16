// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.skills

// The selected skill: its metadata, its SKILL.md, and the controls that
// write to the CLI. Deploy state per agent is the same chip the list uses,
// so a click means the same thing wherever it is made.
StyledRect {
    id: root

    required property var skill

    property string tagDraft: ""

    readonly property alias agentChipCount: previewAgentChips.count
    readonly property alias tagChipCount: previewTagChips.count

    radius: Tokens.rounding.large
    color: Colours.signalStyle.raised
    border.width: 1
    border.color: Colours.signalStyle.hairline

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "extension"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                Layout.fillWidth: true
                text: root.skill?.name ?? ""
                color: Colours.palette.m3onSurface
                font: Tokens.font.label.large
                elide: Text.ElideRight
            }

            StyledRect {
                implicitWidth: refreshLabel.implicitWidth + Tokens.padding.small * 2
                implicitHeight: 26
                radius: Tokens.rounding.full
                color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)
                opacity: SkillsService.busy ? 0.6 : 1

                StyledText {
                    id: refreshLabel
                    anchors.centerIn: parent
                    text: "Reload"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    disabled: SkillsService.busy
                    onClicked: SkillsService.showSkill(root.skill?.name ?? "")
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: (root.skill?.path ?? "").length > 0
            text: root.skill?.path ?? ""
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
            elide: Text.ElideMiddle
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Deployed to")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Repeater {
                id: previewAgentChips

                model: SkillsService.installedAgents

                AgentChip {
                    required property var modelData

                    record: root.skill
                    agent: modelData
                }
            }
        }

        // Tags: the chips in the list are the read side, this field is the
        // write side. Enter adds, the x on a chip removes.
        StyledText {
            Layout.fillWidth: true
            text: qsTr("Tags")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Repeater {
                id: previewTagChips

                model: root.skill?.tags ?? []

                StyledRect {
                    required property var modelData
                    implicitWidth: tagRow.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: 26
                    radius: Tokens.rounding.full
                    color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)
                    border.width: 1
                    border.color: Colours.signalStyle.hairline

                    RowLayout {
                        id: tagRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            text: `#${modelData}`
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }

                        MaterialIcon {
                            text: "close"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
                            opacity: SkillsService.busy ? 0.5 : 1

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -Tokens.padding.extraSmall
                                enabled: !SkillsService.busy
                                onClicked: SkillsService.removeTag(root.skill?.name ?? "", modelData)
                            }
                        }
                    }
                }
            }
        }

        TextField {
            id: tagField

            Layout.fillWidth: true
            Layout.preferredHeight: 32
            placeholderText: qsTr("Add a tag")
            text: root.tagDraft
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurface
            enabled: !SkillsService.busy
            onTextChanged: root.tagDraft = tagField.text
            onAccepted: {
                const tag = root.tagDraft.trim();
                if (tag.length === 0)
                    return;
                SkillsService.addTag(root.skill?.name ?? "", tag);
                root.tagDraft = "";
                tagField.text = "";
            }
            background: StyledRect {
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainer
                border.width: 1
                border.color: tagField.activeFocus ? Colours.palette.m3primary : Colours.signalStyle.hairline
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Colours.signalStyle.hairline
        }

        StyledText {
            Layout.fillWidth: true
            visible: SkillsService.preview === null && SkillsService.previewName.length > 0
            text: SkillsService.busy ? qsTr("Reading the skill…") : qsTr("No SKILL.md was returned for this skill.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            StyledText {
                id: body

                width: parent.width
                text: SkillsService.preview?.markdown ?? ""
                textFormat: Text.MarkdownText
                color: Colours.palette.m3onSurface
                font: Tokens.font.label.small
                wrapMode: Text.Wrap
            }
        }
    }
}
