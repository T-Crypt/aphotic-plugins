// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    property date now: new Date()

    Ticker {
        active: root.active
        interval: 60000
        onTriggered: root.now = new Date()
    }

    readonly property var target: {
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(root.config.date ?? "").trim());
        if (m)
            return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
        return new Date(root.now.getFullYear() + 1, 0, 1);
    }
    readonly property int days: Math.ceil((root.target - new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate())) / 86400000)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        WText {
            Layout.fillWidth: true
            text: root.config.title || qsTr("Countdown")
            color: root.muted
            font.pixelSize: root.px(0.12)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            WText {
                text: String(Math.abs(root.days))
                color: root.days === 0 ? root.accent : root.ink
                font.pixelSize: root.height * 0.48
                font.weight: Font.Light
            }

            WText {
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: root.height * 0.08
                text: root.days === 0 ? qsTr("today") : root.days > 0 ? (root.days === 1 ? qsTr("day to go") : qsTr("days to go")) : qsTr("days ago")
                color: root.accent
                font.pixelSize: root.px(0.12)
            }
        }

        WText {
            Layout.fillWidth: true
            text: root.target.toLocaleDateString(Qt.locale(), "d MMMM yyyy")
            color: root.muted
            font.pixelSize: root.px(0.09)
        }
    }
}
