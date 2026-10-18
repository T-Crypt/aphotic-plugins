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

// The settings sheet for one widget, drawn from its catalog schema: every
// field a widget declares gets a row, with no per-widget sheet to write.
Rectangle {
    id: root

    required property var widget

    readonly property var entry: Catalog.byType(root.widget?.type ?? "")
    readonly property var schema: Catalog.schemaOf(root.widget?.type ?? "")
    readonly property var cfg: WidgetsStore.configOf(root.widget)
    readonly property var keys: Object.keys(root.schema)

    width: 300
    height: Math.min(560, column.implicitHeight + 28)
    radius: Tokens.rounding.large
    color: Colours.signalStyle.raised
    border.width: 1
    border.color: Colours.signalStyle.hairline

    // Swallow clicks so the edit backdrop under the sheet does not close it.
    MouseArea {
        anchors.fill: parent
    }

    Flickable {
        id: flick

        anchors.fill: parent
        anchors.margins: 14
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column

            width: flick.width - (bar.visible ? 14 : 0)
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                WText {
                    Layout.fillWidth: true
                    text: root.entry?.label ?? ""
                    font.pixelSize: 15
                    font.weight: Font.Medium
                }

                IconButton {
                    icon: "close"
                    size: 24
                    onClicked: WidgetsStore.configuring = ""
                }
            }

            Repeater {
                model: root.keys

                ColumnLayout {
                    id: row

                    required property string modelData
                    readonly property var field: root.schema[row.modelData]
                    readonly property var value: root.cfg[row.modelData]

                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        visible: row.field.type === "bool" || row.field.type === "number"

                        WText {
                            Layout.fillWidth: true
                            text: row.field.label
                            color: Colours.palette.m3onSurfaceVariant
                            font.pixelSize: 12
                        }

                        Toggle {
                            visible: row.field.type === "bool"
                            checked: row.value === true
                            onToggled: value => WidgetsStore.setConfig(root.widget.uid, row.modelData, value)
                        }

                        Stepper {
                            visible: row.field.type === "number"
                            value: Number(row.value) || 0
                            from: row.field.min ?? 0
                            to: row.field.max ?? 100
                            step: row.field.step ?? 1
                            onChanged: value => WidgetsStore.setConfig(root.widget.uid, row.modelData, value)
                        }
                    }

                    WText {
                        visible: row.field.type === "enum" || row.field.type === "text"
                        text: row.field.label
                        color: Colours.palette.m3onSurfaceVariant
                        font.pixelSize: 12
                    }

                    Segmented {
                        Layout.fillWidth: true
                        visible: row.field.type === "enum"
                        values: row.field.values ?? []
                        labels: row.field.labels ?? []
                        current: row.value
                        onPicked: value => WidgetsStore.setConfig(root.widget.uid, row.modelData, value)
                    }

                    Field {
                        Layout.fillWidth: true
                        visible: row.field.type === "text"
                        owner: `config:${root.widget.uid}`
                        text: String(row.value ?? "")
                        onCommitted: value => WidgetsStore.setConfig(root.widget.uid, row.modelData, value)
                    }
                }
            }

            WText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: qsTr("Drag to move, drag the corner to resize. Double-click a widget to open this sheet.")
                wrapMode: Text.Wrap
                color: Colours.palette.m3onSurfaceVariant
                font.pixelSize: 11
            }
        }
    }

    FlickScrollBar {
        id: bar

        flickable: flick
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 6
    }
}
