// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The pane's only link to the skills-manager CLI, and a singleton so every
// surface reads one cache rather than three copies.
//
// It talks to the plugin's own cli/skills.sh rather than to the CLI binary.
// That indirection is the point: the shell script owns a single resolution
// rule (which binary, from which of four places), so the pane and the
// terminal cannot disagree about which one they are driving, and a machine
// with no binary gets a JSON report instead of a parse error.
//
// `doctor --json` answers everything in one process, which is why the whole
// library, agent list, preset list and repository status arrive from a
// single refresh. Every mutation re-runs it, so the pane never renders a
// state the CLI has already moved past.
Singleton {
    id: root

    readonly property string pluginDir: `${Quickshell.env("HOME")}/.local/share/aphotic/plugins/skills`
    readonly property string wrapper: `${root.pluginDir}/cli/skills.sh`

    // Empty until the first refresh answers. The pane hides its controls
    // while it is empty rather than showing them over nothing.
    property bool available: false
    property string cliPath: ""
    property string cliSource: ""
    property string cliVersion: ""
    property string pinnedVersion: ""
    property bool versionMatches: false
    property string hint: ""

    property var repo: ({})
    property var skills: []
    property var agents: []
    property var presets: []

    property bool busy: false
    property string errorText: ""

    // A refused deploy is not an error to log and forget: the CLI declined
    // to overwrite something that is not ours, and the pane shows the paths
    // it protected. Kept separate from errorText for that reason.
    property var conflict: null
    property string lastAction: ""

    readonly property var libraryPath: root.repo?.base_dir ?? ""
    readonly property int skillCount: root.skills.length
    readonly property var installedAgents: root.agents.filter(a => a.installed)

    // One skill by name, or null. Used by the preview pane and by the
    // deploy buttons, which only ever have a name to work from.
    function skillNamed(name): var {
        return root.skills.find(s => s.name === name) ?? null;
    }

    function isDeployed(name, agentKey): bool {
        const skill = root.skillNamed(name);
        if (skill === null)
            return false;
        return (skill.deployed_to ?? []).includes(agentKey);
    }

    // One place decides which way a toggle goes, so the row chip and the
    // preview chip cannot disagree about what a click means.
    function toggleDeploy(name, agentKey): void {
        if (root.isDeployed(name, agentKey))
            root.undeploy(name, [agentKey]);
        else
            root.deploy(name, [agentKey]);
    }

    function _reset(): void {
        root.skills = [];
        root.agents = [];
        root.presets = [];
        root.repo = ({});
    }

    function _apply(data): void {
        root.available = data.ok === true;
        root.hint = data.hint ?? "";
        const cli = data.cli ?? {};
        root.cliPath = cli.path ?? "";
        root.cliSource = cli.source ?? "";
        root.cliVersion = cli.version ?? "";
        root.pinnedVersion = cli.pinned_version ?? "";
        root.versionMatches = cli.version_matches === true;
        root.repo = data.repo ?? ({});
        root.skills = data.skills ?? [];
        root.agents = data.agents ?? [];
        root.presets = data.presets ?? [];
    }

    function refresh(): void {
        if (doctor.running)
            return;
        root.busy = true;
        doctor.command = ["bash", root.wrapper, "doctor", "--json"];
        doctor.running = true;
    }

    // Everything that changes state goes through here. The command is the
    // wrapper's `raw` passthrough, so the argument list is the CLI's own
    // argv and nothing is re-quoted on the way in.
    function _mutate(label, args): void {
        if (mutate.running)
            return;
        root.busy = true;
        root.errorText = "";
        root.conflict = null;
        root.lastAction = label;
        mutate.command = ["bash", root.wrapper, "raw", "--json"].concat(args);
        mutate.running = true;
    }

    function deploy(name, agentKeys): void {
        let args = ["skills", "deploy", name];
        for (const key of agentKeys)
            args = args.concat(["--agent", key]);
        root._mutate(`deploy ${name}`, args);
    }

    function undeploy(name, agentKeys): void {
        let args = ["skills", "undeploy", name];
        for (const key of agentKeys)
            args = args.concat(["--agent", key]);
        root._mutate(`undeploy ${name}`, args);
    }

    function adopt(): void {
        root._mutate("adopt", ["skills", "adopt"]);
    }

    // Tags are a flat set on a skill, so one call adds or removes however
    // many the caller names. The pane's tag field sends one at a time.
    function addTag(name, tag): void {
        root._mutate(`tag ${name} +${tag}`, ["skills", "tag", "add", name, tag]);
    }

    function removeTag(name, tag): void {
        root._mutate(`tag ${name} -${tag}`, ["skills", "tag", "remove", name, tag]);
    }

    // The additive pair, not the legacy `presets apply`: apply replaces
    // whichever preset is active, and a plugin should not take that away
    // from a user with one click. Deploy adds, undeploy takes back, and
    // neither touches the preset's membership.
    function deployPreset(name): void {
        root._mutate(`deploy preset ${name}`, ["presets", "deploy", name]);
    }

    function undeployPreset(name): void {
        root._mutate(`undeploy preset ${name}`, ["presets", "undeploy", name]);
    }

    // The preview reads one skill's SKILL.md through `skills show`. It is a
    // separate process from refresh because it is only requested when a row
    // is selected, and the CLI returns the file body alongside the metadata.
    property var preview: null
    property string previewName: ""

    function showSkill(name): void {
        if (showProc.running)
            showProc.running = false;
        root.previewName = name;
        root.preview = null;
        showProc.command = ["bash", root.wrapper, "raw", "--json", "skills", "show", name];
        showProc.running = true;
    }

    // Shared exit handling. Error JSON arrives on stderr with a non-zero
    // exit and a `code`; a conflict carries `details.conflicts[].path`, and
    // anything unrecognised still has a `message`, which the pane shows
    // rather than a bare exit code.
    function _readError(exitCode, out, err): string {
        const text = err.trim() || out.trim();
        if (text.length > 0) {
            try {
                const parsed = JSON.parse(text);
                if (parsed.code === "TARGET_CONFLICT")
                    root.conflict = parsed;
                return parsed.message ?? parsed.error ?? `exit ${exitCode}`;
            } catch (e) {
                return text;
            }
        }
        return `the CLI exited with ${exitCode}`;
    }

    Process {
        id: doctor
        stdout: StdioCollector { id: doctorOut }
        stderr: StdioCollector { id: doctorErr }
        onExited: (exitCode, exitStatus) => {
            root.busy = false;
            // A non-zero exit is expected here: doctor reports "no binary"
            // that way, and it still printed a full JSON report.
            try {
                root._apply(JSON.parse(doctorOut.text));
            } catch (e) {
                root._reset();
                root.available = false;
                root.errorText = root._readError(exitCode, doctorOut.text, doctorErr.text);
            }
        }
    }

    Process {
        id: mutate
        stdout: StdioCollector { id: mutateOut }
        stderr: StdioCollector { id: mutateErr }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.busy = false;
                root.errorText = root._readError(exitCode, mutateOut.text, mutateErr.text);
                return;
            }
            // Re-read rather than patching the cache: the CLI is the only
            // thing that knows what it actually did, including the skills
            // a preset or adopt swept in besides the one named.
            root.refresh();
        }
    }

    Process {
        id: showProc
        stdout: StdioCollector { id: showOut }
        stderr: StdioCollector { id: showErr }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.errorText = root._readError(exitCode, showOut.text, showErr.text);
                return;
            }
            try {
                root.preview = JSON.parse(showOut.text);
            } catch (e) {
                root.errorText = `could not read ${root.previewName}`;
            }
        }
    }
}
