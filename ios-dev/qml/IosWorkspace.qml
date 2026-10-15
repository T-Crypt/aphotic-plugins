// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

// The iOS workspace: the toolchain checklist, what is plugged in, and the
// session this plugin is currently holding. The host owns the window, the
// rail and the reveal motion; this Item only fills the pane it is given.
//
// Nothing here polls while the plane is closed. The Loader that hosts a
// workspace surface tears this whole Item down otherwise, which stops the
// timer for free. While open it runs one `iosctl status` every five
// seconds.
Item {
    id: root

    readonly property string iosctl: `${root.pluginDir}/bin/iosctl`

    // Resolved rather than hardcoded, because the install directory moves
    // when XDG_DATA_HOME is non-default and a wrong path here would show
    // an empty pane with no error anywhere.
    readonly property string pluginDir: {
        const xdg = Quickshell.env("XDG_DATA_HOME");
        const base = (xdg && xdg.length > 0) ? xdg : `${Quickshell.env("HOME")}/.local/share`;
        return `${base}/aphotic/plugins/ios-dev`;
    }

    readonly property color textPrimary: Colours.palette.m3onSurface
    readonly property color textMuted: Colours.palette.m3onSurfaceVariant
    readonly property color panelColour: Colours.signalStyle.surface
    readonly property color insetColour: Colours.signalStyle.base
    readonly property color hairline: Colours.signalStyle.hairline
    readonly property color accent: Colours.palette.m3primary

    // Status is not decorative. A missing prerequisite and a satisfied one
    // have to stay apart under every theme, and the derived palette cannot
    // promise a hue, so the hue is fixed and saturation and lightness come
    // from the live palette.
    readonly property color statusReference: Colours.palette.m3primaryOnSurface
    readonly property color statusOk: root.statusHue(145)
    readonly property color statusFail: root.statusHue(8)

    function statusHue(degrees: real): color {
        const ref = root.statusReference;
        return Qt.hsla(degrees / 360, Math.max(0.38, ref.hslSaturation), Math.min(0.72, Math.max(0.48, ref.hslLightness)), 1);
    }

    // One complete shape, referenced twice. A partial literal is how a
    // fresh machine ends up reading .project off an object with no
    // project, which is a TypeError in the pane every time.
    readonly property var emptyState: ({
            toolchain: [],
            devices: [],
            session: { state: "idle", project: "", detail: "", pid: 0 },
            ready: false
        })

    property var state: root.emptyState
    property bool busy: false

    readonly property bool running: root.state.session.state === "running"
    readonly property bool failed: root.state.session.state === "failed"

    readonly property int missing: root.state.toolchain.filter(t => !t.ok).length

    function refresh(): void {
        if (root.busy)
            return;
        root.busy = true;
        statusProc.command = [root.iosctl, "status"];
        statusProc.running = true;
    }

    function act(subcommand: string): void {
        Quickshell.execDetached([root.iosctl, subcommand]);
    }

    Process {
        id: statusProc

        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                try {
                    root.state = JSON.parse(text);
                } catch (e) {
                    // A bad parse leaves the last known state on screen
                    // rather than blanking the pane over one failed call.
                }
            }
        }
        onExited: root.busy = false
    }

    Timer {
        interval: 5000
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
                    text: "smartphone"
                    color: root.accent
                    fontStyle: Tokens.font.icon.medium
                    fill: 1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: qsTr("iOS Development")
                        font: Tokens.font.title.small
                        color: root.textPrimary
                    }

                    StyledText {
                        text: root.missing === 0
                              ? qsTr("The toolchain is complete")
                              : qsTr("%1 of %2 prerequisites missing").arg(root.missing).arg(root.state.toolchain.length)
                        font: Tokens.font.label.small
                        color: root.textMuted
                    }
                }

                StyledRect {
                    implicitWidth: actionLabel.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 30
                    radius: Tokens.rounding.full
                    color: root.insetColour

                    StateLayer {
                        color: root.textMuted
                        onClicked: root.refresh()
                    }

                    RowLayout {
                        id: actionLabel

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "refresh"
                            color: root.textMuted
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: qsTr("Refresh")
                            font: Tokens.font.label.small
                            color: root.textMuted
                        }
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 1
                color: root.hairline
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacing.large

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("TOOLCHAIN")
                        font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.2).build()
                        color: root.textMuted
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: Tokens.spacing.small
                        model: root.state.toolchain

                        delegate: StyledRect {
                            required property var modelData

                            width: ListView.view.width
                            implicitHeight: 44
                            radius: Tokens.rounding.medium
                            color: root.insetColour

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Tokens.padding.small
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: modelData.ok ? "check_circle" : "warning"
                                    color: modelData.ok ? root.statusOk : root.statusFail
                                    fontStyle: Tokens.font.icon.small
                                    fill: 1
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    elide: Text.ElideRight
                                    font: Tokens.font.label.medium
                                    color: root.textPrimary
                                }

                                StyledText {
                                    visible: modelData.detail.length > 0
                                    text: modelData.detail
                                    elide: Text.ElideRight
                                    font: Tokens.font.label.small
                                    color: root.textMuted
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: 300
                    Layout.fillHeight: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("DEVICES")
                        font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.2).build()
                        color: root.textMuted
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.state.devices.length === 0
                        text: qsTr("Nothing plugged in. Connect an iPhone, unlock it and tap Trust.")
                        wrapMode: Text.Wrap
                        font: Tokens.font.label.small
                        color: root.textMuted
                    }

                    Repeater {
                        model: root.state.devices

                        delegate: StyledRect {
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: Tokens.rounding.medium
                            color: root.insetColour

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Tokens.padding.small
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: "smartphone"
                                    color: root.statusOk
                                    fontStyle: Tokens.font.icon.small
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        elide: Text.ElideRight
                                        font: Tokens.font.label.medium
                                        color: root.textPrimary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: `${modelData.transport} · ${modelData.udid}`
                                        elide: Text.ElideMiddle
                                        font: Tokens.font.label.small
                                        color: root.textMuted
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.topMargin: Tokens.spacing.small
                        text: qsTr("SESSION")
                        font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.2).build()
                        color: root.textMuted
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: Tokens.rounding.medium
                        color: root.insetColour

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.small
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: root.running
                                      ? qsTr("Running on the device")
                                      : (root.failed ? qsTr("Last run failed") : qsTr("Idle"))
                                font: Tokens.font.label.medium
                                color: root.failed ? root.statusFail : root.textPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.state.session.project.length > 0
                                text: root.state.session.project
                                elide: Text.ElideMiddle
                                font: Tokens.font.label.small
                                color: root.textMuted
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.state.session.detail.length > 0
                                text: root.state.session.detail
                                elide: Text.ElideRight
                                font: Tokens.font.label.small
                                color: root.statusFail
                            }
                        }
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 1
                color: root.hairline
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: Tokens.rounding.full
                    color: root.accent
                    opacity: root.missing === 0 ? 1 : 0.5

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        onClicked: root.act("run")
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "play_arrow"
                            color: Colours.contrastOn(root.accent)
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: qsTr("Run on device")
                            font: Tokens.font.label.small
                            color: Colours.contrastOn(root.accent)
                        }
                    }
                }

                StyledRect {
                    implicitWidth: stopLabel.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 34
                    radius: Tokens.rounding.full
                    color: root.insetColour

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        color: root.textMuted
                        onClicked: root.act("stop")
                    }

                    RowLayout {
                        id: stopLabel

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "close"
                            color: root.textMuted
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: qsTr("Stop")
                            font: Tokens.font.label.small
                            color: root.textMuted
                        }
                    }
                }

                StyledRect {
                    implicitWidth: setupLabel.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 34
                    radius: Tokens.rounding.full
                    color: root.insetColour

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        color: root.textMuted
                        onClicked: root.act("setup")
                    }

                    RowLayout {
                        id: setupLabel

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "download"
                            color: root.textMuted
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: qsTr("Setup")
                            font: Tokens.font.label.small
                            color: root.textMuted
                        }
                    }
                }
            }
        }
    }
}
