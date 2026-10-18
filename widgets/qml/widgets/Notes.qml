// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import qs.services
import qs.modules.plugins.widgets
import qs.modules.plugins.widgets.parts

// Saved when focus leaves the note and a second after typing stops.
WidgetBase {
    id: root

    Flickable {
        id: flick

        anchors.fill: parent
        contentHeight: edit.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        TextEdit {
            id: edit

            width: flick.width
            text: String(root.store.text ?? "")
            color: root.ink
            selectionColor: Qt.alpha(root.accent, 0.35)
            wrapMode: TextEdit.Wrap
            font.family: root.config.mono ? "JetBrainsMono Nerd Font Mono" : "Inter"
            font.pixelSize: Math.max(11, Math.min(16, root.u * 0.07))
            onTextChanged: if (activeFocus) saveTimer.restart()
            onActiveFocusChanged: {
                if (activeFocus) {
                    WidgetsStore.typing = root.uid;
                } else {
                    if (WidgetsStore.typing === root.uid)
                        WidgetsStore.typing = "";
                    root.save("text", edit.text);
                }
            }
            Keys.onEscapePressed: edit.focus = false
        }
    }

    WText {
        anchors.fill: parent
        visible: edit.text.length === 0 && !edit.activeFocus
        text: qsTr("Click to write…")
        color: root.muted
        font.pixelSize: 13
    }

    Timer {
        id: saveTimer

        interval: 1000
        onTriggered: root.save("text", edit.text)
    }
}
