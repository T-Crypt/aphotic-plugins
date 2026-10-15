import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.plugins.agentMemory

// Drives MemoryService headlessly and prints one PASS or FAIL line per claim,
// which tests/test_memory_service.sh greps. Offscreen and windowless: this
// only ever instantiates the plugin's own state holder, never the plane, so
// nothing here needs the shell's service graph or a compositor.
//
// Two cases, chosen by MEMORY_SERVICE_CASE:
//   path    the state paths resolve, under the state home the shell says to
//           use, and they agree with the engine's own layout
//   build   the fold runs against a fixture event log under
//           APHOTIC_STATE_HOME, and everything the plane draws comes back
ShellRoot {
    id: root

    readonly property string testCase: Quickshell.env("MEMORY_SERVICE_CASE") ?? "path"

    property bool started: false
    property int ticks: 0

    function check(ok: bool, label: string): void {
        if (ok) {
            console.log(`PASS: ${label}`);
            return;
        }
        console.error(`FAIL: ${label}`);
    }

    function checkPaths(): void {
        root.check(MemoryService.stateHome.length > 0, "the state home resolved");
        root.check(MemoryService.eventsPath.indexOf(MemoryService.stateHome) === 0
                   && MemoryService.eventsPath.endsWith("agent-events.jsonl"),
                   "the watched log is the one the hooks write, under the state home");
        root.check(MemoryService.storePath.indexOf("agent-memory/store.json") >= 0,
                   "the store lives beside the digest");
        root.check(MemoryService.storePath.lastIndexOf("/", 0) === 0,
                   "the store path is absolute");
        root.check(MemoryService.cliPrefix === "memory", "the command verb is the manifest's");
        Qt.quit();
    }

    function checkBuild(): void {
        MemoryService.build();
    }

    Component.onCompleted: {
        if (root.testCase === "build")
            root.checkBuild();
    }

    Timer {
        interval: 100
        repeat: true
        running: true

        onTriggered: {
            root.ticks++;
            if (root.started)
                return;

            if (root.testCase !== "build") {
                if (root.ticks < 2)
                    return;
                root.started = true;
                root.checkPaths();
                return;
            }

            // The fold runs one process, then two `cat` reads. Wait for the
            // store and the digest rather than racing either.
            if (MemoryService.store === null || MemoryService.contextText.length === 0) {
                if (root.ticks > 60)
                    root.started = true;
                return;
            }

            root.started = true;

            // What the command answered, captured rather than discarded.
            root.check(MemoryService.lastOutput.indexOf("ok projects=") === 0,
                       "the runner captured the command's answer");
            root.check(!MemoryService.busy, "the runner is idle once the fold is done");

            const store = MemoryService.store;
            const repo = store.projects["/repo"];
            root.check(!!repo, "the fixture project folded into the store");
            if (repo) {
                root.check(repo.sessions === 1, "one session counted");
                root.check(repo.turns === 1, "one turn counted");
                root.check(repo.tools.bash.calls === 2, "both bash calls counted");
                root.check(repo.tools.bash.failures === 1, "the failed bash call counted once as a failure");
                root.check(repo.harnesses.omp === 1, "the harness is named");
            }

            const errors = store.errors ?? [];
            root.check(errors.length === 1, "one failure signature");
            if (errors.length > 0) {
                root.check(errors[0].tool === "bash", "the signature names the tool");
                root.check(errors[0].count === 1, "the signature counted one occurrence");
                root.check(errors[0].resolved === false, "the signature starts open");
            }

            // Everything the plane draws, in the shapes it draws them.
            const projects = MemoryService.projects();
            // Two session_start lines, two projects; the busiest comes first.
            root.check(projects.length === 2, "two project rows");
            root.check(projects.length > 0 && projects[0].path === "/repo", "the project row names its path");
            root.check(projects.length > 0 && projects[0].calls === 2, "the project row carries its calls");
            root.check(MemoryService.projectName("/repo") === "repo", "the project name is the basename");
            root.check(MemoryService.errorsFor("/repo").length === 1, "one issue row for that project");
            root.check(MemoryService.toolsFor("/repo").length === 1
                       && MemoryService.toolsFor("/repo")[0].calls === 2, "one tool row, counting both calls");
            root.check(MemoryService.notesFor("/repo").length === 0, "no notes yet");
            root.check(MemoryService.contextText.indexOf("project /repo") >= 0, "the digest names the project");
            root.check(MemoryService.contextText.indexOf("issue ") >= 0, "the digest carries the issue");

            // An action goes the same route as the build, and the store is
            // read back rather than assumed. The id the command answers
            // with is the one that gets forgotten, because a second run of
            // this probe starts from a store that already handed out the
            // first one.
            MemoryService.act("note", ["a note from the probe", "--project", "/repo"]);
        }
    }

    property int phase: 0

    Timer {
        interval: 100
        repeat: true
        running: root.started && root.phase < 2 && MemoryService.lastOutput.length > 0

        onTriggered: {
            const out = MemoryService.lastOutput.trim();
            if (root.phase === 0 && /^n[0-9]+$/.test(out)) {
                root.phase = 1;
                root.check(MemoryService.notesFor("/repo").length === 1,
                           "an action ran the command and the plane sees its result");
                root.check(out.length > 0, "the note answered with its id");
                MemoryService.act("forget", [out]);
            } else if (root.phase === 1 && out.indexOf("forgot ") === 0) {
                root.phase = 2;
                root.check(MemoryService.notesFor("/repo").length === 0, "forgetting removed the note");
                Qt.quit();
            }
        }
    }
}
