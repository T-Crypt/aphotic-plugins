pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

Rectangle {
    id: root

    required property string label
    property color accent: Colours.palette.m3primaryOnSurface
    property bool removable: false
    property bool interactive: true

    signal clicked
    signal removed

    implicitWidth: chipRow.implicitWidth + 20
    implicitHeight: 26
    radius: 999
    color: Qt.alpha(root.accent, 0.14)
    border.width: 1
    border.color: Qt.alpha(root.accent, 0.42)

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: root.accent
        opacity: chipMouse.containsMouse ? 0.06 : 0

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }
    }

    RowLayout {
        id: chipRow
        z: 1
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: root.label
            color: root.accent
            font.family: "Inter, Noto Sans, Sans-Serif"
            font.pixelSize: 11
            font.weight: Font.Medium
        }

        MaterialIcon {
            visible: root.removable
            text: "close"
            color: root.accent
            font.pixelSize: 14

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

    MouseArea {
        id: chipMouse
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
