// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.services

RowLayout {
    id: root

    property real value: 0
    property real from: 0
    property real to: 100
    property real step: 1

    signal changed(real value)

    spacing: 4

    function _set(v: real): void {
        const clamped = Math.max(root.from, Math.min(root.to, Math.round(v / root.step) * root.step));
        root.changed(Number(clamped.toFixed(3)));
    }

    IconButton {
        icon: "remove"
        size: 22
        filled: true
        enabled: root.value > root.from
        onClicked: root._set(root.value - root.step)
    }

    WText {
        Layout.minimumWidth: 40
        horizontalAlignment: Text.AlignHCenter
        text: root.step < 1 ? root.value.toFixed(2) : String(Math.round(root.value))
        font.family: "JetBrainsMono Nerd Font Mono"
        font.pixelSize: 12
    }

    IconButton {
        icon: "add"
        size: 22
        filled: true
        enabled: root.value < root.to
        onClicked: root._set(root.value + root.step)
    }
}
