// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import Quickshell
import qs.modules.plugins.skills

// Instantiates every surface and shared part the manifest names, so a
// renamed property, a bad type or a binding that throws fails here rather
// than on a user's desktop. `aphotic plugin validate` only proves the files
// exist, which says nothing about whether they load.
//
// The surfaces import qs.config, qs.components and qs.services, which a bare
// `qs -p` probe cannot resolve on its own: the runner symlinks the core
// shell's modules into the probe's import path and hands it the stub CLI.
ShellRoot {
    id: root

    property var workspace: null

    Component {
        id: workspaceComponent
        SkillsWorkspace {}
    }

    Component {
        id: settingsComponent
        SkillsSettings {}
    }

    Component {
        id: rowComponent
        SkillRow {}
    }

    Component {
        id: chipComponent
        AgentChip {}
    }

    Component {
        id: previewComponent
        SkillPreview {}
    }

    // The step the service's next quiescent moment should run. One slot, so
    // a signal arriving twice runs the continuation once.
    property var _after: null

    function _continue(): void {
        const next = root._after;
        root._after = null;
        if (next)
            next();
    }

    function after(action): void {
        root._after = action;
    }

    function pass(message: string): void {
        console.log(`PASS: ${message}`);
        Qt.callLater(Qt.quit);
    }

    function fail(message: string): void {
        console.error(`FAIL: ${message}`);
        Qt.callLater(Qt.quit);
    }

    function check(condition: bool, message: string): bool {
        if (!condition) {
            root.fail(message);
            return false;
        }
        return true;
    }

    function checkEqual(actual, expected, what: string): bool {
        return root.check(actual === expected, `${what}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
    }

    Connections {
        target: SkillsService

        function onBusyChanged(): void {
            if (!SkillsService.busy)
                Qt.callLater(root._continue);
        }
    }

    function run(): void {
        root.workspace = workspaceComponent.createObject(null, {
            width: 1200,
            height: 800
        });
        if (!root.check(root.workspace !== null, "SkillsWorkspace should instantiate"))
            return;
        root.after(root.loaded);
    }

    function loaded(): void {
        if (!root.check(SkillsService.available, `the stub CLI should resolve: ${SkillsService.errorText}`))
            return;
        if (!root.checkEqual(root.workspace.visibleSkills.length, SkillsService.skillCount, "unfiltered list should show the whole library"))
            return;
        if (!root.check(root.workspace.selectedSkill === null, "nothing should be selected before a click"))
            return;

        // Filters are bindings, so reading them right after the write proves
        // the dependency is wired rather than merely parseable.
        root.workspace.searchText = "conflict";
        if (!root.checkEqual(root.workspace.visibleSkills.length, 1, "a search term should narrow the list"))
            return;
        if (!root.checkEqual(root.workspace.visibleSkills[0].name, "conflict-demo", "the search should keep the matching skill"))
            return;
        root.workspace.searchText = "";
        if (!root.checkEqual(root.workspace.visibleSkills.length, SkillsService.skillCount, "clearing the search should restore the list"))
            return;

        const tags = root.workspace.tagOptions;
        if (tags.length > 0) {
            root.workspace.tagFilter = tags[0];
            const kept = root.workspace.visibleSkills;
            if (!root.check(kept.length > 0, `the tag filter '${tags[0]}' should keep at least one skill`))
                return;
            for (const skill of kept) {
                if (!root.check((skill.tags ?? []).includes(tags[0]), `skill '${skill.name}' survived a filter it does not match`))
                    return;
            }
            root.workspace.tagFilter = "";
        }

        const sources = root.workspace.sourceOptions;
        if (sources.length > 1) {
            root.workspace.sourceFilter = sources[0];
            for (const skill of root.workspace.visibleSkills) {
                if (!root.checkEqual(skill.source_type, sources[0], "the source filter should keep only its own kind"))
                    return;
            }
            root.workspace.sourceFilter = "";
        }

        root.workspace.select(SkillsService.skills[0].name);
        if (!root.check(root.workspace.selectedSkill !== null, "selecting a skill should resolve its record"))
            return;
        if (!root.checkEqual(root.workspace.selectedSkill.name, SkillsService.skills[0].name, "the selected record"))
            return;

        const preview = previewComponent.createObject(null, {
            width: 400,
            height: 600,
            skill: root.workspace.selectedSkill
        });
        if (!root.check(preview !== null, "SkillPreview should instantiate"))
            return;
        if (!root.checkEqual(preview.agentChipCount, SkillsService.installedAgents.length, "one deploy chip per installed agent in the preview"))
            return;
        if (!root.checkEqual(preview.tagChipCount, (root.workspace.selectedSkill.tags ?? []).length, "one tag chip per tag in the preview"))
            return;

        const row = rowComponent.createObject(null, {
            width: 600,
            skill: root.workspace.selectedSkill
        });
        if (!root.check(row !== null, "SkillRow should instantiate"))
            return;
        if (!root.checkEqual(row.agentChipCount, SkillsService.installedAgents.length, "one deploy chip per installed agent in the row"))
            return;
        if (!root.checkEqual(row.tagChipCount, (root.workspace.selectedSkill.tags ?? []).length, "one tag chip per tag in the row"))
            return;

        // The list renders from the same filtered array the panel reads, so
        // the two counts have to match or the panel is showing something
        // other than what the list drew.
        if (!root.checkEqual(root.workspace.renderedRowCount, root.workspace.visibleSkills.length, "one row per visible skill"))
            return;

        const agent = SkillsService.installedAgents[0];
        const chip = chipComponent.createObject(null, {
            record: root.workspace.selectedSkill,
            agent: agent
        });
        if (!root.check(chip !== null, "AgentChip should instantiate"))
            return;
        // The chip reads deployed state off the record rather than calling
        // isDeployed(), so the two must agree or the row shows a lie.
        if (!root.checkEqual(chip.deployed, SkillsService.isDeployed(root.workspace.selectedSkill.name, agent.key), "the chip should agree with the service about deployed state"))
            return;

        const settings = settingsComponent.createObject(null, {
            width: 900,
            height: 600
        });
        if (!root.check(settings !== null, "SkillsSettings should instantiate"))
            return;
        if (!root.checkEqual(settings.agentRowCount, SkillsService.installedAgents.length, "one settings row per installed agent"))
            return;
        if (!root.checkEqual(settings.presetRowCount, SkillsService.presets.length, "one settings row per preset"))
            return;

        root.pass("every named surface and shared part instantiates and its bindings resolve");
    }

    Timer {
        interval: 25000
        running: true
        onTriggered: root.fail("timed out waiting on the service")
    }

    Component.onCompleted: root.run()
}
