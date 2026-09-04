// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.services.ai
import qs.modules.plugins.llmFit

ColumnLayout {
    id: root

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Hardware Advisor")
        font: Tokens.font.title.large
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Model recommendations")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        StyledText {
            visible: LlmFitService.checked && !LlmFitService.available
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: qsTr("⚠ llmfit not found. Add it via the 'ai' profile layer, or run: curl -fsSL https://llmfit.axjns.dev/install.sh | sh")
            color: Colours.palette.m3error
            font: Tokens.font.label.small
        }

        SettingsGroup {
            Layout.fillWidth: true
            visible: LlmFitService.available

            SettingsRow {
                icon: "insights"
                label: qsTr("Recommended model for this system")
                description: LlmFitService.scanning ? qsTr("Scanning CPU/GPU…") : qsTr("Runs llmfit against your detected hardware")

                // Wrapped in a RowLayout, not a bare StyledRect: a lone
                // StyledRect dropped directly into SettingsRow's trailing
                // slot (a plain Item, not a Layout) has no real Layout
                // parent, so its Layout.preferredWidth/Height are silently
                // ignored and it collapses to 0x0.
                RowLayout {
                    StyledRect {
                        Layout.preferredWidth: scanLabel.implicitWidth + Tokens.padding.large * 2
                        Layout.preferredHeight: 32
                        radius: Tokens.rounding.full
                        opacity: LlmFitService.scanning ? 0.5 : 1
                        color: Colours.palette.m3primary

                        StyledText {
                            id: scanLabel
                            anchors.centerIn: parent
                            text: LlmFitService.scanning ? qsTr("Scanning…") : qsTr("Scan")
                            color: Colours.contrastOn(Colours.palette.m3primary)
                            font: Tokens.font.label.small
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            showHoverBackground: !LlmFitService.scanning
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !LlmFitService.scanning
                            onClicked: LlmFitService.scan()
                        }
                    }
                }
            }
        }

        StyledText {
            visible: LlmFitService.available && LlmFitService.errorText.length > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: `⚠ ${LlmFitService.errorText}`
            color: Colours.palette.m3error
            font: Tokens.font.label.small
        }

        StyledText {
            visible: LlmFitService.available && LlmFitService.systemInfo !== null
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: LlmFitService.systemInfo ? qsTr("%1 · %2 cores · %3 GB RAM · %4").arg(LlmFitService.systemInfo.cpu_name).arg(LlmFitService.systemInfo.cpu_cores).arg(LlmFitService.systemInfo.total_ram_gb).arg(LlmFitService.systemInfo.has_gpu ? `${LlmFitService.systemInfo.gpu_name} (${LlmFitService.systemInfo.gpu_vram_gb} GB)` : qsTr("no GPU detected")) : ""
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        SettingsGroup {
            Layout.fillWidth: true
            visible: LlmFitService.available && LlmFitService.recommendations.length > 0

            Repeater {
                model: LlmFitService.recommendations

                SettingsRow {
                    id: recRow

                    required property var modelData
                    readonly property string tag: LlmFitService.guessOllamaTag(recRow.modelData)

                    icon: "smart_toy"
                    label: `${recRow.modelData.name} (${recRow.modelData.best_quant})`
                    description: qsTr("%1 fit · ~%2 tok/s · %3 params · score %4/100").arg(recRow.modelData.fit_level).arg(Math.round(recRow.modelData.estimated_tps)).arg(recRow.modelData.parameter_count).arg(Math.round(recRow.modelData.score))

                    // See the RowLayout-wrap comment on the Scan button
                    // above -- same fix, same reason.
                    RowLayout {
                        StyledRect {
                            Layout.preferredWidth: pullLabel.implicitWidth + Tokens.padding.large * 2
                            Layout.preferredHeight: 32
                            radius: Tokens.rounding.full
                            visible: recRow.tag.length > 0
                            opacity: AiProviders.pulling ? 0.5 : 1
                            color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                            StyledText {
                                id: pullLabel
                                anchors.centerIn: parent
                                text: qsTr("Pull \"%1\"").arg(recRow.tag)
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }

                            StateLayer {
                                anchors.fill: parent
                                radius: parent.radius
                                showHoverBackground: !AiProviders.pulling
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !AiProviders.pulling
                                onClicked: AiProviders.pullModel(recRow.tag)
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            visible: LlmFitService.available && LlmFitService.recommendations.length > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: qsTr("Pull tags are a best-effort guess from the model name, not a lookup -- verify against Ollama Models in the AI pane if a pull doesn't find a match.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }
}
