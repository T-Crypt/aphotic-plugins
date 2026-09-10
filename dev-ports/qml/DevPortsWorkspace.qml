// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Local HTTP dev servers, found by scanning listening loopback ports
// rather than asking any one project to register itself -- so it works
// the same for a node dev server, a Python one-liner, or anything else
// that happens to bind a port. Scan happens only while this pane is the
// active Workspace tab: the Loader that hosts a workspace surface tears
// this whole Item down otherwise, which stops the timer for free.
Item {
    id: root

    readonly property string pluginDir: `${Quickshell.env("HOME")}/.local/share/aphotic/plugins/dev-ports`
    readonly property string scanScript: `${root.pluginDir}/bin/scan.sh`

    // Status is not decorative -- it has to read as "up" under every
    // theme, and the generated palette cannot promise a green hue (see
    // agent-audit's own note on this). Fix the hue, take saturation and
    // lightness from the live palette, so it still sits in the theme.
    readonly property color statusReference: Colours.palette.m3primaryOnSurface
    readonly property color onlineColour: root.statusHue(145)
    readonly property color textPrimary: Colours.palette.m3onSurface
    readonly property color textMuted: Colours.palette.m3onSurfaceVariant
    readonly property color panelColour: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
    readonly property color insetColour: Colours.palette.m3surfaceContainer
    readonly property color hairline: Qt.alpha(Colours.palette.m3onSurface, 0.09)

    function statusHue(degrees: real): color {
        const ref = root.statusReference;
        return Qt.hsla(degrees / 360, Math.max(0.38, ref.hslSaturation), Math.min(0.72, Math.max(0.48, ref.hslLightness)), 1);
    }

    // Port-keyed object from scan.sh, turned into a label-sorted array:
    // online first, then by port.
    property var entries: []
    property bool scanning: false

    function _toArray(data: var): var {
        const rows = Object.values(data ?? {});
        rows.sort((a, b) => {
            if (a.status !== b.status)
                return a.status === "online" ? -1 : 1;
            return a.port - b.port;
        });
        return rows;
    }

    function refresh(): void {
        if (root.scanning)
            return;
        root.scanning = true;
        scanProc.command = [root.scanScript];
        scanProc.running = true;
    }

    function clearOffline(): void {
        if (root.scanning)
            return;
        root.scanning = true;
        scanProc.command = [root.scanScript, "clear-offline"];
        scanProc.running = true;
    }

    function open(url: string): void {
        Quickshell.execDetached(["xdg-open", url]);
    }

    function agoLabel(epochSeconds: var): string {
        const delta = Date.now() / 1000 - Number(epochSeconds ?? 0);
        if (!(delta > 0))
            return qsTr("now");
        const minutes = Math.floor(delta / 60);
        if (minutes < 1)
            return qsTr("just now");
        if (minutes < 60)
            return qsTr("%1m ago").arg(minutes);
        const hours = Math.floor(minutes / 60);
        if (hours < 24)
            return qsTr("%1h ago").arg(hours);
        return qsTr("%1d ago").arg(Math.floor(hours / 24));
    }

    Process {
        id: scanProc

        stdout: StdioCollector {
            id: scanStdout

            onStreamFinished: {
                root.scanning = false;
                try {
                    root.entries = root._toArray(JSON.parse(text));
                } catch (e) {
                    // A bad parse leaves the last-known list on screen
                    // rather than blanking it over one failed scan.
                }
            }
        }
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: root.panelColour

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "lan"
                    color: root.textPrimary
                    fontStyle: Tokens.font.icon.medium
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: qsTr("Dev Ports")
                        font: Tokens.font.title.small
                        color: root.textPrimary
                    }

                    StyledText {
                        text: qsTr("Loopback ports that answer HTTP, scanned every few seconds")
                        font: Tokens.font.label.small
                        color: root.textMuted
                    }
                }

                StyledRect {
                    implicitWidth: clearLabel.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 30
                    radius: Tokens.rounding.full
                    color: root.insetColour

                    StateLayer {
                        color: root.textMuted
                        onClicked: root.clearOffline()
                    }

                    StyledText {
                        id: clearLabel
                        anchors.centerIn: parent
                        text: qsTr("Clear offline")
                        font: Tokens.font.label.small
                        color: root.textMuted
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 1
                color: root.hairline
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacing.large
                visible: root.entries.length === 0
                text: qsTr("Nothing found yet -- start a local dev server and it will show up here")
                font: Tokens.font.label.medium
                color: root.textMuted
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.entries.length > 0
                clip: true
                spacing: Tokens.spacing.small
                model: root.entries

                delegate: PortDelegate {
                    required property var modelData
                    entry: modelData
                }
            }
        }
    }

    component PortDelegate: StyledRect {
        id: portRow

        required property var entry

        readonly property bool online: portRow.entry.status === "online"

        width: ListView.view.width
        implicitHeight: 52
        radius: Tokens.rounding.small
        color: root.insetColour
        opacity: portRow.online ? 1 : 0.6

        StateLayer {
            visible: portRow.online
            color: root.onlineColour
            onClicked: root.open(`http://127.0.0.1:${portRow.entry.port}/`)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            StyledRect {
                width: 10
                height: 10
                radius: Tokens.rounding.full
                color: portRow.online ? root.onlineColour : root.textMuted
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: portRow.entry.name
                    elide: Text.ElideRight
                    font: Tokens.font.label.medium
                    color: root.textPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: `127.0.0.1:${portRow.entry.port}`
                    elide: Text.ElideRight
                    font: Tokens.font.mono.small
                    color: root.textMuted
                }
            }

            StyledText {
                visible: !portRow.online
                text: root.agoLabel(portRow.entry.last_seen)
                font: Tokens.font.label.small
                color: root.textMuted
            }

            MaterialIcon {
                visible: portRow.online
                text: "open_in_new"
                color: root.textMuted
                fontStyle: Tokens.font.icon.small
            }
        }
    }
}
