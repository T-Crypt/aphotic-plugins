// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

import QtQuick
import Quickshell

// Headless, same shape as LaunchTerminal.qml.
QtObject {
    Component.onCompleted: Quickshell.execDetached(["code"])
}
