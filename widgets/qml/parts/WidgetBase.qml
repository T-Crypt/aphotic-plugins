// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import qs.services
import qs.modules.plugins.widgets

// What every widget gets from its frame. Sizes scale with `u`, the short
// side, so a widget reads the same at any size the user drags it to.
Item {
    id: root

    property string uid: ""
    property var config: ({})
    property var store: ({})
    property bool active: true
    property bool editing: false

    readonly property real u: Math.min(root.width, root.height)
    readonly property color ink: Colours.palette.m3onSurface
    readonly property color muted: Colours.palette.m3onSurfaceVariant
    readonly property color faint: Colours.signalStyle.hairline
    readonly property color onAccent: Colours.contrastOn(root.accent)
    readonly property color accent: {
        switch (root.config.accent) {
        case "secondary":
            return Colours.palette.m3secondary;
        case "tertiary":
            return Colours.palette.m3tertiary;
        case "ink":
            return Colours.palette.m3onSurface;
        default:
            return Colours.signal;
        }
    }

    function px(fraction: real): real {
        return Math.max(9, Math.round(root.u * fraction));
    }

    function save(key: string, value: var): void {
        if (root.uid)
            WidgetsStore.setData(root.uid, key, value);
    }

    function pad(n: int): string {
        return n < 10 ? "0" + n : String(n);
    }

    function hour24(date: var): bool {
        if (root.config.hours === "24")
            return true;
        if (root.config.hours === "12")
            return false;
        return !Settings.twelveHourClock;
    }
}
