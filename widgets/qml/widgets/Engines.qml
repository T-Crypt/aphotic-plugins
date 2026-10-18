// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.services.ai
import qs.services.profile
import qs.modules.plugins.widgets.parts

// Local inference engines the shell already watches: engines a descriptor
// reports live, then any built-in backend with a model loaded.
WidgetBase {
    id: root

    readonly property var engines: {
        const rows = [];
        const seen = {};
        for (const e of EngineRegistry.liveEngines) {
            if (seen[e.id])
                continue;
            seen[e.id] = true;
            rows.push({ id: e.id, label: e.label || e.id, models: (e.models ?? []).map(m => m.name) });
        }
        const backends = LocalInference.backends;
        for (const owner of Object.keys(backends)) {
            const models = (backends[owner].models ?? []).map(m => m.name);
            if (seen[owner] || models.length === 0)
                continue;
            seen[owner] = true;
            rows.push({ id: owner, label: backends[owner].label || owner, models: models });
        }
        return rows.map(r => Object.assign(r, { vram: ResourceEngine.claimsOf(r.id).filter(c => c.resource === "gpu-vram").reduce((t, c) => t + (c.amount ?? 0), 0) }))
            .sort((a, b) => (b.models.length > 0) - (a.models.length > 0) || b.vram - a.vram);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true

            MaterialIcon {
                text: root.engines.length > 0 ? "neurology" : "memory_off"
                color: root.engines.length > 0 ? root.accent : root.muted
                font.pixelSize: 18
            }

            WText {
                Layout.fillWidth: true
                text: root.engines.length > 0 && root.engines[0].models.length > 0 ? qsTr("%1 in use").arg(root.engines[0].label) : qsTr("No local model loaded")
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        Repeater {
            model: root.engines

            ColumnLayout {
                id: eng

                required property var modelData

                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true

                    WText {
                        Layout.fillWidth: true
                        text: eng.modelData.label
                        font.pixelSize: 12
                    }

                    WText {
                        visible: eng.modelData.vram > 0
                        text: eng.modelData.vram >= 1024 ? `${(eng.modelData.vram / 1024).toFixed(1)} GiB` : `${eng.modelData.vram} MiB`
                        color: root.muted
                        font.family: "JetBrainsMono Nerd Font Mono"
                        font.pixelSize: 10
                    }
                }

                WText {
                    Layout.fillWidth: true
                    text: eng.modelData.models.length > 0 ? eng.modelData.models.join(", ") : qsTr("idle")
                    color: root.muted
                    font.pixelSize: 11
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
