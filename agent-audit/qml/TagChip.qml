pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// One pill. Tags, status and the kind of a step all wear this, so the
// audit reads as one vocabulary rather than three shapes doing the same
// job.
StyledRect {
    id: root

    required property string label
    property color accent: Colours.palette.m3primaryOnSurface
    property string icon: ""
    property bool removable: false
    property bool interactive: true
    property bool filled: false

    signal clicked
    signal removed

    implicitWidth: chipRow.implicitWidth + Tokens.padding.medium * 2
    implicitHeight: 26
    radius: Tokens.rounding.full
    color: Qt.alpha(root.accent, root.filled ? 0.22 : 0.12)
    border.width: 1
    border.color: Qt.alpha(root.accent, root.filled ? 0.55 : 0.32)

    StateLayer {
        color: root.accent
        disabled: !root.interactive
        onClicked: root.clicked()
    }

    RowLayout {
        id: chipRow

        z: 1
        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            visible: root.icon.length > 0
            text: root.icon
            color: root.accent
            fontStyle: Tokens.font.icon.small
            fill: 1
        }

        StyledText {
            text: root.label
            color: root.accent
            font: Tokens.font.label.small
        }

        MaterialIcon {
            visible: root.removable
            text: "close"
            color: root.accent
            fontStyle: Tokens.font.icon.small

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    mouse.accepted = true;
                    root.removed();
                }
            }
        }
    }
}
