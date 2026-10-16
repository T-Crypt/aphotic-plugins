// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import Quickshell

// Headless, same shape as xfreerdp/qml/actions/Connect.qml: this is what the
// command palette, `aphotic` IPC and the [keybind] combo all run.
//
// It goes out through the shell's own IPC rather than setting a flag here,
// because a plugin action is built with no context (see the core Actions
// singleton): this object has no screen state to write to, and the IPC
// handler resolves the focused one. `action workspace.open` instead of
// `toggle workspace` so invoking it with the plane already up leaves it up.
//
// The plane picks its own first surface by label, so this opens the plane
// and the reader picks Skills from the rail. Core has no one-shot request
// for a named workspace surface the way it has one for a dashboard tab.
QtObject {
    Component.onCompleted: Quickshell.execDetached([
        "qs", "-c", "aphotic", "ipc", "call", "aphotic", "action", "workspace.open"
    ])
}
