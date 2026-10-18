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

// One skill in the library list: what it is, where it came from, and which
// agents hold it. Clicking anywhere but a chip selects it for the preview.
StyledRect {
    id: row

    required property var skill
    property bool selected: false

    // The probe reads these to tell a rendered list from an empty one: a
    // typo in a model name resolves to undefined and produces no warning,
    // only an empty Repeater.
    readonly property alias agentChipCount: agentChips.count
    readonly property alias tagChipCount: tagChips.count

    signal picked

    implicitHeight: content.implicitHeight + Tokens.padding.medium * 2
    radius: Tokens.rounding.large
    color: row.selected
        ? Qt.alpha(Colours.palette.m3primary, 0.10)
        : Colours.signalStyle.raised
    border.width: 1
    border.color: row.selected ? Colours.palette.m3primary : Colours.signalStyle.hairline

    // Declared before the content so the chips sit above it and get their
    // own clicks; text and the icon accept no input, so a click anywhere
    // else falls through to here and selects the row.
    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        onClicked: row.picked()
    }

    ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.extraSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "extension"
                color: row.selected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                Layout.fillWidth: true
                text: row.skill?.name ?? ""
                color: Colours.palette.m3onSurface
                font: Tokens.font.label.large
                elide: Text.ElideRight
            }

            // Where the skill came from decides whether it can move on
            // without the user, so it is shown rather than hidden away.
            StyledRect {
                visible: (row.skill?.source_type ?? "").length > 0
                implicitWidth: sourceText.implicitWidth + Tokens.padding.small * 2
                implicitHeight: 20
                radius: Tokens.rounding.full
                color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                StyledText {
                    id: sourceText
                    anchors.centerIn: parent
                    text: row.skill?.source_type ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: (row.skill?.description ?? "").length > 0
            text: row.skill?.description ?? ""
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Repeater {
                id: agentChips

                model: SkillsService.installedAgents

                AgentChip {
                    required property var modelData

                    record: row.skill
                    agent: modelData
                }
            }

            Repeater {
                id: tagChips

                model: row.skill?.tags ?? []

                StyledRect {
                    required property var modelData
                    implicitWidth: tagText.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: 20
                    radius: Tokens.rounding.full
                    color: "transparent"
                    border.width: 1
                    border.color: Colours.signalStyle.hairline

                    StyledText {
                        id: tagText
                        anchors.centerIn: parent
                        text: `#${modelData}`
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }

            ComboBox {
                visible: (SkillsService.presets ?? []).length > 0
                Layout.preferredWidth: 110
                Layout.preferredHeight: 24
                model: (SkillsService.presets ?? []).map(s => s.name ?? "")
                currentIndex: -1
                displayText: qsTr("Add to set")
                font: Tokens.font.label.small
                onActivated: (index) => {
                    const name = (SkillsService.presets ?? [])[index]?.name ?? "";
                    if (name.length > 0 && (row.skill?.name ?? "").length > 0)
                        SkillsService.addToSet(name, row.skill.name);
                    currentIndex = -1;
                }
                background: StyledRect {
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainer
                    border.width: 1
                    border.color: Colours.signalStyle.hairline
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
