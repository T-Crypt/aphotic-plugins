// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import Quickshell

// Headless, the same contract every action component has. Stopping a
// detached run needs no project, because the CLI already recorded the
// process it started in the state file.
QtObject {
    id: root

    readonly property string iosctl: {
        const xdg = Quickshell.env("XDG_DATA_HOME");
        const base = (xdg && xdg.length > 0) ? xdg : `${Quickshell.env("HOME")}/.local/share`;
        return `${base}/aphotic/plugins/ios-dev/bin/iosctl`;
    }

    Component.onCompleted: Quickshell.execDetached([root.iosctl, "stop"])
}
