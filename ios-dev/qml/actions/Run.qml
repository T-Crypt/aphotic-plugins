// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import Quickshell
import qs.services
import qs.services.profile

// Headless, the same shape every action component has: this is what the
// command palette, `aphotic` IPC and the [keybind] combo all run, so
// there is one path that decides how an app reaches a device.
//
// The project comes from the dev layer's own active project rather than
// from this plugin's opinion about what "current" means. An action fired
// from a keybind has no working directory, so guessing would be worse
// than asking; the dev profile already tracks what the user opened.
QtObject {
    id: root

    readonly property string iosctl: {
        const xdg = Quickshell.env("XDG_DATA_HOME");
        const base = (xdg && xdg.length > 0) ? xdg : `${Quickshell.env("HOME")}/.local/share`;
        return `${base}/aphotic/plugins/ios-dev/bin/iosctl`;
    }

    // Null until the shell hands the handle over, and null again when the
    // plugin is disabled. Every use is guarded for that reason.
    readonly property var api: PluginApi.handle("ios-dev")

    readonly property string project: {
        if (!DevProfile.active || DevProfile.activeProjectPath.length === 0)
            return "";
        return DevProfile.activeProjectPath;
    }

    Component.onCompleted: {
        if (root.project.length === 0) {
            if (root.api)
                root.api.notify("iOS: no project open", "Open an app folder in the launcher or a terminal, then run it again.");
            return;
        }
        Quickshell.execDetached([root.iosctl, "run", "--detach", "--project", root.project]);
    }
}
