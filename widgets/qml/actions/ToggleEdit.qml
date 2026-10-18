// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import qs.modules.plugins.widgets

// Headless: the palette, IPC and the keybind all run this.
QtObject {
    Component.onCompleted: WidgetsStore.toggleEdit()
}
