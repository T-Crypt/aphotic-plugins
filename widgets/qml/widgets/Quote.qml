// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.modules.plugins.widgets.parts

// Old proverbs and plain advice, so nothing here needs a source or a
// network call. The user's own lines replace them entirely.
WidgetBase {
    id: root

    readonly property var builtIn: [
        "Well begun is half done.",
        "Make it work, make it right, make it fast.",
        "The best time to plant a tree was twenty years ago. The second best time is now.",
        "Measure twice, cut once.",
        "Slow is smooth, and smooth is fast.",
        "Leave the campground cleaner than you found it.",
        "A little progress each day adds up to big results.",
        "Do one thing at a time, and do it well.",
        "Rest is part of the work.",
        "If it is worth doing, it is worth writing down."
    ]
    readonly property var lines: {
        const own = String(root.config.lines ?? "").split("|").map(l => l.trim()).filter(l => l.length > 0);
        return own.length > 0 ? own : root.builtIn;
    }
    readonly property int day: Math.floor((Date.now() - new Date().getTimezoneOffset() * 60000) / 86400000)

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        WText {
            text: "“"
            color: root.accent
            font.pixelSize: root.px(0.3)
            Layout.preferredHeight: root.px(0.16)
        }

        WText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.lines[root.day % root.lines.length]
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            fontSizeMode: Text.Fit
            minimumPixelSize: 10
            font.pixelSize: root.px(0.16)
            font.italic: true
            font.weight: Font.Light
        }
    }
}
