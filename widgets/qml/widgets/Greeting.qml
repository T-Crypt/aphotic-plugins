// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    property date now: new Date()

    Ticker {
        active: root.active
        interval: 60000
        onTriggered: root.now = new Date()
    }

    readonly property string who: {
        const own = String(root.config.name ?? "").trim();
        if (own)
            return own;
        const user = Quickshell.env("USER") ?? "";
        return user.charAt(0).toUpperCase() + user.slice(1);
    }
    readonly property string part: {
        const h = root.now.getHours();
        return h < 5 ? qsTr("Good night") : h < 12 ? qsTr("Good morning") : h < 18 ? qsTr("Good afternoon") : qsTr("Good evening");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        WText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            verticalAlignment: Text.AlignVCenter
            text: root.who ? `${root.part}, ${root.who}` : root.part
            fontSizeMode: Text.Fit
            minimumPixelSize: 10
            font.pixelSize: root.height * 0.5
            font.weight: Font.Light
        }

        Rectangle {
            implicitWidth: Math.min(root.width * 0.2, 64)
            implicitHeight: 2
            radius: 1
            color: root.accent
        }
    }
}
