// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property var qualityPresets: [{ value: "auto", label: qsTr("Auto") }, { value: "lite", label: qsTr("Lite") }, { value: "standard", label: qsTr("Standard") }, { value: "full", label: qsTr("Full") }]
    readonly property var historyPresets: [{ value: 0, label: qsTr("Auto") }, { value: 150, label: qsTr("150") }, { value: 400, label: qsTr("400") }, { value: 1000, label: qsTr("1000") }]

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Agent Graph")
        font: Tokens.font.title.large
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Tracking")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            wrapMode: Text.Wrap
            text: qsTr("The graph tab always stays available. Live keeps it tracking new tool calls and animating in real time; paused freezes it on whatever it last showed -- still browsable, just not doing continuous work in the background.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsToggleRow {
                label: qsTr("Live")
                description: qsTr("Off pauses layout updates and flow animation -- past sessions stay visible, nothing is lost")
                checked: Settings.agentGraphEnabled
                onToggled: state => Settings.agentGraphEnabled = state
            }

            SettingsPresetRow {
                icon: "history"
                label: qsTr("Retained history")
                description: qsTr("How many past events the graph keeps. An ended session leaves the graph once none of its events are left in the window. Auto follows the detail tier below.")
                presets: root.historyPresets
                value: Settings.agentGraphHistoryLines
                onSelected: value => Settings.agentGraphHistoryLines = value
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Appearance")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            wrapMode: Text.Wrap
            text: qsTr("Detail is how much of the agent graph is simulated, not how it looks — every tier draws the same thing. Auto reads your GPU and eases off while Ollama has models loaded, so the graph never competes with a local model for VRAM.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsPresetRow {
                icon: "hub"
                label: qsTr("Detail")
                presets: root.qualityPresets
                value: Settings.agentGraphQuality
                onSelected: value => Settings.agentGraphQuality = value
            }

            SettingsRow {
                icon: "palette"
                label: qsTr("Graph accent")

                ColorPickerField {
                    value: Settings.agentGraphAccent
                    onValueChanged: Settings.agentGraphAccent = value
                }
            }

            SettingsToggleRow {
                label: qsTr("Group by parent agent")
                description: qsTr("Color-codes a subagent's own tool calls separately from its session — computed once when the graph updates, off by default")
                checked: Settings.agentGraphGroupByParent
                onToggled: state => Settings.agentGraphGroupByParent = state
            }
        }
    }
}
