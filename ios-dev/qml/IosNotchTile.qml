// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

// The iOS notch tile: what is plugged in, and what this plugin is doing
// with it.
//
// No process and no timer. The state file is read through a FileView with
// watchChanges, so the notch builds every gated-in tile without paying
// for any of them: one inotify watch on one file, updated when the CLI
// rewrites it. A tile that ran a scan to open would spend a fork per
// second to learn nothing.
ColumnLayout {
    id: root

    implicitWidth: parent ? parent.width : 240
    spacing: Tokens.spacing.small

    // The notch reads this off whichever tiles are loaded to badge the
    // collapsed strip. A missing prerequisite and a failed run are both
    // things the user has to act on; an idle session with a complete
    // toolchain is not.
    readonly property bool attention: root.missing > 0 || root.state.session.state === "failed"

    readonly property color textPrimary: Colours.palette.m3onSurface
    readonly property color textMuted: Colours.palette.m3onSurfaceVariant
    readonly property color insetColour: Colours.signalStyle.base
    readonly property color statusReference: Colours.palette.m3primaryOnSurface
    readonly property color statusOk: root.statusHue(145)
    readonly property color statusFail: root.statusHue(8)

    function statusHue(degrees: real): color {
        const ref = root.statusReference;
        return Qt.hsla(degrees / 360, Math.max(0.38, ref.hslSaturation), Math.min(0.72, Math.max(0.48, ref.hslLightness)), 1);
    }

    readonly property string stateFile: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        const base = (xdg && xdg.length > 0) ? xdg : `${Quickshell.env("HOME")}/.config`;
        return `${base}/aphotic/plugins/ios-dev/state.json`;
    }

    // One complete shape, referenced twice. A partial literal here is how
    // a fresh machine ends up reading .project off an object that has no
    // project, which is a TypeError in the notch every time.
    readonly property var emptyState: ({
            toolchain: [],
            devices: [],
            session: { state: "idle", project: "", detail: "", pid: 0 },
            ready: false
        })

    property var state: root.emptyState

    readonly property int missing: root.state.toolchain.filter(t => !t.ok).length
    readonly property bool running: root.state.session.state === "running"
    readonly property bool failed: root.state.session.state === "failed"

    readonly property var device: root.state.devices.length > 0 ? root.state.devices[0] : null

    FileView {
        path: root.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.state = JSON.parse(text());
            } catch (e) {
                // A half-written file leaves the last known state up.
            }
        }
        onLoadFailed: root.state = root.emptyState
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "smartphone"
            color: root.device ? root.statusOk : root.textMuted
            fontStyle: Tokens.font.icon.small
            fill: root.device ? 1 : 0
        }

        StyledText {
            Layout.fillWidth: true
            text: root.device ? root.device.name : qsTr("No device")
            elide: Text.ElideRight
            font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
            color: root.textPrimary
        }

        StyledText {
            visible: root.missing > 0
            text: qsTr("%1 missing").arg(root.missing)
            font: Tokens.font.label.small
            color: root.statusFail
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.fillWidth: true
            text: root.running
                  ? qsTr("Running on the device")
                  : (root.failed ? qsTr("Last run failed") : qsTr("Idle"))
            font: Tokens.font.label.medium
            color: root.failed ? root.statusFail : root.textMuted
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.state.session.project.length > 0
            text: root.state.session.project.split("/").pop()
            elide: Text.ElideMiddle
            font: Tokens.font.label.small
            color: root.textMuted
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.missing > 0
            text: qsTr("Run: aphotic ios setup")
            font: Tokens.font.label.small
            color: root.textMuted
        }
    }
}
