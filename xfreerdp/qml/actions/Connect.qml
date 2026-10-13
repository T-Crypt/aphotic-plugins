// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import Quickshell

// Headless, same shape as pet/qml/actions/LaunchVSCode.qml: this is what the
// command palette, `aphotic` IPC and the [keybind] combo all run. It goes
// through the CLI rather than building a session here so there is one path
// that decides whether to focus or launch, and it stays behind the plugin so
// the argument order lives in one file.
QtObject {
    Component.onCompleted: Quickshell.execDetached(["aphotic", "xfreerdp", "connect"])
}
