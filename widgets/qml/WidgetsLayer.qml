// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services
import qs.modules.plugins.widgets.parts

// The widgets placed on one screen. Core gives every screen a free
// overlay on the bottom layer; this hands back a mask with one region per
// widget, so only the widgets take clicks. Editing takes the whole screen
// so a widget can be dragged anywhere and the catalog can open.
Item {
    id: root

    readonly property string screenName: Screen.name
    readonly property bool primary: root.screenName === "" || (Quickshell.screens[0]?.name ?? "") === root.screenName
    readonly property var screenNames: Quickshell.screens.map(s => s.name)

    // A widget saved on a screen that is not plugged in shows on the
    // first screen rather than vanishing.
    readonly property var mine: WidgetsStore.widgets.filter(w => w.screen === root.screenName || (root.primary && (w.screen === "" || !root.screenNames.includes(w.screen))))

    readonly property bool covered: {
        if (!WidgetsStore.hideWhenCovered)
            return false;
        const monitor = (Hypr.monitors?.values ?? []).find(m => m.name === root.screenName);
        return monitor?.activeWorkspace?.lastIpcObject?.hasfullscreen === true;
    }

    readonly property bool editing: WidgetsStore.editing
    readonly property bool wantsKeyboard: root.editing || WidgetsStore.typing !== ""
    readonly property var configWidget: WidgetsStore.configuring ? root.mine.find(w => w.uid === WidgetsStore.configuring) ?? null : null

    property var _frameRegions: []

    function _collect(): void {
        const list = [];
        for (let i = 0; i < frames.count; i++) {
            const frame = frames.itemAt(i);
            if (frame)
                list.push(frame.region);
        }
        root._frameRegions = list;
    }

    readonly property Region maskRegion: Region {
        regions: root.editing ? [root.fullRegion] : (root.covered ? [] : root._frameRegions)
    }

    readonly property Region fullRegion: Region {
        item: root
    }

    // For a shell without `maskRegion`: the whole screen while editing,
    // nothing otherwise, so the desktop never loses its clicks.
    readonly property Item maskItem: root.editing ? root : noInput

    Item {
        id: noInput
    }

    // Editing dims the desktop a little and draws the grid widgets snap to.
    Rectangle {
        anchors.fill: parent
        visible: root.editing
        color: Qt.alpha(Colours.palette.m3scrim ?? "#000000", 0.28)

        MouseArea {
            anchors.fill: parent
            onClicked: {
                WidgetsStore.configuring = "";
                WidgetsStore.catalogScreen = "";
            }
        }
    }

    Repeater {
        id: frames

        model: root.mine

        onItemAdded: root._collect()
        onItemRemoved: Qt.callLater(root._collect)

        WidgetFrame {
            required property var modelData

            widget: modelData
            screenW: root.width
            screenH: root.height
            visible: !root.covered
            active: !root.covered && !SessionLockState.locked
        }
    }

    WidgetConfig {
        id: sheet

        visible: root.editing && root.configWidget !== null
        widget: root.configWidget ?? ({ uid: "", type: "", config: {} })
        x: {
            const w = root.configWidget;
            if (!w)
                return 0;
            const right = w.x + w.w + 12;
            return right + width <= root.width ? right : Math.max(0, w.x - width - 12);
        }
        y: Math.max(0, Math.min((root.configWidget?.y ?? 0), root.height - height))
    }

    // The edit bar: add, done, and a count. Top centre of every screen.
    Rectangle {
        id: bar

        visible: root.editing
        anchors.horizontalCenter: parent.horizontalCenter
        y: 64
        width: barRow.implicitWidth + 24
        height: 44
        radius: 22
        color: Colours.signalStyle.raised
        border.width: 1
        border.color: Colours.signal

        RowLayout {
            id: barRow

            anchors.centerIn: parent
            spacing: 10

            MaterialIcon {
                text: "dashboard_customize"
                color: Colours.signal
                font.pixelSize: 18
            }

            WText {
                text: qsTr("Editing widgets · %n on this screen", "", root.mine.length)
                font.pixelSize: 13
            }

            Rectangle {
                implicitWidth: addLabel.implicitWidth + 24
                implicitHeight: 30
                radius: 15
                color: Qt.alpha(Colours.signal, 0.2)
                border.width: 1
                border.color: Colours.signal

                WText {
                    id: addLabel

                    anchors.centerIn: parent
                    text: qsTr("Add widget")
                    font.pixelSize: 12
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: WidgetsStore.catalogScreen = WidgetsStore.catalogScreen === root.screenName ? "" : root.screenName
                }
            }

            Rectangle {
                implicitWidth: doneLabel.implicitWidth + 24
                implicitHeight: 30
                radius: 15
                color: "transparent"
                border.width: 1
                border.color: Colours.signalStyle.hairline

                WText {
                    id: doneLabel

                    anchors.centerIn: parent
                    text: qsTr("Done")
                    font.pixelSize: 12
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: WidgetsStore.toggleEdit()
                }
            }
        }
    }

    Loader {
        active: root.editing && WidgetsStore.catalogScreen === root.screenName
        anchors.centerIn: parent

        sourceComponent: CatalogPanel {
            screenName: root.screenName
            screenW: root.width
            screenH: root.height
        }
    }

    Keys.onEscapePressed: {
        if (root.editing)
            WidgetsStore.toggleEdit();
    }
    focus: root.editing
}
