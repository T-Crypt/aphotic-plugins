// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.services.ai
import qs.services.profile
import qs.modules.plugins.llamaSwap

ColumnLayout {
    id: root

    readonly property string owner: `llama-swap-tile-${Math.random()}`
    readonly property bool configured: AiConfig.llamaSwapHostConfigured
    readonly property bool reachable: root.configured && AiProviders.llamaSwapReachable
    readonly property bool attention: root.configured && !root.reachable

    // Every engine on the machine: the ones a descriptor reports live, then
    // each built-in backend that has a model loaded, then llama-swap while
    // it answers. One row per engine, whatever runs it.
    readonly property var engines: {
        const rows = [];
        const seen = {};
        for (const e of EngineRegistry.liveEngines) {
            if (seen[e.id])
                continue;
            seen[e.id] = true;
            rows.push({ id: e.id, label: e.label || e.id, models: (e.models ?? []).map(m => ({ name: m.name, state: m.state ?? "" })), via: e.gateway ? (EngineRegistry.byId(e.gateway)?.label ?? e.gateway) : "" });
        }
        const backends = LocalInference.backends;
        for (const owner of Object.keys(backends)) {
            const models = backends[owner].models ?? [];
            if (seen[owner] || models.length === 0)
                continue;
            seen[owner] = true;
            rows.push({ id: owner, label: backends[owner].label || owner, models: models.map(m => ({ name: m.name, state: m.state ?? "" })), via: "" });
        }
        for (const [id, label, up] of [["ollama", "Ollama", AiProviders.ollamaReachable], ["llama-swap", "llama-swap", root.reachable], ["lm-studio", "LM Studio", AiProviders.lmStudioReachable]]) {
            if (up && !seen[id]) {
                seen[id] = true;
                rows.push({ id: id, label: label, models: [], via: "" });
            }
        }
        return rows.map(r => Object.assign(r, { vramMib: root.vramOf(r.id), loaded: r.models.some(m => m.state !== "unloaded") }))
            .sort((a, b) => (b.loaded - a.loaded) || (b.vramMib - a.vramMib) || a.label.localeCompare(b.label));
    }

    // The engine holding the most GPU memory with a model loaded is the one
    // in use; ties go to the first listed.
    readonly property var inUse: root.engines.find(e => e.loaded) ?? null

    function vramOf(owner: string): int {
        return ResourceEngine.claimsOf(owner).filter(c => c.resource === "gpu-vram").reduce((total, c) => total + (c.amount ?? 0), 0);
    }

    function formatMib(mib: int): string {
        return mib >= 1024 ? qsTr("%1 GiB").arg((mib / 1024).toFixed(1)) : qsTr("%1 MiB").arg(mib);
    }

    spacing: Tokens.spacing.small

    onVisibleChanged: LlamaSwapService.setSurfaceVisible(root.owner, visible)
    Component.onCompleted: LlamaSwapService.setSurfaceVisible(root.owner, visible)
    Component.onDestruction: LlamaSwapService.setSurfaceVisible(root.owner, false)

    component ActionButton: StyledRect {
        id: action

        required property string label
        property string icon: ""
        property bool enabled: true
        property bool selected: false

        signal activated

        implicitWidth: actionRow.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: 26
        radius: Tokens.rounding.full
        color: action.selected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh
        opacity: action.enabled ? 1 : 0.5

        RowLayout {
            id: actionRow

            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                visible: action.icon.length > 0
                text: action.icon
                color: action.selected ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                text: action.label
                color: action.selected ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurface
                font: Tokens.font.label.small
            }
        }

        StateLayer {
            disabled: !action.enabled
            onClicked: action.activated()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: root.inUse ? "memory" : "memory_off"
            color: root.inUse ? Colours.palette.m3primaryOnSurface : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.large
            fill: root.inUse ? 1 : 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.inUse ? qsTr("%1 in use").arg(root.inUse.label) : qsTr("Local AI")
                color: Colours.palette.m3onSurface
                font: Tokens.font.title.builders.medium.weight(Font.Medium).build()
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.engines.length === 0 ? qsTr("No local engine running") : qsTr("%n engine(s) running", "", root.engines.length)
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }
    }

    Repeater {
        model: root.engines

        StyledRect {
            id: engineRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: engineColumn.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.small
            color: "transparent"
            border.width: 1
            border.color: engineRow.modelData.id === root.inUse?.id ? Colours.signal : Colours.signalStyle.hairline

            ColumnLayout {
                id: engineColumn

                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledRect {
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: 3
                        color: engineRow.modelData.loaded ? Colours.palette.m3primary : Colours.palette.m3outline
                    }

                    StyledText {
                        text: engineRow.modelData.label
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: engineRow.modelData.via !== ""
                        text: qsTr("via %1").arg(engineRow.modelData.via)
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    Item {
                        Layout.fillWidth: engineRow.modelData.via === ""
                    }

                    StyledText {
                        visible: engineRow.modelData.vramMib > 0
                        text: root.formatMib(engineRow.modelData.vramMib)
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.mono.small
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: engineRow.modelData.models.length === 0 ? qsTr("No model loaded") : engineRow.modelData.models.map(m => m.state && m.state !== "ready" && m.state !== "loaded" ? `${m.name} (${m.state})` : m.name).join(", ")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.engines.length === 0
        text: qsTr("Start Ollama, llama.cpp, vLLM or any OpenAI-compatible server and it appears here. Others can be added with a file in ~/.config/aphotic/engines/.")
        color: Colours.palette.m3onSurfaceVariant
        wrapMode: Text.Wrap
        font: Tokens.font.body.small
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall
        implicitHeight: 1
        color: Colours.signalStyle.hairline
        visible: root.configured
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.configured
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: root.reachable ? "memory" : root.configured ? "cloud_off" : "memory_off"
            color: root.reachable ? Colours.palette.m3primaryOnSurface : root.attention ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.large
            fill: root.reachable ? 1 : 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: qsTr("llama-swap")
                color: Colours.palette.m3onSurface
                font: Tokens.font.title.builders.medium.weight(Font.Medium).build()
            }

            StyledText {
                Layout.fillWidth: true
                text: !root.configured ? qsTr("Host not configured") : root.reachable ? AiConfig.llamaSwapHost : qsTr("Host unavailable")
                color: root.attention ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideMiddle
            }
        }

        StyledRect {
            implicitWidth: reachabilityLabel.implicitWidth + Tokens.padding.small * 2
            implicitHeight: 20
            radius: Tokens.rounding.full
            color: root.reachable ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh

            StyledText {
                id: reachabilityLabel

                anchors.centerIn: parent
                text: root.reachable ? qsTr("reachable") : qsTr("offline")
                color: root.reachable ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.reachable && LlamaSwapService.models.length === 0
        text: qsTr("No models running")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    Repeater {
        model: root.reachable ? LlamaSwapService.models : []

        StyledRect {
            id: modelRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: 46
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainerHigh

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.small
                spacing: Tokens.spacing.small

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: modelRow.modelData.name
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: [modelRow.modelData.state,
                            modelRow.modelData.vramMib > 0 ? qsTr("%1 MiB VRAM").arg(Math.round(modelRow.modelData.vramMib)) : ""]
                            .filter(Boolean).join(" · ")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }

                ActionButton {
                    label: LlamaSwapService.unloadingModel === modelRow.modelData.name ? qsTr("Unloading") : qsTr("Unload")
                    icon: "eject"
                    enabled: LlamaSwapService.unloadingModel.length === 0
                    onActivated: LlamaSwapService.unload(modelRow.modelData.name)
                }
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        visible: root.reachable && LlamaSwapStats.model.length > 0
        implicitHeight: 34
        radius: Tokens.rounding.small
        color: Colours.palette.m3surfaceContainerHigh

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.small
            anchors.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: LlamaSwapStats.generating ? "speed" : "pause"
                color: LlamaSwapStats.generating ? Colours.palette.m3primaryOnSurface : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
                fill: LlamaSwapStats.generating ? 1 : 0
            }

            StyledText {
                Layout.fillWidth: true
                text: LlamaSwapStats.model
                color: Colours.palette.m3onSurface
                font: Tokens.font.label.medium
                elide: Text.ElideRight
            }

            StyledText {
                text: qsTr("%1 tok/s · %2/%3 ctx")
                    .arg(LlamaSwapStats.tokensPerSecond.toFixed(1))
                    .arg(LlamaSwapStats.nDecoded)
                    .arg(LlamaSwapStats.nCtx)
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.mono.small
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.configured
        spacing: Tokens.spacing.small

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: qsTr("Inference mode")
                color: Colours.palette.m3onSurface
                font: Tokens.font.label.medium
            }

            StyledText {
                Layout.fillWidth: true
                text: InferenceMode.active
                    ? qsTr("Active%1").arg(InferenceMode.model ? ` · ${InferenceMode.model}` : "")
                    : qsTr("Idle")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        ActionButton {
            label: InferenceMode.active ? qsTr("Exit") : qsTr("Enter")
            icon: InferenceMode.active ? "stop" : "play_arrow"
            selected: InferenceMode.active
            onActivated: {
                if (InferenceMode.active)
                    InferenceMode.exit("llama-swap-tile");
                else
                    InferenceMode.enter("llama-swap-tile");
            }
        }
    }
}
