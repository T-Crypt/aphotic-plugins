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

// The skill library on the workspace plane. The host owns the window, the
// rail and the reveal motion; this Item fills the pane it is given.
//
// The read happens once when the surface is built, which the host does on
// first open, plus whenever a write has landed (the service re-reads) or
// the user asks. Nothing polls.
Item {
    id: root

    property string selectedName: ""
    property string searchText: ""
    property string tagFilter: ""
    property string sourceFilter: ""

    readonly property var selectedSkill: SkillsService.skillNamed(root.selectedName)
    readonly property var tagOptions: root._distinct(skill => skill.tags ?? [])
    readonly property var sourceOptions: root._distinct(skill => (skill.source_type ?? "").length > 0 ? [skill.source_type] : [])
    readonly property var visibleSkills: root._visible()
    readonly property alias renderedRowCount: skillList.count

    function _distinct(pick: var): var {
        const seen = new Set();
        for (const skill of SkillsService.skills)
            for (const value of pick(skill))
                seen.add(value);
        return Array.from(seen).sort();
    }

    function _visible(): var {
        const needle = root.searchText.trim().toLowerCase();
        return SkillsService.skills.filter(skill => {
            if (root.tagFilter.length > 0 && !(skill.tags ?? []).includes(root.tagFilter))
                return false;
            if (root.sourceFilter.length > 0 && skill.source_type !== root.sourceFilter)
                return false;
            if (needle.length === 0)
                return true;
            const hay = `${skill.name} ${skill.description ?? ""} ${(skill.tags ?? []).join(" ")}`.toLowerCase();
            return hay.includes(needle);
        });
    }

    function select(name: string): void {
        root.selectedName = name;
        SkillsService.showSkill(name);
    }

    onVisibleSkillsChanged: {
        if (root.selectedName.length > 0 && root.selectedSkill === null)
            root.selectedName = "";
    }

    Component.onCompleted: SkillsService.refresh()

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.small

            // ── Header ──────────────────────────────────────────────

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "extension"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.medium
                }

                ColumnLayout {
                    spacing: 0

                    StyledText {
                        text: qsTr("Skills")
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        text: SkillsService.available
                            ? qsTr("%1 skills · %2 agents · %3").arg(SkillsService.skillCount).arg(SkillsService.installedAgents.length).arg(SkillsService.libraryPath)
                            : qsTr("skills-manager-cli is not available")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                TextField {
                    id: searchField

                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 34
                    placeholderText: qsTr("Search")
                    text: root.searchText
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurface
                    onTextChanged: root.searchText = searchField.text
                    background: StyledRect {
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainer
                        border.width: 1
                        border.color: searchField.activeFocus ? Colours.palette.m3primary : Colours.signalStyle.hairline
                    }
                }

                StyledRect {
                    implicitWidth: reloadLabel.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 34
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainer
                    border.width: 1
                    border.color: Colours.signalStyle.hairline
                    opacity: SkillsService.busy ? 0.6 : 1

                    StyledText {
                        id: reloadLabel
                        anchors.centerIn: parent
                        text: SkillsService.busy ? qsTr("Reading…") : qsTr("Reload")
                        color: Colours.palette.m3onSurface
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

            // ── Filters ─────────────────────────────────────────────

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall
                visible: root.tagOptions.length > 0

                Repeater {
                    model: [""].concat(root.tagOptions)

                    StyledRect {
                        required property var modelData
                        readonly property bool active: root.tagFilter === modelData
                        implicitWidth: filterLabel.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: 28
                        radius: Tokens.rounding.full
                        color: active ? Qt.alpha(Colours.palette.m3primary, 0.16) : Colours.palette.m3surfaceContainer
                        border.width: 1
                        border.color: active ? Colours.palette.m3primary : Colours.signalStyle.hairline

                        StyledText {
                            id: filterLabel
                            anchors.centerIn: parent
                            text: modelData.length > 0 ? `#${modelData}` : qsTr("All tags")
                            color: active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            onClicked: root.tagFilter = modelData
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall
                visible: root.sourceOptions.length > 1

                Repeater {
                    model: [""].concat(root.sourceOptions)

                    StyledRect {
                        required property var modelData
                        readonly property bool active: root.sourceFilter === modelData
                        implicitWidth: sourceLabel.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: 28
                        radius: Tokens.rounding.full
                        color: active ? Qt.alpha(Colours.palette.m3primary, 0.16) : Colours.palette.m3surfaceContainer
                        border.width: 1
                        border.color: active ? Colours.palette.m3primary : Colours.signalStyle.hairline

                        StyledText {
                            id: sourceLabel
                            anchors.centerIn: parent
                            text: modelData.length > 0 ? modelData : qsTr("All sources")
                            color: active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            onClicked: root.sourceFilter = modelData
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            // ── Status ──────────────────────────────────────────────

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

            // A refused deploy is its own thing: the CLI protected these
            // paths and changed nothing, so they are named rather than
            // folded into the error line above.
            StyledRect {
                Layout.fillWidth: true
                visible: SkillsService.conflict !== null
                implicitHeight: conflictColumn.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.medium
                color: Qt.alpha(Colours.palette.m3error, 0.12)
                border.width: 1
                border.color: Colours.palette.m3error

                ColumnLayout {
                    id: conflictColumn

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        text: qsTr("Not ours to replace")
                        color: Colours.palette.m3error
                        font: Tokens.font.label.medium
                    }

                    Repeater {
                        model: SkillsService.conflict?.details?.conflicts ?? []

                        delegate: StyledText {
                            required property var modelData
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: `${modelData.path} — ${modelData.reason}`
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }
                }
            }

            // ── Library ─────────────────────────────────────────────

            ListView {
                id: skillList

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Tokens.spacing.extraSmall
                model: root.visibleSkills
                boundsBehavior: Flickable.StopAtBounds
                visible: root.visibleSkills.length > 0

                delegate: SkillRow {
                    required property var modelData

                    width: skillList.width
                    skill: modelData
                    selected: modelData.name === root.selectedName
                    onPicked: root.select(modelData.name)
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.visibleSkills.length === 0
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: SkillsService.available
                    ? (SkillsService.skillCount === 0 ? qsTr("The library is empty. Adopt what your agents already have, in Settings.") : qsTr("No skill matches these filters."))
                    : qsTr("Install skills-manager-cli to read the library.")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }
        }

        // ── Preview ─────────────────────────────────────────────────

        SkillPreview {
            Layout.preferredWidth: 400
            Layout.fillHeight: true
            visible: root.selectedSkill !== null
            skill: root.selectedSkill
        }
    }
}
