// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

import QtQuick
import Quickshell

// Headless: fires once in `Component.onCompleted` and draws nothing.
// `PetActionMenu` tears the Loader down again right after, same as any
// other surface's dynamic file:// load -- there is nothing here for it
// to wait on.
QtObject {
    Component.onCompleted: Quickshell.execDetached(["kitty"])
}
