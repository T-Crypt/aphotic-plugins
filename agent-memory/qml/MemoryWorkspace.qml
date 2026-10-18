pragma ComponentBehavior: Bound

// The memory workstation: pick a project on the left, read its failures,
// notes and tool balance in the middle, read the digest it would inject on
// the right.
//
// Everything here comes from the fold's own store: a signature, a count, a
// tool name, a timestamp, a note. No prompt, response or transcript text
// exists in that store, so nothing here pretends to show one.
//
// The plane owns the only watch in the plugin. It is created and destroyed
// with the plane, so a closed plane runs nothing at all; while it is open a
// new line in the event log rebuilds at most once every 1.5 s.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.components
import qs.config
import qs.services
import qs.modules.plugins.agentMemory

Item {
    id: root

    // --- Colour ---------------------------------------------------------
    //
    // The same split Agent Audit uses: decorative accents follow the
    // wallpaper, status does not. Pass, warn and fail keep a fixed hue and
    // take saturation and lightness from the live palette, so they stay
    // apart from each other under a palette wallust derived from a
    // wallpaper.
    readonly property color statusReference: Colours.palette.m3primaryOnSurface
    readonly property color statusPass: root.statusHue(145)
    readonly property color statusWarn: root.statusHue(42)
    readonly property color statusFail: root.statusHue(8)

    readonly property color accentTool: Colours.palette.m3primaryOnSurface
    readonly property color accentNote: Colours.palette.m3tertiaryOnSurface

    readonly property color panelColour: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
    readonly property color insetColour: Colours.palette.m3surfaceContainer
    readonly property color hairline: Qt.alpha(Colours.palette.m3onSurface, 0.09)
    readonly property color textPrimary: Colours.palette.m3onSurface
    readonly property color textMuted: Colours.palette.m3onSurfaceVariant

    readonly property font sectionFont: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(0.8).build()

    function statusHue(degrees: real): color {
        const ref = root.statusReference;
        return Qt.hsla(degrees / 360, Math.max(0.38, ref.hslSaturation), Math.min(0.72, Math.max(0.48, ref.hslLightness)), 1);
    }

    // --- State ----------------------------------------------------------

    property string selectedProject: ""
    property int tab: 0

    readonly property var projectRows: MemoryService.projects()
    readonly property string activeProject: root.selectedProject.length > 0
        ? root.selectedProject
        : (root.projectRows.length > 0 ? root.projectRows[0].path : "")

    readonly property var issueRows: root.activeProject.length > 0 ? MemoryService.errorsFor(root.activeProject) : []
    readonly property var noteRows: root.activeProject.length > 0 ? MemoryService.notesFor(root.activeProject) : []
    readonly property var toolRows: root.activeProject.length > 0 ? MemoryService.toolsFor(root.activeProject) : []
    readonly property var activeEntry: root.projectRows.find(row => row.path === root.activeProject) ?? null

    readonly property string injectionState: (MemoryService.lastOutput === "enabled" || MemoryService.lastOutput === "disabled")
        ? MemoryService.lastOutput
        : "unknown"

    readonly property int busiestTool: root.toolRows.reduce((most, row) => Math.max(most, row.calls), 0)

    // The store is a snapshot of the log, so a project that produced no
    // failures and wrote no notes is still a real row: it is the one that
    // answers "what did this session actually do".
    readonly property bool empty: root.projectRows.length === 0

    // The first read happens on open; the injection read is chained to it
    // by the service because both share one runner.
    Component.onCompleted: {
        MemoryService.injectStatus();
        MemoryService.build();
    }

    function agoLabel(ms: var): string {
        const delta = Date.now() - Number(ms ?? 0);
        if (!(delta > 0))
            return qsTr("now");
        const minutes = Math.floor(delta / 60000);
        if (minutes < 1)
            return qsTr("just now");
        if (minutes < 60)
            return qsTr("%1m ago").arg(minutes);
        const hours = Math.floor(minutes / 60);
        if (hours < 24)
            return qsTr("%1h ago").arg(hours);
        return qsTr("%1d ago").arg(Math.floor(hours / 24));
    }

    function dateLabel(ms: var): string {
        const value = Number(ms ?? 0);
        return value > 0 ? new Date(value).toISOString().slice(0, 10) : "";
    }

    // Both the button and the field's accept do this, so it is one function
    // rather than two copies that drift.
    function addNote(): void {
        const text = noteInput.text.trim();
        if (root.activeProject.length === 0 || text.length === 0)
            return;
        MemoryService.act("note", [text, "--project", root.activeProject]);
        noteInput.text = "";
    }

    function secondsLabel(ms: var): string {
        const value = Number(ms ?? 0);
        if (value <= 0)
            return "0s";
        if (value < 1000)
            return `${value} ms`;
        return `${(value / 1000).toFixed(1)}s`;
    }

    // --- Shared pieces --------------------------------------------------

    component SectionLabel: StyledText {
        color: root.textMuted
        font: root.sectionFont
    }

    component Divider: StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: root.hairline
    }

    component ActionButton: StyledRect {
        id: button

        required property string label
        required property color accent

        signal activated()

        implicitHeight: 26
        radius: Tokens.rounding.full
        color: Qt.alpha(button.accent, 0.16)
        border.width: 1
        border.color: Qt.alpha(button.accent, 0.42)

        StateLayer {
            color: button.accent
            onClicked: button.activated()
        }

        StyledText {
            anchors.centerIn: parent
            text: button.label
            color: button.accent
            font: Tokens.font.label.small
        }
    }

    component ProjectDelegate: StyledRect {
        id: projectRow

        required property var rowData

        readonly property bool current: root.activeProject === projectRow.rowData.path

        width: ListView.view.width
        implicitHeight: 56
        radius: Tokens.rounding.small
        color: projectRow.current ? Qt.alpha(root.accentTool, 0.14) : "transparent"
        border.width: projectRow.current ? 1 : 0
        border.color: Qt.alpha(root.accentTool, 0.42)

        StateLayer {
            color: root.accentTool
            onClicked: root.selectedProject = projectRow.rowData.path
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.small
            anchors.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            StyledRect {
                Layout.preferredWidth: 8
                Layout.preferredHeight: 8
                radius: Tokens.rounding.full
                color: projectRow.rowData.failures > 0 ? root.statusFail : root.statusPass
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: projectRow.rowData.name
                    color: root.textPrimary
                    elide: Text.ElideRight
                    font: Tokens.font.label.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: `${projectRow.rowData.sessions} sessions · ${projectRow.rowData.calls} calls`
                    color: root.textMuted
                    elide: Text.ElideRight
                    font: Tokens.font.label.small
                }
            }

            StyledText {
                visible: projectRow.rowData.failures > 0
                text: String(projectRow.rowData.failures)
                color: root.statusFail
                font: Tokens.font.mono.small
            }
        }
    }

    component IssueDelegate: StyledRect {
        id: issueRow

        required property var issueData

        readonly property color tone: issueRow.issueData.resolved ? root.statusPass : root.statusFail

        width: ListView.view.width
        implicitHeight: 74
        radius: Tokens.rounding.small
        color: root.insetColour
        border.width: 1
        border.color: root.hairline

        RowLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.small
            spacing: Tokens.spacing.small

            StyledRect {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: Tokens.rounding.small
                color: Qt.alpha(issueRow.tone, 0.15)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: issueRow.issueData.resolved ? "check" : "error"
                    color: issueRow.tone
                    fontStyle: Tokens.font.icon.small
                    fill: 1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: issueRow.issueData.tool.length > 0 ? issueRow.issueData.tool : "no tool"
                        color: root.textPrimary
                        font: Tokens.font.label.medium
                    }

                    StyledText {
                        text: `x${issueRow.issueData.count}`
                        color: issueRow.tone
                        font: Tokens.font.mono.small
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: issueRow.issueData.kind
                        color: root.textMuted
                        elide: Text.ElideLeft
                        font: Tokens.font.label.small
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: issueRow.issueData.message.length > 0 ? issueRow.issueData.message : "(no message recorded)"
                    color: root.textPrimary
                    elide: Text.ElideRight
                    font: Tokens.font.mono.small
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: `${root.dateLabel(issueRow.issueData.last)} · ${root.agoLabel(issueRow.issueData.last)} · ${issueRow.issueData.sig}`
                        color: root.textMuted
                        elide: Text.ElideRight
                        font: Tokens.font.label.small
                    }

                    ActionButton {
                        label: issueRow.issueData.resolved ? qsTr("Reopen") : qsTr("Resolve")
                        accent: issueRow.tone
                        onActivated: MemoryService.act(
                            issueRow.issueData.resolved ? "reopen" : "resolve",
                            [issueRow.issueData.sig, "--project", root.activeProject]
                        )
                    }
                }
            }
        }
    }

    component NoteDelegate: StyledRect {
        id: noteRow

        required property var noteData

        width: ListView.view.width
        implicitHeight: 58
        radius: Tokens.rounding.small
        color: root.insetColour
        border.width: 1
        border.color: root.hairline

        RowLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.small
            spacing: Tokens.spacing.small

            StyledRect {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: Tokens.rounding.small
                color: Qt.alpha(root.accentNote, 0.15)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "notes"
                    color: root.accentNote
                    fontStyle: Tokens.font.icon.small
                    fill: 1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: noteRow.noteData.text
                    color: root.textPrimary
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font: Tokens.font.body.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: `${noteRow.noteData.id} · ${root.dateLabel(noteRow.noteData.created)}`
                    color: root.textMuted
                    elide: Text.ElideRight
                    font: Tokens.font.label.small
                }
            }

            ActionButton {
                label: qsTr("Delete")
                accent: root.textMuted
                onActivated: MemoryService.act("forget", [noteRow.noteData.id])
            }
        }
    }

    component ToolDelegate: StyledRect {
        id: toolRow

        required property var toolData

        width: ListView.view.width
        implicitHeight: 44
        radius: Tokens.rounding.small
        color: "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.small
            anchors.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            StyledText {
                Layout.preferredWidth: 110
                text: toolRow.toolData.tool
                color: root.textPrimary
                elide: Text.ElideRight
                font: Tokens.font.label.medium
            }

            StyledRect {
                Layout.preferredWidth: Math.max(2, Math.round((toolRow.toolData.calls / Math.max(1, root.busiestTool)) * 120))
                Layout.fillHeight: true
                radius: Tokens.rounding.full
                color: Qt.alpha(toolRow.toolData.failures > 0 ? root.statusFail : root.accentTool, 0.35)
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: toolRow.toolData.failures > 0
                    ? `${toolRow.toolData.calls} calls · ${toolRow.toolData.failures} failed`
                    : `${toolRow.toolData.calls} calls`
                color: toolRow.toolData.failures > 0 ? root.statusFail : root.textMuted
                font: Tokens.font.mono.small
            }

            StyledText {
                Layout.preferredWidth: 60
                horizontalAlignment: Text.AlignRight
                text: root.secondsLabel(toolRow.toolData.totalMs)
                color: root.textMuted
                font: Tokens.font.mono.small
            }
        }
    }

    // --- Chrome ---------------------------------------------------------

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer
        border.width: 1
        border.color: root.hairline
    }

    StyledRect {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        height: 64
        radius: Tokens.rounding.medium
        color: root.panelColour
        border.width: 1
        border.color: root.hairline

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium

            StyledRect {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: Tokens.rounding.small
                color: Colours.palette.m3primary

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "psychology"
                    color: Colours.contrastOn(Colours.palette.m3primary)
                    fontStyle: Tokens.font.icon.medium
                    fill: 1
                }
            }

            ColumnLayout {
                spacing: 0

                StyledText {
                    text: qsTr("Agent Memory")
                    color: root.textPrimary
                    font: Tokens.font.title.small
                }

                StyledText {
                    Layout.maximumWidth: 320
                    text: root.activeProject.length > 0 ? root.activeProject : qsTr("no session recorded yet")
                    color: root.textMuted
                    elide: Text.ElideRight
                    font: Tokens.font.mono.small
                }
            }

            StyledRect {
                implicitHeight: 24
                radius: Tokens.rounding.full
                color: Qt.alpha(MemoryService.busy ? root.statusWarn : root.statusPass, 0.16)
                border.width: 1
                border.color: Qt.alpha(MemoryService.busy ? root.statusWarn : root.statusPass, 0.42)

                StyledText {
                    anchors.centerIn: parent
                    text: MemoryService.busy ? qsTr("FOLDING") : qsTr("READY")
                    color: MemoryService.busy ? root.statusWarn : root.statusPass
                    font: Tokens.font.label.small
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            StyledText {
                text: `${root.projectRows.length} projects`
                color: root.textMuted
                font: Tokens.font.mono.small
            }
        }
    }

    SplitView {
        id: workbench

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Tokens.spacing.medium
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        anchors.bottomMargin: Tokens.padding.large
        orientation: Qt.Horizontal

        handle: Item {
            implicitWidth: Tokens.spacing.medium

            StyledRect {
                anchors.centerIn: parent
                width: 1
                height: parent.height - Tokens.spacing.large
                color: root.hairline
            }
        }

        // --- Left: projects ---------------------------------------------

        StyledRect {
            SplitView.preferredWidth: 280
            SplitView.minimumWidth: 220
            radius: Tokens.rounding.medium
            color: root.panelColour
            border.width: 1
            border.color: root.hairline
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                SectionLabel {
                    text: qsTr("PROJECTS")
                }

                ListView {
                    id: projectList

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: root.projectRows

                    delegate: ProjectDelegate {
                        required property var modelData

                        rowData: modelData
                    }

                    ScrollBar.vertical: ScrollBar {}
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.empty
                    text: qsTr("No agent sessions recorded yet. Run a harness with its hooks plugin installed, then reopen this plane.")
                    color: root.textMuted
                    wrapMode: Text.Wrap
                    font: Tokens.font.label.small
                }
            }
        }

        // --- Middle: issues, notes, tools -------------------------------

        StyledRect {
            SplitView.fillWidth: true
            SplitView.minimumWidth: 360
            radius: Tokens.rounding.medium
            color: root.panelColour
            border.width: 1
            border.color: root.hairline
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: root.activeEntry ? root.activeEntry.name : qsTr("No project")
                        color: root.textPrimary
                        elide: Text.ElideRight
                        font: Tokens.font.title.small
                    }

                    StyledText {
                        text: root.activeEntry
                            ? `sessions=${root.activeEntry.sessions} turns=${root.activeEntry.turns} calls=${root.activeEntry.calls} failures=${root.activeEntry.failures}`
                            : ""
                        color: root.textMuted
                        elide: Text.ElideRight
                        font: Tokens.font.mono.small
                    }

                    StyledText {
                        visible: root.activeEntry && root.activeEntry.harnesses.length > 0
                        text: root.activeEntry ? root.activeEntry.harnesses.join(" ") : ""
                        color: root.accentNote
                        elide: Text.ElideLeft
                        font: Tokens.font.label.small
                    }
                }

                TabBar {
                    id: tabs

                    Layout.fillWidth: true
                    currentIndex: root.tab
                    onCurrentIndexChanged: root.tab = currentIndex

                    TabButton {
                        text: qsTr("Issues") + ` (${root.issueRows.length})`
                        font: Tokens.font.label.medium
                    }
                    TabButton {
                        text: qsTr("Notes") + ` (${root.noteRows.length})`
                        font: Tokens.font.label.medium
                    }
                    TabButton {
                        text: qsTr("Tools") + ` (${root.toolRows.length})`
                        font: Tokens.font.label.medium
                    }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.tab

                    // --- Issues -----------------------------------------

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Tokens.spacing.small

                            ListView {
                                id: issueList

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: 2
                                model: root.issueRows

                                delegate: IssueDelegate {
                                    required property var modelData

                                    issueData: modelData
                                }

                                ScrollBar.vertical: ScrollBar {}
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.issueRows.length === 0
                                text: qsTr("No failure signature for this project. A failing tool call is folded into one issue and counted, not one line per crash.")
                                color: root.textMuted
                                wrapMode: Text.Wrap
                                font: Tokens.font.label.small
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                TextField {
                                    id: noteInput

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    placeholderText: qsTr("remember something about this project")
                                    placeholderTextColor: root.textMuted
                                    color: root.textPrimary
                                    selectByMouse: true
                                    font: Tokens.font.mono.small
                                    leftPadding: Tokens.padding.medium
                                    rightPadding: Tokens.padding.medium
                                    topPadding: 0
                                    bottomPadding: 0

                                    background: StyledRect {
                                        radius: Tokens.rounding.full
                                        color: root.insetColour
                                        border.width: 1
                                        border.color: noteInput.activeFocus ? root.accentNote : root.hairline
                                    }

                                    onAccepted: root.addNote()
                                }

                                ActionButton {
                                    label: qsTr("Add note")
                                    accent: root.accentNote
                                    onActivated: root.addNote()
                                }
                            }
                        }
                    }

                    // --- Notes ------------------------------------------

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Tokens.spacing.small

                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: 2
                                model: root.noteRows

                                delegate: NoteDelegate {
                                    required property var modelData

                                    noteData: modelData
                                }

                                ScrollBar.vertical: ScrollBar {}
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.noteRows.length === 0
                                text: qsTr("No notes for this project yet. A note is the one thing the fold cannot learn on its own.")
                                color: root.textMuted
                                wrapMode: Text.Wrap
                                font: Tokens.font.label.small
                            }
                        }
                    }

                    // --- Tools ------------------------------------------

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Tokens.spacing.small

                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: 2
                                model: root.toolRows

                                delegate: ToolDelegate {
                                    required property var modelData

                                    toolData: modelData
                                }

                                ScrollBar.vertical: ScrollBar {}
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.toolRows.length === 0
                                text: qsTr("No tool calls folded for this project yet.")
                                color: root.textMuted
                                wrapMode: Text.Wrap
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }
            }
        }

        // --- Right: the digest, and what to do with it ------------------

        StyledRect {
            SplitView.preferredWidth: 360
            SplitView.minimumWidth: 300
            radius: Tokens.rounding.medium
            color: root.panelColour
            border.width: 1
            border.color: root.hairline
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    SectionLabel {
                        Layout.fillWidth: true
                        text: qsTr("CONTEXT DIGEST")
                    }

                    StyledText {
                        text: root.injectionState === "enabled" ? qsTr("INJECTED") : qsTr("NOT INJECTED")
                        color: root.injectionState === "enabled" ? root.statusPass : root.statusWarn
                        font: Tokens.font.label.small
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Tokens.rounding.small
                    color: root.insetColour
                    border.width: 1
                    border.color: root.hairline

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.small
                        clip: true
                        contentHeight: digestText.implicitHeight
                        contentWidth: digestText.implicitWidth

                        ScrollBar.vertical: ScrollBar {}

                        TextEdit {
                            id: digestText

                            width: Math.max(parent.width, implicitWidth)
                            text: MemoryService.contextText.length > 0 ? MemoryService.contextText : qsTr("The digest is written by the first build.")
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.WrapAnywhere
                            color: root.textPrimary
                            selectionColor: Qt.alpha(root.accentTool, 0.35)
                            selectedTextColor: root.textPrimary
                            font: Tokens.font.mono.small
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    ActionButton {
                        label: qsTr("Rebuild")
                        accent: root.accentTool
                        onActivated: MemoryService.build()
                    }

                    ActionButton {
                        Layout.fillWidth: true
                        label: root.injectionState === "enabled" ? qsTr("Remove from ~/.claude/CLAUDE.md") : qsTr("Inject into ~/.claude/CLAUDE.md")
                        accent: root.injectionState === "enabled" ? root.statusFail : root.statusPass
                        onActivated: MemoryService.act("inject", [root.injectionState === "enabled" ? "--disable" : "--enable"])
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Injection writes this digest between HTML comment markers in ~/.claude/CLAUDE.md, so the next Claude Code session starts knowing what broke before. Removing it takes the markers with it and leaves every other line alone.")
                    color: root.textMuted
                    wrapMode: Text.Wrap
                    font: Tokens.font.label.small
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: MemoryService.lastOutput.length > 0
                    text: MemoryService.lastOutput
                    color: root.textMuted
                    elide: Text.ElideRight
                    font: Tokens.font.mono.small
                }
            }
        }
    }

    // --- The only watch in the plugin -----------------------------------

    FileView {
        path: MemoryService.eventsPath
        watchChanges: true
        printErrors: false

        onFileChanged: rebuildDebounce.restart()
    }

    // One fold per change, at most: a harness write loop produces a burst,
    // and a fold per line would spend the whole session rebuilding.
    Timer {
        id: rebuildDebounce

        interval: 1500
        onTriggered: MemoryService.build()
    }

    Item {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        visible: root.empty

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - Tokens.padding.extraLarge * 2, 360)
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "psychology"
                color: Qt.alpha(root.textMuted, 0.5)
                fontStyle: Tokens.font.icon.extraLarge
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("No agent sessions recorded yet. Run a harness with its hooks plugin installed, then reopen this plane.")
                color: root.textMuted
                wrapMode: Text.Wrap
                font: Tokens.font.body.small
            }
        }
    }
}
