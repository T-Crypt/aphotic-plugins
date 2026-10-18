// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    property date now: new Date()

    Ticker {
        active: root.active
        interval: 1000 * (60 - new Date().getSeconds())
        onTriggered: root.now = new Date()
    }

    readonly property var names: ["twelve", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]

    readonly property string phrase: {
        const m = Math.round(root.now.getMinutes() / 5) * 5;
        let h = root.now.getHours() % 12;
        const next = names[(h + 1) % 12 || 12];
        const cur = names[h || 12];
        const words = {
            0: `${cur} o'clock`, 5: `five past ${cur}`, 10: `ten past ${cur}`, 15: `quarter past ${cur}`, 20: `twenty past ${cur}`, 25: `twenty-five past ${cur}`,
            30: `half past ${cur}`, 35: `twenty-five to ${next}`, 40: `twenty to ${next}`, 45: `quarter to ${next}`, 50: `ten to ${next}`, 55: `five to ${next}`, 60: `${next} o'clock`
        };
        const text = qsTr("It's %1").arg(words[m]);
        if (root.config.casing === "upper")
            return text.toUpperCase();
        if (root.config.casing === "lower")
            return text.toLowerCase();
        return text;
    }

    WText {
        anchors.fill: parent
        text: root.phrase
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        verticalAlignment: Text.AlignVCenter
        fontSizeMode: Text.Fit
        minimumPixelSize: 10
        font.pixelSize: root.height * 0.42
        font.weight: Font.Light
    }
}
