// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick

// A timer that runs only while its widget is on screen.
Timer {
    property bool active: true

    repeat: true
    triggeredOnStart: true
    running: active
}
