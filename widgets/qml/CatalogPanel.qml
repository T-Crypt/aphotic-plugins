// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services
import qs.modules.plugins.widgets.parts
import "Catalog.js" as Catalog

// Every widget the plugin ships, by category. A click places one in the
// middle of this screen; the panel stays open to add more.
Rectangle {
    id: root

    required property string screenName
    property real screenW: 1920
    property real screenH: 1080
    property string category: "clock"

    width: 760
    height: 520
    radius: Tokens.rounding.large
    color: Colours.signalStyle.raised
    border.width: 1
    border.color: Colours.signalStyle.hairline

    MouseArea {
        anchors.fill: parent
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        ColumnLayout {
            Layout.preferredWidth: 170
            Layout.fillHeight: true
            spacing: 4

            WText {
                Layout.bottomMargin: 8
                text: qsTr("Add a widget")
                font.pixelSize: 16
                font.weight: Font.Medium
            }

            Repeater {
                model: Catalog.CATEGORIES

                Rectangle {
                    id: cat

                    required property var modelData
                    readonly property bool on: root.category === cat.modelData.id

                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 8
                    color: cat.on ? Qt.alpha(Colours.signal, 0.16) : (catArea.containsMouse ? Colours.signalStyle.hover : "transparent")
                    border.width: cat.on ? 1 : 0
                    border.color: Colours.signal

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        MaterialIcon {
                            text: cat.modelData.icon
                            color: cat.on ? Colours.signal : Colours.palette.m3onSurfaceVariant
                            font.pixelSize: 16
                        }

                        WText {
                            Layout.fillWidth: true
                            text: cat.modelData.label
                            color: cat.on ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                            font.pixelSize: 13
                        }

                        WText {
                            text: String(Catalog.inCategory(cat.modelData.id).length)
                            color: Colours.palette.m3onSurfaceVariant
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: catArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.category = cat.modelData.id
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: 16
                color: "transparent"
                border.width: 1
                border.color: Colours.signalStyle.hairline

                WText {
                    anchors.centerIn: parent
                    text: qsTr("Close")
                    font.pixelSize: 12
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: WidgetsStore.catalogScreen = ""
                }
            }
        }

        Rectangle {
            Layout.fillHeight: true
            implicitWidth: 1
            color: Colours.signalStyle.hairline
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: grid

                anchors.fill: parent
                anchors.rightMargin: 14
                clip: true
                cellWidth: Math.floor(width / 2)
                cellHeight: 96
                boundsBehavior: Flickable.StopAtBounds
                model: Catalog.inCategory(root.category)

                delegate: Item {
                    id: card

                    required property var modelData

                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 10
                        color: cardArea.containsMouse ? Colours.signalStyle.hover : "transparent"
                        border.width: 1
                        border.color: cardArea.containsMouse ? Colours.signal : Colours.signalStyle.hairline

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            MaterialIcon {
                                Layout.alignment: Qt.AlignTop
                                text: card.modelData.icon
                                color: Colours.signal
                                font.pixelSize: 26
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: 2

                                WText {
                                    Layout.fillWidth: true
                                    text: card.modelData.label
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }

                                WText {
                                    Layout.fillWidth: true
                                    text: card.modelData.description
                                    color: Colours.palette.m3onSurfaceVariant
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                }
                            }
                        }

                        MouseArea {
                            id: cardArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WidgetsStore.add(card.modelData.type, root.screenName, (root.screenW - card.modelData.w) / 2, (root.screenH - card.modelData.h) / 2)
                        }
                    }
                }
            }

            FlickScrollBar {
                flickable: grid
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
            }
        }
    }
}
