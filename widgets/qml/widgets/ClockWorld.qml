// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.plugins.widgets.parts

// Time zones come from the system's own zone database through `date`, so
// daylight saving is always right. One call per zone, once a minute.
WidgetBase {
    id: root

    readonly property var zones: String(root.config.zones ?? "").split(",").map(z => z.trim()).filter(z => /^[A-Za-z_+\-\/0-9]+$/.test(z)).slice(0, 8)
    property var rows: ({})
    property int _cursor: 0

    function _next(): void {
        if (root._cursor >= root.zones.length)
            return;
        query.zone = root.zones[root._cursor];
        query.command = ["env", `TZ=${query.zone}`, "date", root.hour24() ? "+%H:%M|%a|%z" : "+%-I:%M %p|%a|%z"];
        query.running = true;
    }

    Ticker {
        active: root.active && root.zones.length > 0
        interval: 1000 * (60 - new Date().getSeconds())
        onTriggered: {
            root._cursor = 0;
            root._next();
        }
    }

    Process {
        id: query

        property string zone: ""

        stdout: StdioCollector {
            onStreamFinished: {
                const [time, day, offset] = text.trim().split("|");
                root.rows = Object.assign({}, root.rows, { [query.zone]: { time: time ?? "", day: day ?? "", offset: offset ?? "" } });
                root._cursor++;
                root._next();
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Repeater {
            model: root.zones

            RowLayout {
                id: row

                required property string modelData
                readonly property var info: root.rows[row.modelData] ?? ({ time: "--:--", day: "", offset: "" })

                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    WText {
                        Layout.fillWidth: true
                        text: row.modelData.split("/").pop().replace(/_/g, " ")
                        font.pixelSize: Math.min(root.px(0.12), root.height / root.zones.length * 0.32)
                    }

                    WText {
                        text: `${row.info.day} · UTC${row.info.offset.slice(0, 3)}`
                        color: root.muted
                        font.pixelSize: Math.min(root.px(0.08), root.height / root.zones.length * 0.22)
                    }
                }

                WText {
                    text: row.info.time
                    font.pixelSize: Math.min(root.px(0.2), root.height / root.zones.length * 0.6)
                    font.weight: Font.Light
                }
            }
        }

        WText {
            visible: root.zones.length === 0
            text: qsTr("Add time zones in this widget's settings, like Europe/Paris.")
            color: root.muted
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }
}
