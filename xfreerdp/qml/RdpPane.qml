// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.xfreerdp

// The Remote Desktop section, docked into Network. The host's
// SettingsSection already draws the header (icon and label); this body holds
// the four groups the session is built from: who to connect to, what leaves
// this machine, how the window behaves, and the free-form tail.
//
// Every value persists through RdpSettings to the plugin's own settings file
// and nothing here writes a core Settings key, so removing the plugin removes
// the profile with it. Free-text fields save on focus-out rather than on
// every keystroke, which is the shell's own idiom: one write per field
// touched, not one per character typed.
ColumnLayout {
    id: root

    readonly property int fieldWidth: 240

    implicitWidth: parent ? parent.width : 460
    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Remote Desktop")
        font: Tokens.font.title.large
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("An RDP session into a Windows machine, one window that tiles like any other. The profile lives in this plugin's own settings; no password is stored or passed on the command line.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    // ── Session ─────────────────────────────────────────────────────

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Session")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "dns"
            label: qsTr("Host")
            description: qsTr("Address or name of the machine to connect to")

            StyledRect {
                implicitWidth: root.fieldWidth
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: hostField

                    property string _value: RdpSettings.settings.host

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    activeFocusOnPress: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true
                    text: hostField._value
                    onTextChanged: hostField._value = hostField.text
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            RdpSettings.setHost(hostField.text);
                    }

                    StyledText {
                        visible: hostField.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("192.0.2.10")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SettingsRow {
            icon: "settings_ethernet"
            label: qsTr("Port")
            description: qsTr("3389 unless the machine says otherwise")

            StyledRect {
                implicitWidth: 96
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: portField

                    property string _value: String(RdpSettings.settings.port)

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    activeFocusOnPress: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true
                    inputMethodHints: Qt.ImhDigitsOnly
                    text: portField._value
                    onTextChanged: portField._value = portField.text
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            RdpSettings.setPort(portField.text);
                    }
                }
            }
        }

        SettingsRow {
            icon: "person"
            label: qsTr("User")
            description: qsTr("DOMAIN\\user as the machine expects it; leave empty to be asked")

            StyledRect {
                implicitWidth: root.fieldWidth
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: userField

                    property string _value: RdpSettings.settings.user

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    activeFocusOnPress: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true
                    text: userField._value
                    onTextChanged: userField._value = userField.text
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            RdpSettings.setUser(userField.text);
                    }

                    StyledText {
                        visible: userField.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "EXAMPLE\\user"
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        // NLA is what a domain machine wants. AAD is the Entra fallback: a
        // browser sign-in whose redirect URL is pasted back into the
        // terminal, for a machine that refuses NTLM outright.
        SettingsPresetRow {
            icon: "lock"
            label: qsTr("Security")
            description: qsTr("AAD when the machine refuses NLA and sends you to a browser instead")
            presets: [{
                    value: "nla",
                    label: qsTr("NLA")
                }, {
                    value: "aad",
                    label: qsTr("AAD")
                }]
            value: RdpSettings.settings.sec
            onSelected: value => RdpSettings.setSecurity(value)
        }

        SettingsPresetRow {
            icon: "verified_user"
            label: qsTr("Certificate")
            description: qsTr("Ignore matches the working setup; tofu accepts only what you have seen before")
            presets: [{
                    value: "ignore",
                    label: qsTr("Ignore")
                }, {
                    value: "tofu",
                    label: qsTr("Trust on first use")
                }]
            value: RdpSettings.settings.cert
            onSelected: value => RdpSettings.setCertificate(value)
        }
    }

    // ── Devices ─────────────────────────────────────────────────────

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Devices")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsToggleRow {
            icon: "mic"
            label: qsTr("Microphone")
            description: qsTr("Carries your local microphone into the session")
            checked: RdpSettings.settings.mic.enabled
            onToggled: state => RdpSettings.setMic({ enabled: state })
        }

        SettingsRow {
            icon: "graphic_eq"
            label: qsTr("Microphone device")
            description: RdpSettings.settings.mic.device.length > 0
                ? RdpSettings.settings.mic.device
                : qsTr("Empty means the system default")

            StyledRect {
                implicitWidth: root.fieldWidth
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: micField

                    property string _value: RdpSettings.settings.mic.device

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    activeFocusOnPress: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true
                    text: micField._value
                    onTextChanged: micField._value = micField.text
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            RdpSettings.setMic({ device: micField.text });
                    }

                    StyledText {
                        visible: micField.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("system default")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SettingsRow {
            icon: "speaker"
            label: qsTr("Speaker device")
            description: RdpSettings.settings.speaker.device.length > 0
                ? RdpSettings.settings.speaker.device
                : qsTr("Empty means the system default")

            StyledRect {
                implicitWidth: root.fieldWidth
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: speakerField

                    property string _value: RdpSettings.settings.speaker.device

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    activeFocusOnPress: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true
                    text: speakerField._value
                    onTextChanged: speakerField._value = speakerField.text
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            RdpSettings.setSpeaker({ device: speakerField.text });
                    }

                    StyledText {
                        visible: speakerField.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("system default")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SettingsToggleRow {
            icon: "videocam"
            label: qsTr("Camera")
            description: qsTr("Requests the remote camera channel, which the session needs for a webcam")
            checked: RdpSettings.settings.camera.enabled
            onToggled: state => RdpSettings.setCamera(state)
        }
    }

    // ── Window ──────────────────────────────────────────────────────

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Window")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsPresetRow {
            icon: "aspect_ratio"
            label: qsTr("Resolution")
            description: qsTr("Dynamic follows the window; the size below is the starting geometry either way")
            presets: [{
                    value: "dynamic",
                    label: qsTr("Follow the window")
                }, {
                    value: "fixed",
                    label: qsTr("Fixed")
                }]
            value: RdpSettings.settings.resolution.mode
            onSelected: value => RdpSettings.setResolution({ mode: value })
        }

        SettingsRow {
            icon: "photo_size_select_large"
            label: qsTr("Size")
            description: qsTr("The session's starting size, in pixels")

            RowLayout {
                spacing: Tokens.spacing.small

                StyledRect {
                    implicitWidth: 72
                    implicitHeight: 32
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainerHigh

                    TextInput {
                        id: widthField

                        property string _value: String(RdpSettings.settings.resolution.width)

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.small
                        activeFocusOnPress: true
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurface
                        clip: true
                        inputMethodHints: Qt.ImhDigitsOnly
                        text: widthField._value
                        onTextChanged: widthField._value = widthField.text
                        onActiveFocusChanged: {
                            if (!activeFocus)
                                RdpSettings.setResolution({ width: widthField.text });
                        }
                    }
                }

                StyledText {
                    text: "×"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                StyledRect {
                    implicitWidth: 72
                    implicitHeight: 32
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3surfaceContainerHigh

                    TextInput {
                        id: heightField

                        property string _value: String(RdpSettings.settings.resolution.height)

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.small
                        activeFocusOnPress: true
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurface
                        clip: true
                        inputMethodHints: Qt.ImhDigitsOnly
                        text: heightField._value
                        onTextChanged: heightField._value = heightField.text
                        onActiveFocusChanged: {
                            if (!activeFocus)
                                RdpSettings.setResolution({ height: heightField.text });
                        }
                    }
                }
            }
        }

        // The class is also the compositor's match expression, so it is the
        // one name that has to stay stable for window rules to keep working.
        SettingsRow {
            icon: "label"
            label: qsTr("Window class")
            description: qsTr("What window rules match on; the default is what the working setup used")

            StyledRect {
                implicitWidth: root.fieldWidth
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: classField

                    property string _value: RdpSettings.settings.window.class

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    activeFocusOnPress: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true
                    text: classField._value
                    onTextChanged: classField._value = classField.text
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            RdpSettings.setWindow({ class: classField.text });
                    }

                    StyledText {
                        visible: classField.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "work-rdp"
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        // Pinning is what keeps the session off whatever workspace the
        // launcher happened to be on. Empty or `none` leaves it alone, which
        // is what keeps wheel-scroll workspace flipping working.
        SettingsRow {
            icon: "push_pin"
            label: qsTr("Same space always")
            description: qsTr("A workspace id, or special:rdp. `none` leaves the window where it opens")

            StyledRect {
                implicitWidth: 160
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: workspaceField

                    property string _value: RdpSettings.settings.window.workspace

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    activeFocusOnPress: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true
                    text: workspaceField._value
                    onTextChanged: workspaceField._value = workspaceField.text
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            RdpSettings.setWindow({ workspace: workspaceField.text.trim() || "none" });
                    }
                }
            }
        }

        SettingsToggleRow {
            icon: "keyboard"
            label: qsTr("Send the Windows key through")
            description: qsTr("Off means the compositor keeps SUPER for itself and the remote session never sees it")
            checked: RdpSettings.settings.window.grab_keyboard
            onToggled: state => RdpSettings.setWindow({ grab_keyboard: state })
        }

        SettingsToggleRow {
            icon: "autorenew"
            label: qsTr("Reconnect after a drop")
            checked: RdpSettings.settings.window.auto_reconnect
            onToggled: state => RdpSettings.setWindow({ auto_reconnect: state })
        }

        SettingsToggleRow {
            icon: "fullscreen"
            label: qsTr("Open fullscreen")
            description: qsTr("Off by default: SUPER + SHIFT + F fullscreens the window when you want it")
            checked: RdpSettings.settings.window.fullscreen
            onToggled: state => RdpSettings.setWindow({ fullscreen: state })
        }
    }

    // ── Advanced ────────────────────────────────────────────────────

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Advanced")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "terminal"
            label: qsTr("Extra arguments")
            description: qsTr("Passed to xfreerdp3 as typed, split on spaces, after everything above. A flag carrying a password is refused, because the session asks for it instead.")

            StyledRect {
                implicitWidth: root.fieldWidth
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: extraField

                    property string _value: RdpSettings.settings.extra

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    activeFocusOnPress: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true
                    text: extraField._value
                    onTextChanged: extraField._value = extraField.text
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            RdpSettings.setExtra(extraField.text);
                    }

                    StyledText {
                        visible: extraField.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("/f /bpp:16")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }
    }

    // ── The session itself ──────────────────────────────────────────

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "computer"
            label: qsTr("Session")
            description: !RdpSettings.statusKnown
                ? qsTr("No compositor to ask, so the state is unknown")
                : (RdpSettings.sessionRunning ? qsTr("Running") : qsTr("Not running"))

            RowLayout {
                spacing: Tokens.spacing.small

                StyledRect {
                    implicitWidth: connectLabel.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 32
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primary
                    opacity: RdpSettings.settings.host.length > 0 ? 1 : 0.5

                    StyledText {
                        id: connectLabel
                        anchors.centerIn: parent
                        text: qsTr("Connect")
                        color: Colours.contrastOn(Colours.palette.m3primary)
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        disabled: RdpSettings.settings.host.length === 0
                        onClicked: {
                            Quickshell.execDetached(["aphotic", "xfreerdp", "connect"]);
                            RdpSettings.refreshStatus();
                        }
                    }
                }

                StyledRect {
                    implicitWidth: disconnectLabel.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 32
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainer
                    border.width: 1
                    border.color: Colours.signalStyle.hairline

                    StyledText {
                        id: disconnectLabel
                        anchors.centerIn: parent
                        text: qsTr("Disconnect")
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        onClicked: {
                            Quickshell.execDetached(["aphotic", "xfreerdp", "disconnect"]);
                            RdpSettings.refreshStatus();
                        }
                    }
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        visible: RdpSettings.settings.host.length === 0
        text: qsTr("Set a host before connecting. The password is asked for when the session starts, never stored here.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    // The status line follows the compositor rather than a poll: a session
    // opening or closing is an event, and the pane is only one of the ways
    // one can start.
    Connections {
        target: Hypr

        function onRawEvent(name: string, data: string): void {
            if (name === "openwindow" || name === "closewindow")
                RdpSettings.refreshStatus();
        }
    }

    Component.onCompleted: RdpSettings.refreshStatus()
}
