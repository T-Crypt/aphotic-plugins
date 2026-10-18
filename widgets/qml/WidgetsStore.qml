// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "Catalog.js" as Catalog

// The placed widgets and everything the user typed into them, in one
// file. A widget record is {uid, type, screen, x, y, w, h, config, data}:
// `config` is what the settings sheet edits, `data` is what the widget
// itself keeps (a note's text, a checklist).
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("HOME")}/.config/aphotic/plugins/widgets`
    readonly property string path: `${root.dir}/layout.json`
    readonly property int grid: 8

    property var widgets: []
    property bool loaded: false
    property bool editing: false
    property string configuring: ""
    property string catalogScreen: ""
    // The uid whose text field has focus; the overlay takes keys only then.
    property string typing: ""

    property bool hideWhenCovered: true

    function toggleEdit(): void {
        root.editing = !root.editing;
        if (!root.editing) {
            root.configuring = "";
            root.catalogScreen = "";
        }
    }

    function _uid(): string {
        return `${Date.now().toString(36)}${Math.floor(Math.random() * 1e6).toString(36)}`;
    }

    function byUid(uid: string): var {
        return root.widgets.find(w => w.uid === uid) ?? null;
    }

    function configOf(widget: var): var {
        return Catalog.merged(widget?.type ?? "", widget?.config ?? {});
    }

    function add(type: string, screen: string, x: real, y: real): string {
        const entry = Catalog.byType(type);
        if (!entry)
            return "";
        const uid = root._uid();
        root.widgets = root.widgets.concat([{
                uid: uid,
                type: type,
                screen: screen,
                x: Catalog.snap(x, root.grid),
                y: Catalog.snap(y, root.grid),
                w: entry.w,
                h: entry.h,
                config: {},
                data: {}
            }]);
        root._save();
        return uid;
    }

    function remove(uid: string): void {
        root.widgets = root.widgets.filter(w => w.uid !== uid);
        if (root.configuring === uid)
            root.configuring = "";
        root._save();
    }

    function _patch(uid: string, patch: var): void {
        root.widgets = root.widgets.map(w => w.uid === uid ? Object.assign({}, w, patch) : w);
        root._save();
    }

    function place(uid: string, rect: var, screenW: real, screenH: real): void {
        const widget = root.byUid(uid);
        if (!widget)
            return;
        const snapped = { x: Catalog.snap(rect.x, root.grid), y: Catalog.snap(rect.y, root.grid), w: Catalog.snap(rect.w, root.grid), h: Catalog.snap(rect.h, root.grid) };
        root._patch(uid, Catalog.clampRect(snapped, Catalog.byType(widget.type), screenW, screenH));
    }

    function setConfig(uid: string, key: string, value: var): void {
        const widget = root.byUid(uid);
        if (!widget)
            return;
        root._patch(uid, { config: Object.assign({}, widget.config, { [key]: value }) });
    }

    function setData(uid: string, key: string, value: var): void {
        const widget = root.byUid(uid);
        if (!widget)
            return;
        root._patch(uid, { data: Object.assign({}, widget.data, { [key]: value }) });
    }

    function raise(uid: string): void {
        const widget = root.byUid(uid);
        if (!widget)
            return;
        root.widgets = root.widgets.filter(w => w.uid !== uid).concat([widget]);
        root._save();
    }

    function setHideWhenCovered(value: bool): void {
        root.hideWhenCovered = value;
        root._save();
    }

    function _apply(text: string): void {
        let parsed = null;
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            parsed = null;
        }
        const list = Array.isArray(parsed?.widgets) ? parsed.widgets : [];
        root.widgets = list.filter(w => w && typeof w.uid === "string" && Catalog.byType(w.type)).map(w => ({
                    uid: w.uid,
                    type: w.type,
                    screen: typeof w.screen === "string" ? w.screen : "",
                    x: Number(w.x) || 0,
                    y: Number(w.y) || 0,
                    w: Number(w.w) || Catalog.byType(w.type).w,
                    h: Number(w.h) || Catalog.byType(w.type).h,
                    config: w.config && typeof w.config === "object" ? w.config : {},
                    data: w.data && typeof w.data === "object" ? w.data : {}
                }));
        root.hideWhenCovered = parsed?.hideWhenCovered !== false;
        root.loaded = true;
    }

    // A first run with no file places a clock and a date, so the plugin is
    // visibly on and SUPER+ALT+W has something to show.
    function _starter(): void {
        root.widgets = [
            { uid: root._uid(), type: "clockDigital", screen: "", x: 64, y: 96, w: 320, h: 150, config: {}, data: {} },
            { uid: root._uid(), type: "calendarMonth", screen: "", x: 64, y: 264, w: 300, h: 290, config: {}, data: {} }
        ];
        root.loaded = true;
        root._save();
    }

    function _save(): void {
        if (root.loaded)
            saveTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: mkdir.running = true
    }

    Process {
        id: mkdir

        command: ["mkdir", "-p", root.dir]
        onExited: writer.setText(JSON.stringify({ version: 1, hideWhenCovered: root.hideWhenCovered, widgets: root.widgets }, null, 2) + "\n")
    }

    FileView {
        id: reader

        path: root.path
        printErrors: false
        onLoaded: root._apply(reader.text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root._starter();
            else
                root.loaded = true;
        }
    }

    FileView {
        id: writer

        path: root.path
        printErrors: false
    }
}
