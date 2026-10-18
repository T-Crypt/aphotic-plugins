// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services
import qs.modules.plugins.widgets.parts

// The apps named in settings, or with none named, the ones launched most.
WidgetBase {
    id: root

    readonly property var named: String(root.config.apps ?? "").split(",").map(s => s.trim()).filter(s => s.length > 0)
    readonly property var entries: {
        if (root.named.length > 0)
            return root.named.map(id => DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id)).filter(e => e);
        const counts = LauncherUsage.counts;
        return DesktopEntries.applications.values.filter(e => (counts[e.id] ?? 0) > 0).sort((a, b) => (counts[b.id] ?? 0) - (counts[a.id] ?? 0)).slice(0, 8);
    }
    readonly property real cell: Math.min(root.height - (root.config.labels ? 16 : 0), root.width / Math.max(1, root.entries.length))

    Row {
        anchors.centerIn: parent

        Repeater {
            model: root.entries

            Item {
                id: app

                required property var modelData

                width: root.cell
                height: root.cell + (root.config.labels ? 16 : 0)

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.cell * 0.86
                    height: width
                    radius: width * 0.28
                    color: tap.containsMouse ? Colours.signalStyle.hover : "transparent"
                    border.width: tap.containsMouse ? 1 : 0
                    border.color: Colours.signalStyle.hairline

                    AppIcon {
                        anchors.centerIn: parent
                        name: app.modelData.icon
                        appClass: app.modelData.id
                        size: root.cell * 0.56
                    }
                }

                WText {
                    visible: root.config.labels === true
                    anchors.bottom: parent.bottom
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: app.modelData.name
                    color: root.muted
                    font.pixelSize: 10
                }

                MouseArea {
                    id: tap

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        LauncherUsage.recordLaunch(app.modelData.id);
                        app.modelData.execute();
                    }
                }
            }
        }
    }

    WText {
        anchors.centerIn: parent
        visible: root.entries.length === 0
        text: qsTr("Name some apps in settings")
        color: root.muted
    }
}
