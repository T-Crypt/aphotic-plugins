// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// What the screensaver spells out. A watched file rather than a setting,
// because it is content rather than configuration -- `aphotic screensaver`
// writes it, this reads it, and neither needs the shell's settings store
// in between.
//
// Absent is the normal state, not an error: an install nobody has
// customised has no file at all and gets the wordmark.
Singleton {
    id: root

    readonly property string fallback: "APHOTIC"
    readonly property string path: `${Quickshell.env("HOME")}/.config/aphotic/branding/screensaver.txt`

    // Art is anything that needs its own line breaks and a fixed cell --
    // an imported image, or hand-drawn text. It is rendered as a block at
    // a smaller size with no letter spacing, where a wordmark is rendered
    // as one wide line.
    readonly property bool art: root.content.includes("\n")
    readonly property string text: root.content.length > 0 ? root.content : root.fallback

    property string content: ""

    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.content = text().replace(/\s+$/, "")
        onLoadFailed: root.content = ""
    }
}
