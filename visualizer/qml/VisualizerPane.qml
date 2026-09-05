// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.plugins.visualizer

// Docked into the Appearance category (see plugin.toml's
// [ui.settings_pane], parent = "appearance"). Two knobs over
// CavaSpectrum's own state, persisted to this plugin's own
// config/settings.json -- see that file's _saveSettings/FileView pair.
// No shared "Slider" component exists anywhere in core Settings yet, so
// IntensitySlider below is self-contained rather than reaching for one
// that isn't there.
ColumnLayout {
    id: root

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Spectrum")
        font: Tokens.font.title.large
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Tune how the audio spectrum along the bottom of the screen reacts. Both take effect immediately -- there's nothing to play with while it's silent, so try it against something with a beat.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    // StyledRect root with first/last, not a bare ColumnLayout --
    // SettingsGroup stamps first/last on any child exposing those two
    // properties (duck-typed by name, see SettingsGroup.qml) to render
    // a connected card, the same shape PluginsPane.qml's own PluginRow
    // uses for the identical reason. Declared as a sibling of
    // SettingsGroup below (matching where PluginsPane.qml declares its
    // own inline components -- directly under the pane's root, not
    // nested inside another instantiated item), not inside it.
    component IntensitySlider: StyledRect {
        id: slider

        required property string label
        required property string description
        required property real value
        required property real from
        required property real to
        signal moved(real value)

        property bool first: true
        property bool last: true

        readonly property real ratio: Math.max(0, Math.min(1, (slider.value - slider.from) / (slider.to - slider.from)))

        Layout.fillWidth: true
        implicitHeight: content.implicitHeight + Tokens.padding.large * 2

        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)
        topLeftRadius: slider.first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        topRightRadius: slider.first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        bottomLeftRadius: slider.last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        bottomRightRadius: slider.last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: slider.label
                    font: Tokens.font.body.medium
                }

                StyledText {
                    text: slider.value.toFixed(2)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: slider.description
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }

            StyledRect {
                id: track

                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                implicitHeight: 6
                radius: Tokens.rounding.full
                color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                StyledRect {
                    width: track.width * slider.ratio
                    height: parent.height
                    radius: parent.radius
                    color: Colours.palette.m3primary
                }

                // Whole-track jump, declared first so the handle's
                // own drag area (declared after, below) sits on top
                // of it in the region where both overlap -- a direct
                // click on the handle drags instead of jumping out
                // from under the pointer.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => slider.moved(slider.from + Math.max(0, Math.min(1, mouse.x / track.width)) * (slider.to - slider.from))
                }

                StyledRect {
                    id: handle

                    width: 16
                    height: 16
                    radius: 8
                    color: Colours.palette.m3primary
                    y: (track.height - height) / 2
                    x: track.width * slider.ratio - width / 2

                    MouseArea {
                        id: dragArea

                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true

                        function apply(mx: real): void {
                            const local = mapToItem(track, mx, 0).x;
                            const ratio = Math.max(0, Math.min(1, local / track.width));
                            slider.moved(slider.from + ratio * (slider.to - slider.from));
                        }

                        onPressed: mouse => dragArea.apply(mouse.x)
                        onPositionChanged: mouse => {
                            if (dragArea.pressed)
                                dragArea.apply(mouse.x);
                        }
                    }
                }
            }
        }
    }

    SettingsGroup {
        Layout.fillWidth: true

        IntensitySlider {
            label: qsTr("Spectrum intensity")
            description: qsTr("How tall the bars swing for the same audio level. Lower is subtler, higher is punchier.")
            value: CavaSpectrum.sensitivity
            from: 0.4
            to: 2.5
            onMoved: value => CavaSpectrum.setSensitivity(value)
        }

        IntensitySlider {
            label: qsTr("Wave smoothing")
            description: qsTr("How the bars fall between beats. Lower is sharp and reactive, higher is a slower, flowing wave.")
            value: CavaSpectrum.waveSmoothing
            from: 0.08
            to: 0.6
            onMoved: value => CavaSpectrum.setWaveSmoothing(value)
        }
    }
}
