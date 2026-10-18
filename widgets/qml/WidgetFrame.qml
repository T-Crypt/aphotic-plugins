// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.config
import qs.services
import qs.modules.plugins.widgets.parts
import "Catalog.js" as Catalog

// One placed widget: its glass, its content and, while editing, the
// handles that move, resize, configure and remove it. Position and size
// come from the store; a drag only offsets them until it is let go.
Item {
    id: frame

    required property var widget
    property real screenW: 1920
    property real screenH: 1080
    property bool active: true

    readonly property var entry: Catalog.byType(frame.widget.type)
    readonly property var cfg: WidgetsStore.configOf(frame.widget)
    readonly property bool editing: WidgetsStore.editing
    readonly property bool configuring: WidgetsStore.configuring === frame.widget.uid

    property real dx: 0
    property real dy: 0
    property real dw: 0
    property real dh: 0

    readonly property Region region: Region {
        item: frame
    }

    x: frame.widget.x + frame.dx
    y: frame.widget.y + frame.dy
    width: Math.max(frame.entry?.minW ?? 60, frame.widget.w + frame.dw)
    height: Math.max(frame.entry?.minH ?? 40, frame.widget.h + frame.dh)

    function commit(): void {
        WidgetsStore.place(frame.widget.uid, { x: frame.x, y: frame.y, w: frame.width, h: frame.height }, frame.screenW, frame.screenH);
        frame.dx = 0;
        frame.dy = 0;
        frame.dw = 0;
        frame.dh = 0;
    }

    Rectangle {
        id: glass

        anchors.fill: parent
        visible: frame.cfg.background !== "none" || frame.editing
        radius: Tokens.rounding.large
        color: frame.cfg.background === "glass" ? Qt.alpha(Colours.signalStyle.surface, frame.cfg.opacity) : "transparent"
        border.width: 1
        border.color: frame.configuring ? Colours.signal : (frame.editing && frame.cfg.background === "none" ? Qt.alpha(Colours.signal, 0.5) : Colours.signalStyle.hairline)

        // Light along the top edge, inset by the radius: the Signal card's
        // depth cue, never a shadow.
        Rectangle {
            visible: frame.cfg.background === "glass"
            x: glass.radius
            width: parent.width - glass.radius * 2
            height: 1
            color: Colours.signalStyle.edgeLight
        }
    }

    Loader {
        id: content

        anchors.fill: parent
        anchors.margins: frame.cfg.background === "none" ? 4 : 14
        asynchronous: true
        source: frame.entry ? Qt.resolvedUrl(`widgets/${frame.entry.file}`) : ""
        enabled: !frame.editing
    }

    Binding {
        when: content.item !== null
        target: content.item
        property: "uid"
        value: frame.widget.uid
    }

    Binding {
        when: content.item !== null
        target: content.item
        property: "config"
        value: frame.cfg
    }

    Binding {
        when: content.item !== null
        target: content.item
        property: "store"
        value: frame.widget.data
    }

    Binding {
        when: content.item !== null
        target: content.item
        property: "active"
        value: frame.active
    }

    Binding {
        when: content.item !== null
        target: content.item
        property: "editing"
        value: frame.editing
    }

    // Edit mode: the whole card moves, the corner resizes.
    MouseArea {
        id: mover

        property point origin

        anchors.fill: parent
        visible: frame.editing
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: mouse => {
            mover.origin = mapToItem(frame.parent, mouse.x, mouse.y);
            WidgetsStore.raise(frame.widget.uid);
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const p = mapToItem(frame.parent, mouse.x, mouse.y);
            frame.dx = p.x - mover.origin.x;
            frame.dy = p.y - mover.origin.y;
        }
        onReleased: frame.commit()
        onDoubleClicked: WidgetsStore.configuring = frame.widget.uid
    }

    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 4
        width: 16
        height: 16
        radius: 4
        visible: frame.editing
        color: Qt.alpha(Colours.signal, sizer.containsMouse || sizer.pressed ? 0.5 : 0.25)

        MaterialIcon {
            anchors.centerIn: parent
            text: "open_in_full"
            rotation: 90
            color: Colours.palette.m3onSurface
            font.pixelSize: 12
        }

        MouseArea {
            id: sizer

            property point origin

            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
            onPressed: mouse => sizer.origin = mapToItem(frame.parent, mouse.x, mouse.y)
            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                const p = mapToItem(frame.parent, mouse.x, mouse.y);
                frame.dw = p.x - sizer.origin.x;
                frame.dh = p.y - sizer.origin.y;
            }
            onReleased: frame.commit()
        }
    }

    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 6
        spacing: 4
        visible: frame.editing

        IconButton {
            icon: "tune"
            size: 24
            filled: true
            onClicked: WidgetsStore.configuring = frame.configuring ? "" : frame.widget.uid
        }

        IconButton {
            icon: "close"
            size: 24
            filled: true
            colour: Colours.palette.m3error
            onClicked: WidgetsStore.remove(frame.widget.uid)
        }
    }

    WText {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 8
        visible: frame.editing
        text: `${frame.entry?.label ?? frame.widget.type} · ${Math.round(frame.width)}×${Math.round(frame.height)}`
        color: Colours.palette.m3onSurfaceVariant
        font.pixelSize: 10
    }
}
