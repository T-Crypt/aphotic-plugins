// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import Quickshell
import qs.modules.plugins.skills

// Drives SkillsService against the stub CLI and checks what it published.
// One scenario per run, chosen by SKILLS_PROBE_MODE, so a test can hand the
// service an environment the happy path never reaches: a deploy the CLI
// refuses, and a machine with no binary at all.
ShellRoot {
    id: root

    readonly property string mode: Quickshell.env("SKILLS_PROBE_MODE") || "ok"
    readonly property string home: Quickshell.env("HOME")

    // The step the service's next quiescent moment should run. One slot, so
    // a signal arriving twice (busy settling, a preview landing) runs the
    // continuation once.
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
        Qt.quit();
    }

    function fail(message: string): void {
        console.error(`FAIL: ${message}`);
        Qt.quit();
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

        // busy drops before _apply runs in the same handler, so the read is
        // deferred a turn; otherwise every assertion would see the previous
        // refresh.
        function onBusyChanged(): void {
            if (!SkillsService.busy)
                Qt.callLater(root._continue);
        }

        function onPreviewChanged(): void {
            Qt.callLater(root._continue);
        }
    }

    function start(): void {
        SkillsService.refresh();
        root.after(root.loaded);
    }

    function loaded(): void {
        if (root.mode === "missing")
            return root.expectMissing();
        if (!root.check(SkillsService.available, `doctor reported no CLI: ${SkillsService.errorText}`))
            return;
        if (!root.checkEqual(SkillsService.cliSource, "override", "cli source"))
            return;
        if (!root.checkEqual(SkillsService.cliVersion, "1.42.0", "cli version"))
            return;
        if (!root.checkEqual(SkillsService.pinnedVersion, "1.42.0", "pinned version"))
            return;
        if (!root.check(SkillsService.versionMatches, "versionMatches should be true for the pinned stub"))
            return;
        if (!root.checkEqual(SkillsService.hint, "", "hint"))
            return;
        if (!root.checkEqual(SkillsService.skillCount, 2, "skill count"))
            return;
        if (!root.checkEqual(SkillsService.presets.length, 1, "preset count"))
            return;
        if (!root.checkEqual(SkillsService.installedAgents.length, 3, "installed agent count"))
            return;
        if (!root.check(SkillsService.libraryPath.endsWith("/.skills-manager"), `library path ${SkillsService.libraryPath}`))
            return;
        if (!root.check(SkillsService.skillNamed("demo-skill") !== null, "demo-skill should be in the library"))
            return;
        if (!root.checkEqual(SkillsService.skillNamed("nope"), null, "unknown skill lookup"))
            return;

        if (root.mode === "conflict")
            return root.expectConflict();

        if (!root.check(!SkillsService.isDeployed("demo-skill", "claude_code"), "demo-skill starts undeployed"))
            return;
        SkillsService.deploy("demo-skill", ["claude_code", "codex"]);
        root.after(root.deployed);
    }

    function deployed(): void {
        if (!root.check(SkillsService.errorText === "", `deploy reported ${SkillsService.errorText}`))
            return;
        if (!root.checkEqual(SkillsService.lastAction, "deploy demo-skill", "last action"))
            return;
        if (!root.check(SkillsService.isDeployed("demo-skill", "claude_code"), "claude_code should have the skill after deploy"))
            return;
        if (!root.check(SkillsService.isDeployed("demo-skill", "codex"), "codex should have the skill after deploy"))
            return;
        if (!root.check(!SkillsService.isDeployed("demo-skill", "opencode"), "opencode should not have been touched"))
            return;

        SkillsService.undeploy("demo-skill", ["codex"]);
        root.after(root.undeployed);
    }

    function undeployed(): void {
        if (!root.checkEqual(SkillsService.lastAction, "undeploy demo-skill", "last action"))
            return;
        if (!root.check(!SkillsService.isDeployed("demo-skill", "codex"), "codex should be clear after undeploy"))
            return;
        if (!root.check(SkillsService.isDeployed("demo-skill", "claude_code"), "claude_code should keep the skill"))
            return;

        SkillsService.addTag("demo-skill", "tested");
        root.after(root.tagged);
    }

    function tagged(): void {
        if (!root.check(SkillsService.errorText === "", `tag add reported ${SkillsService.errorText}`))
            return;
        const tags = SkillsService.skillNamed("demo-skill")?.tags ?? [];
        if (!root.check(tags.includes("tested"), `the tag should survive the re-read: ${JSON.stringify(tags)}`))
            return;

        SkillsService.removeTag("demo-skill", "tested");
        root.after(root.untagged);
    }

    function untagged(): void {
        const tags = SkillsService.skillNamed("demo-skill")?.tags ?? [];
        if (!root.check(!tags.includes("tested"), `the tag should be gone: ${JSON.stringify(tags)}`))
            return;

        SkillsService.deployPreset("Default");
        root.after(root.presetDeployed);
    }

    function presetDeployed(): void {
        if (!root.check(SkillsService.errorText === "", `preset deploy reported ${SkillsService.errorText}`))
            return;
        if (!root.checkEqual(SkillsService.lastAction, "deploy preset Default", "last action"))
            return;
        if (!root.checkEqual(SkillsService.presets.length, 1, "preset count after a preset deploy"))
            return;

        SkillsService.showSkill("demo-skill");
        root.after(root.previewed);
    }

    function previewed(): void {
        if (!root.check(SkillsService.preview !== null, `no preview: ${SkillsService.errorText}`))
            return;
        if (!root.checkEqual(SkillsService.preview.name, "demo-skill", "previewed skill"))
            return;
        if (!root.check(String(SkillsService.preview.markdown).includes("# Demo"), "the SKILL.md body should ride along with the metadata"))
            return;
        root.pass("the service reads the library, deploys, undeploys, tags, deploys a preset and previews");
    }

    function expectConflict(): void {
        if (!root.checkEqual(SkillsService.previewName, "", "no skill should be selected yet"))
            return;
        SkillsService.deploy("conflict-demo", ["claude_code"]);
        root.after(root.conflicted);
    }

    function conflicted(): void {
        if (!root.check(SkillsService.conflict !== null, "a refused deploy should be kept as a conflict, not dropped as a bare error"))
            return;
        if (!root.checkEqual(SkillsService.conflict.code, "TARGET_CONFLICT", "conflict code"))
            return;
        const paths = (SkillsService.conflict.details?.conflicts ?? []).map(c => c.path);
        if (!root.checkEqual(paths.length, 1, "conflict path count"))
            return;
        if (!root.checkEqual(paths[0], `${root.home}/.claude/skills/conflict-demo`, "protected path"))
            return;
        if (!root.check(SkillsService.errorText.length > 0, "the conflict should also carry its message"))
            return;
        if (!root.check(!SkillsService.isDeployed("conflict-demo", "claude_code"), "a refused deploy must not read as deployed"))
            return;
        root.pass("a refused deploy surfaces its protected paths and nothing changes");
    }

    function expectMissing(): void {
        if (!root.check(!SkillsService.available, "no binary should read as unavailable"))
            return;
        if (!root.checkEqual(SkillsService.cliPath, "", "cli path"))
            return;
        if (!root.checkEqual(SkillsService.skillCount, 0, "skill count"))
            return;
        if (!root.checkEqual(SkillsService.presets.length, 0, "preset count"))
            return;
        if (!root.checkEqual(SkillsService.libraryPath, "", "library path"))
            return;
        // The wrapper still exits non-zero here, and still printed a report.
        // If doctor's JSON had failed to parse, this is where errorText would
        // carry a parse error instead.
        if (!root.checkEqual(SkillsService.errorText, "", `doctor should have parsed: ${SkillsService.errorText}`))
            return;
        if (!root.check(SkillsService.hint.includes("is not installed"), `hint should name the missing binary: ${SkillsService.hint}`))
            return;
        root.pass("a machine with no binary gets a report, not a parse error");
    }

    Timer {
        interval: 20000
        running: true
        onTriggered: root.fail(`timed out in mode '${root.mode}' waiting on the service`)
    }

    Component.onCompleted: {
        if (root.mode !== "ok" && root.mode !== "conflict" && root.mode !== "missing") {
            root.fail(`unknown SKILLS_PROBE_MODE '${root.mode}'`);
            return;
        }
        root.start();
    }
}
