// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    readonly property var items: root.store.items ?? []
    readonly property var shown: root.config.clearDone ? root.items.filter(i => !i.done) : root.items

    function setItems(list: var): void {
        root.save("items", list);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true

            WText {
                Layout.fillWidth: true
                text: root.config.title || qsTr("To-do")
                font.pixelSize: 15
                font.weight: Font.Medium
            }

            WText {
                text: `${root.items.filter(i => i.done).length}/${root.items.length}`
                color: root.muted
                font.family: "JetBrainsMono Nerd Font Mono"
                font.pixelSize: 11
            }
        }

        Flickable {
            id: list

            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: col

                width: list.width - 10
                spacing: 2

                Repeater {
                    model: root.shown

                    RowLayout {
                        id: item

                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            implicitWidth: 16
                            implicitHeight: 16
                            radius: 4
                            color: item.modelData.done ? root.accent : "transparent"
                            border.width: 1
                            border.color: item.modelData.done ? root.accent : root.muted

                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: item.modelData.done === true
                                text: "check"
                                color: root.onAccent
                                font.pixelSize: 13
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setItems(root.items.map(i => i.id === item.modelData.id ? Object.assign({}, i, { done: !i.done }) : i))
                            }
                        }

                        WText {
                            Layout.fillWidth: true
                            text: item.modelData.text
                            color: item.modelData.done ? root.muted : root.ink
                            font.strikeout: item.modelData.done === true
                            font.pixelSize: 13
                        }

                        IconButton {
                            icon: "close"
                            size: 18
                            colour: root.muted
                            onClicked: root.setItems(root.items.filter(i => i.id !== item.modelData.id))
                        }
                    }
                }
            }
        }

        Field {
            id: adder

            Layout.fillWidth: true
            owner: root.uid
            placeholder: qsTr("Add an item and press Enter")
            onCommitted: value => {
                const text = value.trim();
                if (text.length > 0)
                    root.setItems(root.items.concat([{ id: Date.now().toString(36), text: text, done: false }]));
                adder.clear();
            }
        }
    }

    FlickScrollBar {
        flickable: list
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 28
        anchors.bottomMargin: 36
    }
}
