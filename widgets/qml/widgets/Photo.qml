// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import qs.components
import qs.modules.plugins.widgets.parts

WidgetBase {
    id: root

    readonly property string expanded: String(root.config.path ?? "").trim().replace(/^~(?=\/|$)/, Quickshell.env("HOME"))
    readonly property bool isImage: /\.(png|jpe?g|webp|gif|bmp)$/i.test(root.expanded)
    property int index: 0

    FolderListModel {
        id: folder

        folder: !root.isImage && root.expanded ? `file://${root.expanded}` : ""
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    Ticker {
        active: root.active && !root.isImage && folder.count > 1
        interval: (root.config.minutes ?? 10) * 60000
        triggeredOnStart: false
        onTriggered: root.index = (root.index + 1) % folder.count
    }

    readonly property string source: root.isImage ? `file://${root.expanded}` : (folder.count > 0 ? String(folder.get(root.index % folder.count, "fileUrl")) : "")

    StyledClippingRect {
        anchors.fill: parent
        radius: 10
        color: "transparent"

        Image {
            anchors.fill: parent
            source: root.source
            asynchronous: true
            fillMode: root.config.fit === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
            sourceSize.width: 1024
            sourceSize.height: 1024
        }
    }

    WText {
        anchors.centerIn: parent
        visible: root.source === ""
        width: parent.width - 20
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        text: qsTr("Set an image or a folder in this widget's settings")
        color: root.muted
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.isImage && folder.count > 1
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.index = (root.index + 1) % folder.count
    }
}
