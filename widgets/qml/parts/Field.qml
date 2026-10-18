// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import qs.services
import qs.modules.plugins.widgets

// A one-line text box. While it has focus the overlay takes the keyboard;
// Enter or leaving the field commits.
Rectangle {
    id: root

    property string text: ""
    property string owner: ""
    property string placeholder: ""
    property bool multiline: false

    signal committed(string value)

    function clear(): void {
        input.text = "";
    }

    implicitHeight: root.multiline ? 80 : 28
    radius: 6
    color: "transparent"
    border.width: 1
    border.color: input.activeFocus ? Colours.signal : Colours.signalStyle.hairline

    TextEdit {
        id: input

        anchors.fill: parent
        anchors.margins: 6
        text: root.text
        color: Colours.palette.m3onSurface
        selectionColor: Qt.alpha(Colours.signal, 0.35)
        font.family: "Inter"
        font.pixelSize: 12
        wrapMode: root.multiline ? TextEdit.Wrap : TextEdit.NoWrap
        clip: true
        onActiveFocusChanged: {
            WidgetsStore.typing = input.activeFocus ? root.owner : (WidgetsStore.typing === root.owner ? "" : WidgetsStore.typing);
            if (!input.activeFocus && input.text !== root.text)
                root.committed(input.text);
        }
        Keys.onReturnPressed: event => {
            if (root.multiline && !(event.modifiers & Qt.ControlModifier)) {
                event.accepted = false;
                return;
            }
            root.committed(input.text);
            input.focus = false;
        }
        Keys.onEscapePressed: input.focus = false
    }

    WText {
        anchors.fill: input
        visible: input.text.length === 0 && !input.activeFocus
        text: root.placeholder
        color: Colours.palette.m3onSurfaceVariant
        font.pixelSize: 12
    }
}
