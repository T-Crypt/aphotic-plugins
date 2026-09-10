// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import Quickshell

// Headless, same shape as LaunchTerminal.qml.
QtObject {
    Component.onCompleted: Quickshell.execDetached(["code"])
}
