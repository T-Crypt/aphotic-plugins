// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    property date now: new Date()
    property int offset: 0

    Ticker {
        active: root.active
        interval: 60000
        onTriggered: root.now = new Date()
    }

    readonly property date shown: new Date(root.now.getFullYear(), root.now.getMonth() + root.offset, 1)
    readonly property int firstDay: root.config.weekStart === "sunday" ? 0 : 1
    readonly property int lead: (root.shown.getDay() - root.firstDay + 7) % 7
    readonly property int days: new Date(root.shown.getFullYear(), root.shown.getMonth() + 1, 0).getDate()
    readonly property var cells: {
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(root.shown.getFullYear(), root.shown.getMonth(), i - root.lead + 1);
            out.push({ day: d.getDate(), inMonth: d.getMonth() === root.shown.getMonth(), today: d.toDateString() === root.now.toDateString(), date: d });
        }
        return out;
    }
    readonly property real cell: Math.min((root.width - (root.config.weekNumbers ? root.width / 8 : 0)) / 7, (root.height - root.px(0.2)) / 7)

    function weekNumber(d: var): int {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - day);
        const y = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - y) / 86400000 + 1) / 7);
    }

    WheelHandler {
        onWheel: event => root.offset += event.angleDelta.y > 0 ? -1 : 1
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 2

        RowLayout {
            Layout.fillWidth: true

            WText {
                Layout.fillWidth: true
                text: root.shown.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                font.pixelSize: root.px(0.065)
                font.weight: Font.Medium
            }

            IconButton {
                icon: "chevron_left"
                size: root.px(0.08)
                onClicked: root.offset--
            }

            IconButton {
                icon: "today"
                size: root.px(0.08)
                visible: root.offset !== 0
                colour: root.accent
                onClicked: root.offset = 0
            }

            IconButton {
                icon: "chevron_right"
                size: root.px(0.08)
                onClicked: root.offset++
            }
        }

        Grid {
            Layout.alignment: Qt.AlignHCenter
            columns: root.config.weekNumbers ? 8 : 7

            Repeater {
                model: (root.config.weekNumbers ? [""] : []).concat([0, 1, 2, 3, 4, 5, 6].map(i => Qt.locale().dayName((i + root.firstDay) % 7, Locale.ShortFormat).slice(0, 2)))

                WText {
                    required property string modelData

                    width: root.cell
                    height: root.cell * 0.8
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    color: root.muted
                    font.pixelSize: root.cell * 0.32
                }
            }

            Repeater {
                model: root.config.weekNumbers ? root.cells.reduce((all, c, i) => all.concat(i % 7 === 0 ? [{ week: root.weekNumber(c.date) }, c] : [c]), []) : root.cells

                Item {
                    id: day

                    required property var modelData

                    width: root.cell
                    height: root.cell

                    Rectangle {
                        anchors.centerIn: parent
                        width: root.cell * 0.82
                        height: width
                        radius: width / 2
                        visible: day.modelData.today === true
                        color: root.accent
                    }

                    WText {
                        anchors.centerIn: parent
                        text: day.modelData.week !== undefined ? String(day.modelData.week) : String(day.modelData.day)
                        color: day.modelData.today ? root.onAccent : (day.modelData.week !== undefined ? root.faint : (day.modelData.inMonth ? root.ink : root.faint))
                        font.pixelSize: root.cell * 0.38
                        font.weight: day.modelData.today ? Font.Bold : Font.Normal
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
